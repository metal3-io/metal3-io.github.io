---
title: "Deploying OCI Container Images to Bare Metal with a Custom IPA Hardware Manager"
date: 2026-02-01
draft: false
categories: ["metal3", "ironic", "IPA", "OCI", "deployment", "bare metal"]
author: Serhii Ivanov
---

What if you could deploy any OCI container image directly to bare metal,
without building traditional disk images? Back in 2021, Dmitry Tantsur
[implemented custom deploy steps](https://owlet.today/posts/integrating-coreos-installer-with-ironic/)
for Ironic, enabling alternative deployment methods beyond the standard
image-based approach. This feature powers OpenShift's bare metal
provisioning with CoreOS, yet it remains surprisingly unknown to the
broader Metal3 community. This post aims to change that by providing an
example implementation of a custom IPA hardware manager that deploys
Debian-based container images with EFI boot, LVM root filesystem, and
optional RAID1 mirroring.

## The Problem with Traditional Image-Based Deployments

Traditional bare metal provisioning with Metal3 and Ironic typically
requires pre-built disk images. You need to maintain these images,
update them regularly, and ensure they contain all necessary drivers
and configurations. This approach has some drawbacks:

1. **Image building complexity** - Building and maintaining OS disk
   images is not as trivial as creating container images
1. **Software RAID limitations** - Image-based deployments with mdadm
   RAID and EFI boot require workarounds

What if we could leverage the container ecosystem instead? Container
registries already solve the distribution problem, and OCI images are
versioned, layered, simple to build and widely available. This approach
allows you to:

- Use standard container images from any registry
- Avoid maintaining custom disk images
- Easily switch between OS versions by updating `spec.image.url`
- Get RAID1 redundancy with minimal configuration

## Introducing the deb_oci_efi_lvm Hardware Manager

The [`DebOCIEFILVMHardwareManager`](https://github.com/s3rj1k/ironic-python-agent/blob/custom_deploy/ironic_python_agent/hardware_managers/deb_oci_efi_lvm.py)
is a custom IPA hardware manager that deploys Debian-based OCI container
images directly to bare metal. It
provides:

- **EFI boot support** - UEFI boot with GRUB, which unlike systemd-boot,
  supports booting from LVM on top of mdadm software RAID
- **LVM root filesystem** - Flexible volume management for the root
  partition
- **Optional RAID1** - Software mirroring across two disks for
  redundancy
- **Cloud-init integration** - Ironic [configdrive](https://book.metal3.io/bmo/instance_customization.html#implementation-notes)
  data is written directly to the root filesystem, no separate configdrive
  partition
- **Multi-architecture** - Supports x86_64 and ARM64 via OCI multi-arch
  images

## How It Works

The deployment process extracts an OCI image using Google's `crane` tool,
then installs the necessary boot infrastructure on top. The hardware
manager supports three methods for specifying the OCI image (in priority
order):

1. `spec.image.url` with `oci://` prefix (e.g., `oci://debian:12`)
1. Configdrive metadata annotation `bmh.metal3.io/oci_image`
1. Default fallback: `ubuntu:24.04`

Root device hints can be specified using either standard BareMetalHost
`rootDeviceHints` fields or a simplified format via the
`bmh.metal3.io/root_device_hints` annotation (e.g., `serial=ABC123` or
`wwn=0x123456`). For RAID1 configurations, provide two space-separated
values (e.g., `serial=ABC123 DEF456`).

> **Note:** Alternatively, `podman` can be used instead of `crane` for OCI
> image extraction, as it is readily available in CentOS Stream 9 and also
> has an export command. This would require code modifications to the
> hardware manager.

The hardware manager performs these steps during deployment:

1. **Resolve OCI image** - Check `image_source`, configdrive, or use default
1. **Resolve target disks** - Parse root device hints (serial or WWN)
1. **Clean existing data** - Wipe partitions, RAID arrays, and LVM based on
   disk wipe mode (`all` for RAID1, `target` for single disk by default)
1. **Partition disks** - Create 2GB EFI partition and LVM partition
   (with RAID1 if two disks are specified)
1. **Create filesystems** - FAT32 for EFI, ext4 for root LV
1. **Extract OCI image** - Use `crane export` piped to `tar` for rootfs
1. **Install packages** - Add cloud-init, GRUB, kernel, mdadm, lvm2
1. **Configure boot** - Set up GRUB, initramfs, and fstab
1. **Install bootloader** - GRUB to both EFI partitions for RAID1

### Disk Layout

The hardware manager creates the following partition layout:

| Partition | Size | Filesystem | Label | Mount Point |
|-----------|------|------------|-------|-------------|
| 1 (EFI) | 2 GB | FAT32 | EFI | /boot/efi |
| 2 (LVM/RAID) | Remaining | - | - | - |

The LVM configuration:

| Component | Name | Description |
|-----------|------|-------------|
| Volume Group | vg_root | Contains all logical volumes |
| Logical Volume | lv_root | Root filesystem (100% of VG) |
| Filesystem | ext4 | Label: ROOTFS |

For RAID1 configurations, both disks get identical partition tables,
with partition 2 forming a RAID1 array that serves as the LVM physical
volume.

## Configuration

### Basic Single-Disk Deployment

For a simple single-disk deployment, configure your BareMetalHost and
Metal3MachineTemplate as follows:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: my-server
  namespace: metal3
spec:
  online: true
  bootMode: UEFI
  # Preferred method: Use spec.image.url with oci:// prefix
  image:
    url: "oci://debian:12"
  rootDeviceHints:
    serialNumber: "DISK_SERIAL_NUMBER"
```

Alternatively, you can use annotations or simplified hint formats:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: my-server-alt
  namespace: metal3
  annotations:
    # Alternative: Override default ubuntu:24.04 via annotation
    bmh.metal3.io/oci_image: "debian:12"
    # Alternative: Use simplified hint format
    bmh.metal3.io/root_device_hints: "serial=DISK_SERIAL_NUMBER"
spec:
  online: true
  bootMode: UEFI
```

The hardware manager supports three methods for specifying the OCI image
(in priority order):

1. **spec.image.url** with `oci://` prefix (highest priority, recommended)
1. **Annotation** `bmh.metal3.io/oci_image` passed via Metal3DataTemplate
1. **Default** `ubuntu:24.04` (fallback)

Root device hints support both standard format (`serialNumber: "ABC123"`)
and simplified format via annotation (`bmh.metal3.io/root_device_hints: "serial=ABC123"`).

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: my-worker-template
  namespace: metal3
spec:
  template:
    spec:
      customDeploy:
        method: "deb_oci_efi_lvm"
      dataTemplate:
        name: my-data-template
```

### RAID1 Configuration

For production deployments requiring disk redundancy, specify two disk
serial numbers. The hardware manager supports multiple formats:

#### Method 1: Standard format with space-separated values

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: my-ha-server
  namespace: metal3
spec:
  online: true
  bootMode: UEFI
  image:
    url: "oci://debian:13"
  rootDeviceHints:
    # Two space-separated serial numbers enable RAID1
    serialNumber: "DISK1_SERIAL DISK2_SERIAL"
```

#### Method 2: Simplified format via annotation

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: my-ha-server-alt
  namespace: metal3
  annotations:
    bmh.metal3.io/oci_image: "debian:13"
    # Simplified RAID1 hint format
    bmh.metal3.io/root_device_hints: "serial=DISK1_SERIAL DISK2_SERIAL"
spec:
  online: true
  bootMode: UEFI
```

With RAID1 enabled, the hardware manager will:

- Clean both disks (remove existing partitions, RAID arrays, and LVM)
- Create identical partition layouts on both disks
- Set up a RAID1 array (`/dev/md0`) for the LVM physical volume
- Install GRUB to both EFI partitions
- Configure a GRUB update hook to sync EFI partitions via rsync

### Disk Wipe Mode Configuration

By default, the hardware manager wipes all block devices for RAID1
configurations (to prevent stray RAID/LVM metadata issues) and only target
disks for single-disk setups. You can override this behavior:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: my-server
  namespace: metal3
  annotations:
    # Control disk cleaning behavior
    # "all" - Wipe all block devices (recommended for RAID1)
    # "target" - Wipe only target disk(s) from root device hints
    bmh.metal3.io/disk_wipe_mode: "all"
spec:
  online: true
  bootMode: UEFI
  image:
    url: "oci://ubuntu:24.04"
  rootDeviceHints:
    serialNumber: "DISK_SERIAL_NUMBER"
```

The `disk_wipe_mode` annotation is useful when:

- You have multiple disks and want to ensure clean RAID/LVM state (`all`)
- You want to preserve data on non-target disks (`target`)
- You're migrating from a previous RAID configuration

### Metal3DataTemplate Configuration

When using annotations (instead of `spec.image.url`), configure your
Metal3DataTemplate to pass them to the configdrive:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3DataTemplate
metadata:
  name: my-data-template
  namespace: metal3
spec:
  clusterName: my-cluster
  metaData:
    fromAnnotations:
    # Optional: Pass OCI image annotation (only if not using spec.image.url)
    - key: oci_image
      object: baremetalhost
      annotation: "bmh.metal3.io/oci_image"
    # Optional: Pass simplified root device hint
    - key: root_device_hints
      object: baremetalhost
      annotation: "bmh.metal3.io/root_device_hints"
    # Optional: Pass disk wipe mode
    - key: disk_wipe_mode
      object: baremetalhost
      annotation: "bmh.metal3.io/disk_wipe_mode"
    objectNames:
    - key: name
      object: machine
    - key: local-hostname
      object: machine
    - key: local_hostname
      object: machine
    - key: metal3-name
      object: baremetalhost
    - key: metal3-namespace
      object: baremetalhost
  networkData:
    links:
      ethernets:
      - id: enp1s0
        macAddress:
          fromHostInterface: enp1s0
        type: phy
    networks:
      ipv4:
      - id: baremetalv4
        ipAddressFromIPPool: my-ip-pool
        link: enp1s0
        routes:
        - gateway:
            fromIPPool: my-ip-pool
          network: 0.0.0.0
          prefix: 0
    services:
      dns:
      - 8.8.8.8
```

> **Note:** When using `spec.image.url` with the `oci://` prefix, you don't
> need to pass the `oci_image` annotation through Metal3DataTemplate. The
> hardware manager reads directly from `instance_info.image_source`. This is
> the recommended approach for newer deployments.

## Building an IPA Image with the Hardware Manager

To use this hardware manager, you need to build a custom IPA ramdisk
image using
[ironic-python-agent-builder](https://opendev.org/openstack/ironic-python-agent-builder).
This tool uses [diskimage-builder](https://docs.openstack.org/diskimage-builder/latest/)
(DIB) to create bootable ramdisk images containing the IPA and any
custom elements you need.

### Required Packages

The hardware manager requires several packages to be present in the
IPA ramdisk:

| Package | Purpose |
|---------|---------|
| `crane` | OCI image extraction from container registries |
| `mdadm` | Software RAID array management |
| `lvm2` | Logical Volume Manager for root filesystem |
| `parted` | Disk partitioning |
| `dosfstools` | FAT32 filesystem creation for EFI partition |
| `grub2-efi-*` | UEFI bootloader installation |
| `curl` | Downloading files during deployment |
| `rsync` | EFI partition synchronization for RAID |

### Custom DIB Elements

DIB elements are modular components that customize the image build.
Each element is a directory containing scripts that run at different
phases of the build:

| Directory | Phase | Description |
|-----------|-------|-------------|
| `extra-data.d/` | Pre-build | Copy files into build environment |
| `install.d/` | Chroot | Run inside chroot during build |
| `post-install.d/` | Post-install | Run after package installation |
| `finalise.d/` | Finalize | Run at end of build process |

Scripts are named with a numeric prefix (e.g., `50-crane`) to control
execution order.

<!-- markdownlint-disable MD033 -->

<details>
  <summary>DIB element: crane (OCI image tool)</summary>
  <div markdown="1">

<!-- markdownlint-enable MD033 -->

Create a DIB element to install Google's `crane` tool for OCI image
extraction. Create the following directory structure:

```text
crane/
├── element-deps
└── install.d/
    └── 50-crane
```

The `element-deps` file can be empty or list dependencies. The install
script (`install.d/50-crane`):

```bash
#!/bin/bash

# https://docs.openstack.org/diskimage-builder/latest/developer/developing_elements.html

if [ "${DIB_DEBUG_TRACE:-0}" -gt 0 ]; then
    set -x
fi

set -eu
set -o pipefail

CRANE_VERSION="${DIB_CRANE_VERSION:-latest}"

# Detect architecture
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)
        CRANE_ARCH="x86_64"
        ;;
    aarch64)
        CRANE_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

echo "Installing crane (${CRANE_VERSION}) for ${CRANE_ARCH}..."

# Get the download URL
if [ "${CRANE_VERSION}" = "latest" ]; then
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/google/go-containerregistry/releases/latest |
        grep "browser_download_url.*Linux_${CRANE_ARCH}.tar.gz" |
        cut -d '"' -f 4)
else
    DOWNLOAD_URL="https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_${CRANE_ARCH}.tar.gz"
fi

if [ -z "${DOWNLOAD_URL}" ]; then
    echo "Failed to determine crane download URL"
    exit 1
fi

echo "Downloading crane from: ${DOWNLOAD_URL}"

# Download and extract crane
TEMP_DIR=$(mktemp -d)
curl -sL "${DOWNLOAD_URL}" | tar -xz -C "${TEMP_DIR}"

# Install crane binary
install -m 755 "${TEMP_DIR}/crane" /usr/local/bin/crane

# Cleanup
rm -rf "${TEMP_DIR}"

# Verify installation
if crane version; then
    echo "crane installed successfully"
else
    echo "crane installation verification failed"
    exit 1
fi
```

  </div>
</details>

<!-- markdownlint-disable MD033 -->

<details>
  <summary>DIB element: packages-install (extra packages)</summary>
  <div markdown="1">

<!-- markdownlint-enable MD033 -->

Create a DIB element that installs packages from the `DIB_EXTRA_PACKAGES`
environment variable:

```text
packages-install/
├── element-deps
└── install.d/
    └── 50-packages-install
```

The install script (`install.d/50-packages-install`):

```bash
#!/bin/bash

# https://docs.openstack.org/diskimage-builder/latest/developer/developing_elements.html

if [ "${DIB_DEBUG_TRACE:-0}" -gt 0 ]; then
    set -x
fi

set -eu
set -o pipefail

# Enable CRB (CodeReady Builder) repository and install EPEL
echo "Enabling CRB repository..."
dnf config-manager --set-enabled crb || true

# Detect CentOS version and install appropriate EPEL
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${VERSION_ID%%.*}" in
        9)
            echo "Installing EPEL for CentOS 9..."
            dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm || true
            ;;
        10)
            echo "Installing EPEL for CentOS 10..."
            dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm || true
            ;;
        *)
            echo "Unknown CentOS version: ${VERSION_ID}, skipping EPEL installation"
            ;;
    esac
fi

if [ -z "${DIB_EXTRA_PACKAGES:-}" ]; then
    echo "No extra packages specified via DIB_EXTRA_PACKAGES, skipping"
    exit 0
fi

echo "Updating system packages..."
dnf update -y

echo "Installing extra packages: ${DIB_EXTRA_PACKAGES}"

# shellcheck disable=SC2086
dnf install -y ${DIB_EXTRA_PACKAGES}

echo "Cleaning package cache..."
dnf clean all

echo "Extra packages installation complete"
```

  </div>
</details>

### Building the Image

Set the `ELEMENTS_PATH` to include your custom elements directory, then
run the builder:

```bash
export ELEMENTS_PATH="/path/to/your/dib-elements"

export DIB_EXTRA_PACKAGES="jq yq mdadm lvm2 curl parted util-linux \
    squashfs-tools xfsprogs dosfstools grub2-efi-x64 grub2-tools rsync"

ironic-python-agent-builder \
    -o ipa-custom \
    -e extra-hardware \
    -e crane \
    -e packages-install \
    --release 9-stream centos
```

This produces two files:

- `ipa-custom.kernel` - The Linux kernel
- `ipa-custom.initramfs` - The ramdisk containing IPA and tools

For ARM64 builds, the grub packages differ:

```bash
export DIB_EXTRA_PACKAGES="jq yq mdadm lvm2 curl parted util-linux \
    squashfs-tools xfsprogs dosfstools grub2-efi-aa64 grub2-tools rsync"
```

## Installing the Hardware Manager

The hardware manager must be placed in the IPA hardware managers directory
and registered in `setup.cfg`.

**File location:**

```text
ironic_python_agent/hardware_managers/deb_oci_efi_lvm.py
```

**setup.cfg entry point:**

Add the following entry to the `ironic_python_agent.hardware_managers`
section in `setup.cfg`:

```ini
[entry_points]
ironic_python_agent.hardware_managers =
    deb_oci_efi_lvm = ironic_python_agent.hardware_managers.deb_oci_efi_lvm:DebOCIEFILVMHardwareManager
```

This registers the hardware manager as a plugin, allowing IPA to
discover and load it at runtime.

### Source Code

The implementation is shown below in expandable sections. Full source:
[deb_oci_efi_lvm.py](https://github.com/s3rj1k/ironic-python-agent/blob/custom_deploy/ironic_python_agent/hardware_managers/deb_oci_efi_lvm.py).

> **Note:** The code below uses a custom `run_command` helper function
> instead of IPA's built-in
> [`ironic_python_agent.utils.execute`](https://opendev.org/openstack/ironic-python-agent/src/branch/master/ironic_python_agent/utils.py).
> This was a deliberate choice to minimize dependencies on IPA internals,
> avoiding the need to keep the hardware manager in constant sync with
> IPA changes. However, reusing IPA's existing utilities is a valid
> alternative approach.

<!-- markdownlint-disable MD033 -->

<details>
<summary>Imports and constants</summary>

Standard library and IPA imports, plus configuration constants for
device paths, filesystem labels, and retry parameters.

```python
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 s3rj1k

"""Debian/Ubuntu OCI EFI LVM deployment hardware manager.

This hardware manager deploys Debian-based OCI container images with:
- EFI boot partition
- LVM on root partition
- Optional RAID1 support for two-disk configurations
"""

import os
import platform
import re
import shutil
import stat as stat_module
import subprocess
import tempfile
import time

import yaml

from oslo_log import log

from ironic_python_agent import device_hints
from ironic_python_agent import hardware

LOG = log.getLogger(__name__)

# Default OCI image (can be overridden via node metadata 'oci_image')
DEFAULT_OCI_IMAGE = "ubuntu:24.04"

# Device/filesystem constants
RAID_DEVICE = "/dev/md0"
VG_NAME = "vg_root"
LV_NAME = "lv_root"
ROOT_FS_LABEL = "ROOTFS"
BOOT_FS_LABEL = "EFI"
BOOT_FS_LABEL2 = "EFI2"
DEVICE_PROBE_MAX_ATTEMPTS = 5
DEVICE_PROBE_DELAY = 5
DEVICE_WAIT_MAX_ATTEMPTS = 5
DEVICE_WAIT_DELAY = 5
```

</details>

<details>
<summary>run_command</summary>

Wrapper around `subprocess.run` with logging support.

```python
def run_command(cmd, check=True, capture_output=True, timeout=300):
    """Run a shell command with logging.

    :param cmd: Command as list of strings
    :param check: Whether to raise on non-zero exit
    :param capture_output: Whether to capture stdout/stderr
    :param timeout: Command timeout in seconds
    :returns: CompletedProcess object
    :raises: subprocess.CalledProcessError on failure if check=True
    """
    LOG.debug("Running command: %s", " ".join(cmd))
    result = subprocess.run(
        cmd, check=check, capture_output=capture_output, text=True, timeout=timeout
    )
    if result.stdout:
        LOG.debug("stdout: %s", result.stdout)
    if result.stderr:
        LOG.debug("stderr: %s", result.stderr)
    return result
```

</details>

<details>
<summary>is_efi_system</summary>

Checks if the system booted in UEFI mode by testing for `/sys/firmware/efi`.

```python
def is_efi_system():
    """Check if the system is booted in EFI mode.

    :returns: True if running under EFI, False otherwise
    """
    return os.path.isdir("/sys/firmware/efi")
```

</details>

<details>
<summary>probe_device</summary>

Runs `partprobe` and waits for device to appear in the kernel.

```python
def probe_device(device):
    """Probe device until it is visible in the kernel.

    :param device: Device path (e.g., /dev/sda)
    :raises: RuntimeError if device doesn't appear after max attempts
    """
    for attempt in range(DEVICE_PROBE_MAX_ATTEMPTS):
        run_command(["partprobe", device], check=False)
        time.sleep(DEVICE_PROBE_DELAY)
        if os.path.exists(device):
            LOG.debug("Device %s visible after %d attempt(s)", device, attempt + 1)
            return
    raise RuntimeError(
        f"Device {device} not visible after " f"{DEVICE_PROBE_MAX_ATTEMPTS} attempts"
    )
```

</details>

<details>
<summary>has_interactive_users</summary>

Checks for logged-in users via `who` command, used to pause deployment
for debugging via BMC console.

```python
def has_interactive_users():
    """Check if there are any interactive users logged in.

    Uses 'who' command to check for logged-in users, which indicates
    someone has connected via BMC console for debugging.

    :returns: Boolean indicating if interactive users are logged in
    """
    try:
        result = run_command(["who"], check=True, timeout=5)
        # who returns empty output if no users are logged in
        users = result.stdout.strip()
        if users:
            LOG.debug("Interactive users detected: %s", users)
            return True
        return False
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as e:
        LOG.warning("Failed to check for interactive users: %s", e)
        return False
```

</details>

<details>
<summary>get_configdrive_data</summary>

Extracts configdrive dictionary from node's `instance_info`.

```python
def get_configdrive_data(node):
    """Extract configdrive data from node instance_info.

    :param node: Node dictionary containing instance_info
    :returns: Dictionary containing configdrive data
    :raises: ValueError if node is invalid or configdrive data is missing
    """
    if node is None:
        raise ValueError("Node cannot be None")
    if not isinstance(node, dict):
        raise ValueError("Node must be a dictionary")

    instance_info = node.get("instance_info", {})
    if not isinstance(instance_info, dict):
        raise ValueError("instance_info must be a dictionary")

    configdrive = instance_info.get("configdrive")
    if configdrive is None:
        raise ValueError("configdrive not found in instance_info")

    if not isinstance(configdrive, dict):
        raise ValueError("configdrive must be a dictionary")

    LOG.info("Extracted configdrive data: %s", configdrive)
    return configdrive
```

</details>

<details>
<summary>parse_prefixed_hint_string</summary>

Parses simplified hint format like `serial=ABC123` or `wwn=0x123456` into
IPA hint dictionary format. Supports RAID1 with space-separated values.

```python
def parse_prefixed_hint_string(hint_string):
    """Parse a prefixed hint string into a hints dictionary.

    Supports simplified format for cloud-init/annotation use cases:
    - 'serial=ABC123' -> {'serial': 's== ABC123'}
    - 'wwn=0x123456' -> {'wwn': 's== 0x123456'}
    - 'serial=ABC123 DEF456' -> {'serial': 's== ABC123 DEF456'} (RAID1)
    - 'wwn=0x123 0x456' -> {'wwn': 's== 0x123 0x456'} (RAID1)

    :param hint_string: String with format 'hint_type=value1 [value2]'
    :returns: Dictionary containing root_device hints
    :raises: ValueError if format is invalid
    """
    if not hint_string or not isinstance(hint_string, str):
        raise ValueError("Hint string must be a non-empty string")

    hint_string = hint_string.strip()
    if "=" not in hint_string:
        raise ValueError(
            'Hint string must contain "=" separator. '
            'Expected format: "serial=VALUE" or "wwn=VALUE"'
        )

    # Split on first equals only
    parts = hint_string.split("=", 1)
    if len(parts) != 2:
        raise ValueError("Invalid hint string format")

    hint_type = parts[0].strip().lower()
    hint_values = parts[1].strip()

    if hint_type not in ("serial", "wwn"):
        raise ValueError(
            f'Unsupported hint type "{hint_type}". '
            'Only "serial" and "wwn" are supported.'
        )

    if not hint_values:
        raise ValueError(f"No value provided for {hint_type} hint")

    # Add s== operator prefix (string equality)
    hint_with_operator = f"s== {hint_values}"

    LOG.info(
        'Parsed prefixed hint string "%s" -> {"%s": "%s"}',
        hint_string,
        hint_type,
        hint_with_operator,
    )

    return {hint_type: hint_with_operator}
```

</details>

<details>
<summary>get_root_device_hints</summary>

Extracts root device hints from configdrive annotation or node's
`instance_info`. Supports both simplified string format
(`serial=ABC123`) and standard dictionary format.

```python
def get_root_device_hints(node, configdrive_data):
    """Extract root_device hints from node instance_info or annotation.

    Priority order:
    1. configdrive meta_data.root_device_hints (prefixed string format)
    1. node.instance_info.root_device (dict format with operators)

    :param node: Node dictionary containing instance_info
    :param configdrive_data: Configdrive dictionary
    :returns: Dictionary containing root_device hints
    :raises: ValueError if node is invalid or root_device not found anywhere
    """
    if node is None:
        raise ValueError("Node cannot be None")
    if not isinstance(node, dict):
        raise ValueError("Node must be a dictionary")

    instance_info = node.get("instance_info", {})
    if not isinstance(instance_info, dict):
        raise ValueError("instance_info must be a dictionary")

    # Check annotation first (via configdrive metadata)
    meta_data = configdrive_data.get("meta_data", {})
    annotation_hints = meta_data.get("root_device_hints")

    if annotation_hints is not None:
        # Annotations use prefixed string format only
        if not isinstance(annotation_hints, str):
            raise ValueError(
                "root_device_hints from annotation must be a string "
                'in format "serial=VALUE" or "wwn=VALUE"'
            )

        parsed_hints = parse_prefixed_hint_string(annotation_hints)
        LOG.info("Using root_device hints from annotation: %s", parsed_hints)
        return parsed_hints

    # Fall back to instance_info
    root_device = instance_info.get("root_device")
    if root_device is not None:
        if not isinstance(root_device, dict):
            raise ValueError("root_device must be a dictionary")
        LOG.info("Using root_device hints from instance_info: %s", root_device)
        return root_device

    # Neither source provided root_device hints
    raise ValueError("root_device hints not found in instance_info or annotation")
```

</details>

<details>
<summary>find_device_by_hints</summary>

Uses IPA's `device_hints` module to find a block device by serial or WWN.

```python
def find_device_by_hints(hints):
    """Find a single block device matching the given hints.

    :param hints: Dictionary containing device hints (serial or wwn)
    :returns: Device path (e.g., /dev/sda)
    :raises: ValueError if no device or multiple devices match
    """
    devices = hardware.list_all_block_devices()
    LOG.debug("list_all_block_devices returned type: %s", type(devices).__name__)
    LOG.info("Found %d block devices", len(devices))
    serialized_devs = [dev.serialize() for dev in devices]

    matched_raw = device_hints.find_devices_by_hints(serialized_devs, hints)
    matched = list(matched_raw)

    if not matched:
        raise ValueError(f"No device found matching hints: {hints}")

    if len(matched) > 1:
        device_names = [dev["name"] for dev in matched]
        raise ValueError(
            f"Multiple devices match hints: {device_names}. "
            f"Hints must match exactly one device."
        )

    return matched[0]["name"]
```

</details>

<details>
<summary>parse_hint_values</summary>

Parses hint strings, stripping operator prefixes and splitting multiple
values for RAID1 configurations.

```python
def parse_hint_values(hint):
    """Parse hint value, handling operator prefixes like 's=='.

    Returns list of values without the operator prefix.
    For RAID1: 's== SERIAL1 SERIAL2' -> ['SERIAL1', 'SERIAL2']
    For single: 's== SERIAL1' -> ['SERIAL1']
    For plain: 'SERIAL1 SERIAL2' -> ['SERIAL1', 'SERIAL2']

    :param hint: Hint string value (may include operator prefix)
    :returns: List of values without operator prefix
    """
    if not hint:
        return []

    parts = hint.split()

    # Check if first part is an operator (e.g., 's==', 'int', etc.)
    operators = ("s==", "s!=", "<in>", "<or>", "int", "float")
    if parts and parts[0] in operators:
        return parts[1:]  # Skip the operator

    return parts
```

</details>

<details>
<summary>resolve_root_devices</summary>

Resolves device paths from hints. Returns one device for single-disk
or two devices for RAID1 configuration.

```python
def resolve_root_devices(root_device_hints):
    """Resolve root device path(s) from hints.

    Only serial or wwn hints are supported. If the hint contains two
    space-separated values, both devices are resolved for RAID1 setup.

    :param root_device_hints: Dictionary containing root device hints
    :returns: Tuple of device paths - (primary,) for single device or
              (primary, secondary) for RAID1 configuration
    :raises: ValueError if device cannot be resolved or hints are invalid
    """
    if root_device_hints is None:
        raise ValueError("root_device_hints cannot be None")

    if not isinstance(root_device_hints, dict):
        raise ValueError("root_device_hints must be a dictionary")

    # Validate that only serial or wwn hints are present
    serial_hint = root_device_hints.get("serial")
    wwn_hint = root_device_hints.get("wwn")

    if not serial_hint and not wwn_hint:
        raise ValueError("root_device_hints must contain serial or wwn hint")

    # Check for unsupported hint types
    supported_hints = {"serial", "wwn"}
    provided_hints = set(root_device_hints.keys())
    unsupported = provided_hints - supported_hints

    if unsupported:
        raise ValueError(
            f"Unsupported root_device hints: {unsupported}. "
            f"Only serial and wwn are supported."
        )

    LOG.info("Resolving root devices from hints: %s", root_device_hints)

    # Parse hints - may contain one or two values (with optional operator)
    serial_values = parse_hint_values(serial_hint)
    wwn_values = parse_hint_values(wwn_hint)

    # Determine if this is a RAID1 configuration
    is_raid = len(serial_values) == 2 or len(wwn_values) == 2

    if is_raid:
        LOG.info("RAID1 configuration detected")

    # Resolve primary device
    primary_hints = {}
    if serial_values:
        primary_hints["serial"] = serial_values[0]
    if wwn_values:
        primary_hints["wwn"] = wwn_values[0]

    primary_device = find_device_by_hints(primary_hints)
    LOG.info("Resolved primary device: %s", primary_device)

    if not is_raid:
        return (primary_device,)

    # Resolve secondary device for RAID1
    secondary_hints = {}
    if len(serial_values) == 2:
        secondary_hints["serial"] = serial_values[1]
    if len(wwn_values) == 2:
        secondary_hints["wwn"] = wwn_values[1]

    secondary_device = find_device_by_hints(secondary_hints)
    LOG.info("Resolved secondary device: %s", secondary_device)

    return (primary_device, secondary_device)
```

</details>

<details>
<summary>get_oci_image</summary>

Gets OCI image reference with priority: `spec.image.url` (with `oci://`
prefix) > configdrive annotation > default `ubuntu:24.04`.

```python
def get_oci_image(node, configdrive_data):
    """Get OCI image from instance_info, metadata, or use default.

    Priority order:
    1. node.instance_info.image_source with oci:// prefix
    1. configdrive meta_data.oci_image (from annotation)
    1. DEFAULT_OCI_IMAGE

    :param node: Node dictionary containing instance_info
    :param configdrive_data: Configdrive dictionary
    :returns: OCI image reference string (without oci:// prefix)
    """
    oci_image = None

    # Check instance_info first
    instance_info = node.get("instance_info", {})
    image_source = instance_info.get("image_source", "").strip()

    if image_source.startswith("oci://"):
        oci_image = image_source.removeprefix("oci://").strip()
        if not oci_image:
            LOG.warning(
                "Empty OCI image after stripping oci:// prefix, "
                "falling back to annotation/default"
            )
            oci_image = None
        else:
            LOG.info("Using OCI image from instance_info: %s", oci_image)
    else:
        # Fall back to annotation (via configdrive metadata)
        meta_data = configdrive_data.get("meta_data", {})
        annotation_image = (meta_data.get("oci_image") or "").strip()

        if annotation_image:
            oci_image = annotation_image
            LOG.info("Using OCI image from annotation: %s", oci_image)
        else:
            # Fall back to default
            oci_image = DEFAULT_OCI_IMAGE
            LOG.info("Using default OCI image: %s", oci_image)

    return oci_image
```

</details>

<details>
<summary>get_disk_wipe_mode</summary>

Determines disk cleaning behavior based on annotation or setup type. Returns
`all` to wipe all block devices (default for RAID1) or `target` to wipe only
specified disks (default for single disk).

```python
def get_disk_wipe_mode(configdrive_data, is_raid):
    """Get disk wipe mode from configdrive or use default based on setup.

    Priority order:
    1. configdrive meta_data.disk_wipe_mode (from annotation)
    1. Default: "all" for RAID1, "target" for single disk

    :param configdrive_data: Configdrive dictionary
    :param is_raid: Boolean indicating if this is a RAID setup
    :returns: String "all" or "target"
    :raises: ValueError if disk_wipe_mode has invalid value
    """
    meta_data = configdrive_data.get("meta_data", {})
    wipe_mode = (meta_data.get("disk_wipe_mode") or "").strip().lower()

    if wipe_mode:
        if wipe_mode not in ("all", "target"):
            raise ValueError(
                f'Invalid disk_wipe_mode "{wipe_mode}". '
                'Valid values are: "all", "target"'
            )
        LOG.info("Using disk wipe mode from annotation: %s", wipe_mode)
        return wipe_mode

    # Use default based on setup type
    default_mode = "all" if is_raid else "target"
    LOG.info(
        "Using default disk wipe mode for %s setup: %s",
        "RAID1" if is_raid else "single disk",
        default_mode,
    )
    return default_mode
```

</details>

<details>
<summary>get_architecture_config</summary>

Returns architecture-specific settings for x86_64 or ARM64, including
GRUB packages and UEFI target.

```python
def get_architecture_config(oci_image):
    """Get architecture-specific configuration.

    :param oci_image: OCI image reference to use
    :returns: Dictionary with oci_image, oci_platform, uefi_target,
              and grub_packages
    :raises: RuntimeError if architecture is not supported
    """
    machine = platform.machine()

    if machine == "x86_64":
        return {
            "oci_image": oci_image,
            "oci_platform": "linux/amd64",
            "uefi_target": "x86_64-efi",
            "grub_packages": ["grub-efi-amd64", "grub-efi-amd64-signed", "shim-signed"],
        }
    elif machine == "aarch64":
        return {
            "oci_image": oci_image,
            "oci_platform": "linux/arm64",
            "uefi_target": "arm64-efi",
            "grub_packages": ["grub-efi-arm64", "grub-efi-arm64-bin"],
        }
    else:
        raise RuntimeError(f"Unsupported architecture: {machine}")
```

</details>

<details>
<summary>wait_for_device</summary>

Waits for a block device to become available with retries.

```python
def wait_for_device(device):
    """Wait for a block device to become available.

    :param device: Device path (e.g., /dev/sda)
    :returns: True if device is available
    :raises: RuntimeError if device doesn't appear
    """
    for attempt in range(DEVICE_WAIT_MAX_ATTEMPTS):
        if os.path.exists(device):
            try:
                mode = os.stat(device).st_mode
                if stat_module.S_ISBLK(mode):
                    LOG.info("Device %s is available", device)
                    return True
            except OSError:
                pass
        LOG.debug(
            "Waiting for device %s (attempt %d/%d)",
            device,
            attempt + 1,
            DEVICE_WAIT_MAX_ATTEMPTS,
        )
        time.sleep(DEVICE_WAIT_DELAY)

    raise RuntimeError(f"Device {device} did not become available")
```

</details>

<details>
<summary>get_partition_path</summary>

Returns partition path, handling NVMe and MMC naming conventions.

```python
def get_partition_path(device, partition_number):
    """Get the partition path for a device.

    :param device: Base device path (e.g., /dev/sda)
    :param partition_number: Partition number
    :returns: Partition path (e.g., /dev/sda1 or /dev/nvme0n1p1)
    """
    if re.match(r".*/nvme\d+n\d+$", device) or re.match(r".*/mmcblk\d+$", device):
        return f"{device}p{partition_number}"

    return f"{device}{partition_number}"
```

</details>

<details>
<summary>clean_device</summary>

Removes existing partitions, RAID arrays, LVM structures, and wipes
the device.

```python
def clean_device(device):
    """Clean a device of existing partitions, RAID, and LVM.

    :param device: Device path to clean
    """
    LOG.info("Cleaning device: %s", device)

    # Stop any RAID arrays using this device
    try:
        result = run_command(["lsblk", "-nlo", "NAME,TYPE", device], check=False)
        for line in result.stdout.strip().split("\n"):
            parts = line.split()
            if len(parts) >= 2 and parts[1] in (
                "raid1",
                "raid0",
                "raid5",
                "raid6",
                "raid10",
            ):
                raid_dev = f"/dev/{parts[0]}"
                run_command(["mdadm", "--stop", raid_dev], check=False)
    except Exception:
        pass

    # Remove LVM if present (check device and all its partitions)
    try:
        # Get all block devices (device + partitions)
        result = run_command(["lsblk", "-nlo", "NAME", device], check=False)
        all_devs = []
        for line in result.stdout.strip().split("\n"):
            name = line.strip()
            if name:
                all_devs.append(f"/dev/{name}")

        # Find all VGs that use any of these devices
        vgs_to_remove = set()
        for dev in all_devs:
            result = run_command(["pvs", dev], check=False)
            if result.returncode == 0:
                vg_result = run_command(
                    ["pvs", "--noheadings", "-o", "vg_name", dev], check=False
                )
                vg_name = vg_result.stdout.strip()
                if vg_name:
                    vgs_to_remove.add(vg_name)

        # Deactivate, remove all LVs and VGs
        for vg_name in vgs_to_remove:
            # Deactivate all LVs in this VG
            run_command(["lvchange", "-an", vg_name], check=False)

            lv_result = run_command(
                ["lvs", "--noheadings", "-o", "lv_path", vg_name], check=False
            )
            for lv_path in lv_result.stdout.strip().split("\n"):
                lv_path = lv_path.strip()
                if lv_path:
                    # Try dmsetup remove for stubborn LVs
                    dm_name = lv_path.replace("/dev/", "").replace("/", "-")
                    run_command(
                        ["dmsetup", "remove", "--retry", "-f", dm_name], check=False
                    )
                    run_command(["lvremove", "-ff", lv_path], check=False)
            run_command(["vgremove", "-ff", vg_name], check=False)

        # Remove PVs from all devices
        for dev in all_devs:
            run_command(["pvremove", "-ff", "-y", dev], check=False)
    except Exception:
        pass

    # Zero RAID superblocks
    run_command(["mdadm", "--zero-superblock", "--force", device], check=False)

    # Zero superblocks on partitions
    try:
        result = run_command(["lsblk", "-nlo", "NAME", device], check=False)
        base_name = os.path.basename(device)
        for line in result.stdout.strip().split("\n"):
            name = line.strip()
            if name and name != base_name:
                part_dev = f"/dev/{name}"
                run_command(
                    ["mdadm", "--zero-superblock", "--force", part_dev], check=False
                )
                run_command(["wipefs", "--all", "--force", part_dev], check=False)
    except Exception:
        pass

    # Wipe device
    run_command(["wipefs", "--all", "--force", device], check=False)
    run_command(["sgdisk", "--zap-all", device], check=False)

    # Sync filesystem buffers and wait for udev to settle
    run_command(["sync"], check=False)
    run_command(["udevadm", "settle"], check=False)

    # Probe until device is visible again
    probe_device(device)

    LOG.info("Device %s cleaned", device)
```

</details>

<details>
<summary>clean_all_devices</summary>

Cleans all block devices on the system to remove stray RAID/LVM metadata.
Useful when `disk_wipe_mode` is set to `all` (default for RAID1 setups).

```python
def clean_all_devices():
    """Clean all block devices to remove stray RAID/LVM metadata.

    Useful for nodes that may have multiple disks with old metadata
    from previous deployments.
    """
    LOG.info("Cleaning all block devices on the system")

    try:
        devices = hardware.list_all_block_devices()
        LOG.info("Found %d block devices to clean", len(devices))

        for device_obj in devices:
            device = device_obj.name
            try:
                clean_device(device)
            except Exception as e:
                LOG.warning("Error cleaning device %s: %s", device, e)

        LOG.info("Finished cleaning all block devices")
    except Exception as e:
        LOG.error("Error listing block devices: %s", e)
```

</details>

<details>
<summary>clean_partition_signatures</summary>

Cleans RAID, LVM, and filesystem signatures from a partition without
removing the partition itself. Used internally by `partition_disk()` to
clean partitions before creating RAID arrays, ensuring no stray metadata
causes issues.

```python
def clean_partition_signatures(partition):
    """Clean RAID, LVM, and filesystem signatures from a partition.

    Does not remove the partition itself, only metadata/signatures.

    :param partition: Partition path to clean
    """
    LOG.debug("Cleaning signatures from partition: %s", partition)
    run_command(["pvremove", "-ff", "-y", partition], check=False)
    run_command(["wipefs", "--all", "--force", partition], check=False)
    run_command(["mdadm", "--zero-superblock", "--force", partition], check=False)
```

</details>

<details>
<summary>partition_disk</summary>

Creates GPT partition table with EFI and LVM partitions. Sets up RAID1
array if second device is provided. Calls `clean_partition_signatures()`
before RAID creation to ensure clean metadata.

```python
def partition_disk(
    device, vg_name, lv_name, second_device=None, raid_device=RAID_DEVICE, homehost=None
):
    """Partition disk with EFI and LVM (optionally on RAID).

    :param device: Primary device path
    :param vg_name: Volume group name
    :param lv_name: Logical volume name
    :param second_device: Optional second device for RAID
    :param raid_device: RAID device path
    :param homehost: Hostname for RAID array
    :returns: Tuple of (is_raid, pv_device)
    """
    LOG.info("Partitioning disk: %s", device)

    wait_for_device(device)

    # Ensure udev has finished processing before partitioning
    run_command(["udevadm", "settle"], check=False)

    # Create GPT partition table
    run_command(["parted", "-s", device, "mklabel", "gpt"])

    # Create EFI partition (2GB)
    run_command(
        [
            "parted",
            "-s",
            "-a",
            "optimal",
            device,
            "mkpart",
            "primary",
            "fat32",
            "2MiB",
            "2050MiB",
        ]
    )
    run_command(["parted", "-s", device, "set", "1", "esp", "on"])

    # Create data partition (rest of disk)
    run_command(
        ["parted", "-s", "-a", "optimal", device, "mkpart", "primary", "2050MiB", "99%"]
    )

    is_raid = second_device is not None

    if is_raid:
        run_command(["parted", "-s", device, "set", "2", "raid", "on"])
    else:
        run_command(["parted", "-s", device, "set", "2", "lvm", "on"])

    # Wipe new partitions
    try:
        result = run_command(["lsblk", "-nlo", "NAME", device], check=False)
        base_name = os.path.basename(device)
        for line in result.stdout.strip().split("\n"):
            name = line.strip()
            if name and name != base_name:
                run_command(["wipefs", "-a", f"/dev/{name}"], check=False)
    except Exception:
        pass

    data_partition = get_partition_path(device, 2)
    pv_device = data_partition

    if is_raid:
        probe_device(device)
        probe_device(second_device)

        # Clone partition table to second device
        sfdisk_result = run_command(["sfdisk", "-d", device])
        LOG.debug("Cloning partition table to %s", second_device)
        sfdisk_proc = subprocess.run(
            ["sfdisk", "--force", second_device],
            input=sfdisk_result.stdout,
            capture_output=True,
            text=True,
            check=False,
        )
        if sfdisk_proc.stdout:
            LOG.debug("sfdisk stdout: %s", sfdisk_proc.stdout)
        if sfdisk_proc.stderr:
            LOG.debug("sfdisk stderr: %s", sfdisk_proc.stderr)
        if sfdisk_proc.returncode != 0:
            raise subprocess.CalledProcessError(
                sfdisk_proc.returncode,
                ["sfdisk", "--force", second_device],
                sfdisk_proc.stdout,
                sfdisk_proc.stderr,
            )

        # Randomize partition GUIDs on second device
        run_command(["sgdisk", "--partition-guid=1:R", second_device])
        run_command(["sgdisk", "--partition-guid=2:R", second_device])

        second_data_partition = get_partition_path(second_device, 2)
        probe_device(second_data_partition)

        if not homehost:
            raise RuntimeError("homehost required for RAID configuration")

        # Clean new partitions before creating RAID
        LOG.info("Cleaning partition signatures before RAID creation")
        clean_partition_signatures(data_partition)
        clean_partition_signatures(second_data_partition)

        # Create RAID array
        run_command(
            [
                "mdadm",
                "--create",
                raid_device,
                "--level=1",
                "--raid-devices=2",
                "--metadata=1.2",
                "--name=root",
                "--bitmap=internal",
                f"--homehost={homehost}",
                "--force",
                "--run",
                "--assume-clean",
                data_partition,
                second_data_partition,
            ]
        )

        # Sync filesystem buffers before continuing
        run_command(["sync"], check=False)
        time.sleep(5)
        pv_device = raid_device
    else:
        probe_device(device)

    # Create LVM
    run_command(["pvcreate", "-ff", "-y", "--zero", "y", pv_device])
    run_command(["vgcreate", "-y", vg_name, pv_device])
    run_command(["lvcreate", "-y", "-W", "y", "-n", lv_name, "-l", "100%FREE", vg_name])

    LOG.info("Disk partitioned successfully, is_raid=%s", is_raid)
    return is_raid, pv_device
```

</details>

<details>
<summary>create_filesystems</summary>

Creates FAT32 filesystem on EFI partition and ext4 on root LV.

```python
def create_filesystems(
    efi_partition,
    root_lv_path,
    boot_label=BOOT_FS_LABEL,
    root_label=ROOT_FS_LABEL,
    second_efi_partition=None,
    boot_label2=BOOT_FS_LABEL2,
):
    """Create filesystems on partitions.

    :param efi_partition: EFI partition path
    :param root_lv_path: Root LV path
    :param boot_label: EFI partition label
    :param root_label: Root partition label
    :param second_efi_partition: Second EFI partition for RAID
    :param boot_label2: Second EFI partition label
    """
    LOG.info("Creating filesystems")

    run_command(["mkfs.vfat", "-F", "32", "-n", boot_label, efi_partition])

    if second_efi_partition:
        run_command(
            ["mkfs.vfat", "-F", "32", "-n", boot_label2, second_efi_partition],
            check=False,
        )

    run_command(["mkfs.ext4", "-F", "-L", root_label, root_lv_path])

    LOG.info("Filesystems created")
```

</details>

<details>
<summary>setup_chroot</summary>

Mounts `/proc`, `/sys`, `/dev` and sets up DNS resolution in chroot.

```python
def setup_chroot(chroot_dir):
    """Set up chroot environment with necessary mounts.

    :param chroot_dir: Path to chroot directory
    """
    LOG.info("Setting up chroot: %s", chroot_dir)

    run_command(["mount", "-t", "proc", "proc", f"{chroot_dir}/proc"])
    run_command(["mount", "-t", "sysfs", "sys", f"{chroot_dir}/sys"])
    run_command(["mount", "--bind", "/dev", f"{chroot_dir}/dev"])
    run_command(["mount", "--bind", "/dev/pts", f"{chroot_dir}/dev/pts"])

    os.makedirs(f"{chroot_dir}/run", exist_ok=True)

    # Set up resolv.conf
    resolv_link = os.path.join(chroot_dir, "etc", "resolv.conf")
    if os.path.islink(resolv_link):
        target = os.readlink(resolv_link)
        if target.startswith("/"):
            target_path = os.path.join(chroot_dir, target.lstrip("/"))
        else:
            target_path = os.path.join(chroot_dir, "etc", target)

        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        shutil.copy("/etc/resolv.conf", target_path)
    else:
        shutil.copy("/etc/resolv.conf", resolv_link)

    LOG.info("Chroot setup complete")
```

</details>

<details>
<summary>teardown_chroot</summary>

Unmounts chroot bind mounts in reverse order.

```python
def teardown_chroot(chroot_dir):
    """Tear down chroot environment.

    :param chroot_dir: Path to chroot directory
    """
    LOG.info("Tearing down chroot: %s", chroot_dir)

    mounts = [
        f"{chroot_dir}/run",
        f"{chroot_dir}/dev/pts",
        f"{chroot_dir}/dev",
        f"{chroot_dir}/sys",
        f"{chroot_dir}/proc",
    ]

    for mount in mounts:
        try:
            result = run_command(["mountpoint", "-q", mount], check=False)
            if result.returncode == 0:
                run_command(["umount", "-l", mount])
        except Exception as e:
            LOG.warning("Error unmounting %s: %s", mount, e)

    LOG.info("Chroot teardown complete")
```

</details>

<details>
<summary>extract_oci_image</summary>

Extracts OCI image filesystem using `crane export` piped to `tar`.

```python
def extract_oci_image(image, platform, dest_dir):
    """Extract OCI image rootfs using crane.

    :param image: OCI image reference (e.g., ubuntu:24.04)
    :param platform: Target platform (e.g., linux/amd64)
    :param dest_dir: Destination directory for rootfs
    """
    LOG.info("Extracting OCI image %s (%s) to %s", image, platform, dest_dir)

    # Use crane export to extract the image filesystem
    # crane export outputs a tar stream, pipe to tar for extraction
    crane_cmd = ["crane", "export", "--platform", platform, image, "-"]
    tar_cmd = ["tar", "-xf", "-", "-C", dest_dir]

    LOG.info("Running: %s | %s", " ".join(crane_cmd), " ".join(tar_cmd))

    # Create pipeline: crane export | tar extract
    crane_proc = subprocess.Popen(
        crane_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    tar_proc = subprocess.Popen(
        tar_cmd, stdin=crane_proc.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    # Allow crane to receive SIGPIPE if tar exits
    crane_proc.stdout.close()

    # Wait for tar to complete
    tar_stdout, tar_stderr = tar_proc.communicate(timeout=1800)

    # Wait for crane to complete
    crane_proc.wait()

    if crane_proc.returncode != 0:
        _, crane_stderr = crane_proc.communicate()
        raise RuntimeError(
            f"crane export failed with code {crane_proc.returncode}: "
            f"{crane_stderr.decode() if crane_stderr else 'unknown error'}"
        )

    if tar_proc.returncode != 0:
        raise RuntimeError(
            f"tar extract failed with code {tar_proc.returncode}: "
            f"{tar_stderr.decode() if tar_stderr else 'unknown error'}"
        )

    if tar_stderr:
        LOG.debug("tar stderr: %s", tar_stderr.decode())

    LOG.info("OCI image extraction complete")
```

</details>

<details>
<summary>install_packages</summary>

Installs cloud-init, GRUB, kernel, and other required packages via apt.

```python
def install_packages(chroot_dir, grub_packages):
    """Install required packages in chroot.

    :param chroot_dir: Path to chroot directory
    :param grub_packages: List of GRUB packages to install
    """
    LOG.info("Installing packages in chroot")

    # Remove snap packages if present
    snap_path = os.path.join(chroot_dir, "usr", "bin", "snap")
    if os.path.exists(snap_path):
        snap_patterns = [
            "!/^Name|^core|^snapd|^lxd/",
            "/^lxd/",
            "/^core/",
            "/^snapd/",
            "!/^Name/",
        ]
        for pattern in snap_patterns:
            try:
                run_command(
                    [
                        "chroot",
                        chroot_dir,
                        "sh",
                        "-c",
                        f"snap list 2>/dev/null | awk '{pattern} {{print $1}}' | "
                        "xargs -rI{} snap remove --purge {}",
                    ],
                    check=False,
                )
            except Exception:
                pass

    # Update package lists
    run_command(["chroot", chroot_dir, "apt-get", "update"])

    # Remove unwanted packages one by one, ignoring errors for missing packages
    for pkg in ["lxd", "lxd-agent-loader", "lxd-installer", "snapd"]:
        run_command(
            ["chroot", chroot_dir, "apt-get", "--purge", "remove", "-y", pkg],
            check=False,
        )

    # Install required packages
    packages = [
        "cloud-init",
        "curl",
        "efibootmgr",
        "grub-common",
        "initramfs-tools",
        "lvm2",
        "mdadm",
        "netplan.io",
        "rsync",
        "sudo",
        "systemd-sysv",
    ] + grub_packages
    run_command(["chroot", chroot_dir, "apt-get", "install", "-y"] + packages)

    # Install kernel based on distro
    try:
        os_release_path = os.path.join(chroot_dir, "etc", "os-release")
        distro_id = None
        version_id = None
        if os.path.exists(os_release_path):
            with open(os_release_path, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("ID="):
                        distro_id = line.split("=")[1].strip().strip('"')
                    elif line.startswith("VERSION_ID="):
                        version_id = line.split("=")[1].strip().strip('"')

        if distro_id == "ubuntu" and version_id:
            # Ubuntu: install HWE kernel
            run_command(
                [
                    "chroot",
                    chroot_dir,
                    "apt-get",
                    "install",
                    "-y",
                    f"linux-generic-hwe-{version_id}",
                ],
                check=False,
            )
        elif distro_id == "debian":
            # Debian: install standard kernel metapackage
            arch = platform.machine()
            if arch == "x86_64":
                kernel_pkg = "linux-image-amd64"
            elif arch == "aarch64":
                kernel_pkg = "linux-image-arm64"
            else:
                kernel_pkg = "linux-image-" + arch
            run_command(
                ["chroot", chroot_dir, "apt-get", "install", "-y", kernel_pkg],
                check=False,
            )
    except Exception as e:
        LOG.warning("Error installing kernel: %s", e)

    # Clean up removed packages
    try:
        result = run_command(["chroot", chroot_dir, "dpkg", "-l"], check=False)
        rc_packages = []
        for line in result.stdout.split("\n"):
            if line.startswith("rc "):
                parts = line.split()
                if len(parts) >= 2:
                    rc_packages.append(parts[1])

        if rc_packages:
            run_command(
                ["chroot", chroot_dir, "apt-get", "purge", "-y"] + rc_packages,
                check=False,
            )
    except Exception:
        pass

    run_command(
        ["chroot", chroot_dir, "apt-get", "autoremove", "--purge", "-y"], check=False
    )

    LOG.info("Package installation complete")
```

</details>

<details>
<summary>write_hosts_file</summary>

Writes `/etc/hosts` with localhost and IPv6 entries.

```python
def write_hosts_file(mount_point, hostname):
    """Write /etc/hosts file with proper entries.

    :param mount_point: Root mount point
    :param hostname: System hostname
    """
    LOG.info("Writing /etc/hosts file")

    hosts_path = os.path.join(mount_point, "etc", "hosts")

    with open(hosts_path, "w", encoding="utf-8") as f:
        f.write(f"127.0.0.1\tlocalhost\t{hostname}\n")
        f.write("\n")
        f.write("# The following lines are desirable for IPv6 capable hosts\n")
        f.write("::1\tip6-localhost\tip6-loopback\n")
        f.write("fe00::0\tip6-localnet\n")
        f.write("ff00::0\tip6-mcastprefix\n")
        f.write("ff02::1\tip6-allnodes\n")
        f.write("ff02::2\tip6-allrouters\n")
        f.write("ff02::3\tip6-allhosts\n")

    LOG.info("/etc/hosts written with hostname: %s", hostname)
```

</details>

<details>
<summary>configure_cloud_init</summary>

Configures cloud-init NoCloud datasource with metadata, userdata, and
network config from configdrive.

```python
def configure_cloud_init(mount_point, configdrive_data):
    """Configure cloud-init with configdrive data.

    :param mount_point: Root mount point
    :param configdrive_data: Configdrive dictionary
    """
    LOG.info("Configuring cloud-init")

    cloud_init_cfg_dir = os.path.join(mount_point, "etc", "cloud", "cloud.cfg.d")
    os.makedirs(cloud_init_cfg_dir, exist_ok=True)

    nocloud_seed_dir = os.path.join(
        mount_point, "var", "lib", "cloud", "seed", "nocloud-net"
    )
    os.makedirs(nocloud_seed_dir, exist_ok=True)

    # Write datasource config
    datasource_cfg = os.path.join(cloud_init_cfg_dir, "99-nocloud-seed.cfg")
    with open(datasource_cfg, "w", encoding="utf-8") as f:
        f.write(
            """datasource_list: [ NoCloud, None ]
datasource:
  NoCloud:
    seedfrom: file:///var/lib/cloud/seed/nocloud-net/
"""
        )

    # Write meta-data
    meta_data = configdrive_data.get("meta_data", {})
    meta_data_path = os.path.join(nocloud_seed_dir, "meta-data")
    with open(meta_data_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(meta_data, f, default_flow_style=False)

    # Write user-data
    user_data = configdrive_data.get("user_data", "")
    user_data_path = os.path.join(nocloud_seed_dir, "user-data")
    with open(user_data_path, "w", encoding="utf-8") as f:
        f.write(user_data if user_data else "")

    # Write network-config if present
    network_data = configdrive_data.get("network_data", {})
    if network_data:
        network_config_path = os.path.join(nocloud_seed_dir, "network-config")
        with open(network_config_path, "w", encoding="utf-8") as f:
            yaml.safe_dump(network_data, f, default_flow_style=False)

    # Set permissions
    for filename in os.listdir(nocloud_seed_dir):
        filepath = os.path.join(nocloud_seed_dir, filename)
        os.chmod(filepath, 0o600)

    LOG.info("Cloud-init configuration complete")
```

</details>

<details>
<summary>write_fstab</summary>

Writes `/etc/fstab` with root and EFI entries, plus second EFI for RAID.

```python
def write_fstab(mount_point, root_label, boot_label, is_raid, boot_label2=None):
    """Write /etc/fstab.

    :param mount_point: Root mount point
    :param root_label: Root partition label
    :param boot_label: EFI partition label
    :param is_raid: Whether RAID is configured
    :param boot_label2: Second EFI partition label
    """
    LOG.info("Writing fstab")

    fstab_path = os.path.join(mount_point, "etc", "fstab")
    with open(fstab_path, "w", encoding="utf-8") as f:
        f.write(f"LABEL={root_label}\t/\text4\terrors=remount-ro\t0\t1\n")
        f.write(f"LABEL={boot_label}\t/boot/efi\tvfat\tumask=0077,nofail\t0\t1\n")

        if is_raid and boot_label2:
            f.write(
                f"LABEL={boot_label2}\t/boot/efi2\tvfat\t"
                f"umask=0077,nofail,noauto\t0\t2\n"
            )

    LOG.info("fstab written")
```

</details>

<details>
<summary>write_mdadm_conf</summary>

Writes `/etc/mdadm/mdadm.conf` with RAID array configuration.

```python
def write_mdadm_conf(mount_point):
    """Write mdadm configuration.

    :param mount_point: Root mount point
    """
    LOG.info("Writing mdadm.conf")

    mdadm_dir = os.path.join(mount_point, "etc", "mdadm")
    os.makedirs(mdadm_dir, exist_ok=True)

    mdadm_conf_path = os.path.join(mdadm_dir, "mdadm.conf")

    with open(mdadm_conf_path, "w", encoding="utf-8") as f:
        f.write("HOMEHOST <system>\n")
        f.write("MAILADDR root\n")

    # Append ARRAY lines from mdadm --detail --scan
    result = run_command(["mdadm", "--detail", "--scan", "--verbose"])
    with open(mdadm_conf_path, "a", encoding="utf-8") as f:
        for line in result.stdout.split("\n"):
            if line.startswith("ARRAY"):
                f.write(line + "\n")

    LOG.info("mdadm.conf written")
```

</details>

<details>
<summary>configure_initramfs</summary>

Configures initramfs-tools to include LVM and RAID modules.

```python
def configure_initramfs(chroot_dir, is_raid):
    """Configure initramfs-tools for LVM and optionally RAID.

    This ensures initramfs includes LVM modules.

    :param chroot_dir: Chroot directory path
    :param is_raid: Whether RAID is configured
    """
    LOG.info("Configuring initramfs-tools")

    initramfs_conf_dir = os.path.join(chroot_dir, "etc", "initramfs-tools", "conf.d")
    os.makedirs(initramfs_conf_dir, exist_ok=True)

    # Disable resume (no swap partition)
    resume_conf = os.path.join(initramfs_conf_dir, "resume")
    with open(resume_conf, "w", encoding="utf-8") as f:
        f.write("RESUME=none\n")

    # Force LVM inclusion in initramfs
    # This is needed because during chroot, LVM volumes may not be
    # detected by the initramfs-tools hooks
    initramfs_conf = os.path.join(
        chroot_dir, "etc", "initramfs-tools", "initramfs.conf"
    )
    if os.path.exists(initramfs_conf):
        with open(initramfs_conf, "r", encoding="utf-8") as f:
            content = f.read()
        # Set MODULES to "most" to include storage drivers
        content = re.sub(r"^MODULES=.*$", "MODULES=most", content, flags=re.MULTILINE)
        with open(initramfs_conf, "w", encoding="utf-8") as f:
            f.write(content)

    # Add LVM modules explicitly
    modules_file = os.path.join(chroot_dir, "etc", "initramfs-tools", "modules")
    lvm_modules = ["dm-mod", "dm-snapshot", "dm-mirror", "dm-zero"]
    if is_raid:
        lvm_modules.extend(["raid1", "md-mod"])

    existing_modules = set()
    if os.path.exists(modules_file):
        with open(modules_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    existing_modules.add(line)

    with open(modules_file, "a", encoding="utf-8") as f:
        for module in lvm_modules:
            if module not in existing_modules:
                f.write(f"{module}\n")

    LOG.info("initramfs-tools configuration complete")
```

</details>

<details>
<summary>setup_grub_defaults</summary>

Configures `/etc/default/grub` with root device and RAID options.

```python
def setup_grub_defaults(chroot_dir, root_label, is_raid):
    """Configure GRUB defaults.

    :param chroot_dir: Chroot directory path
    :param root_label: Root partition label
    :param is_raid: Whether RAID is configured
    """
    LOG.info("Setting up GRUB defaults")

    grub_default = os.path.join(chroot_dir, "etc", "default", "grub")

    with open(grub_default, "r", encoding="utf-8") as f:
        content = f.read()

    # Build GRUB_CMDLINE_LINUX
    cmdline = f"root=LABEL={root_label}"
    if is_raid:
        cmdline += " rd.auto=1"

    # Update GRUB_CMDLINE_LINUX
    content = re.sub(
        r"^#*\s*GRUB_CMDLINE_LINUX=.*$",
        f'GRUB_CMDLINE_LINUX="{cmdline}"',
        content,
        flags=re.MULTILINE,
    )

    # Update GRUB_DISABLE_LINUX_UUID
    if "GRUB_DISABLE_LINUX_UUID=" in content:
        content = re.sub(
            r"^#*\s*GRUB_DISABLE_LINUX_UUID=.*$",
            "GRUB_DISABLE_LINUX_UUID=true",
            content,
            flags=re.MULTILINE,
        )
    else:
        content += "\nGRUB_DISABLE_LINUX_UUID=true\n"

    # Add rootdelay for RAID
    if is_raid:
        if "GRUB_CMDLINE_LINUX_DEFAULT=" in content:
            if "rootdelay=" not in content:
                content = re.sub(
                    r'^(#*\s*GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)',
                    r"\1 rootdelay=10",
                    content,
                    flags=re.MULTILINE,
                )
        else:
            content += '\nGRUB_CMDLINE_LINUX_DEFAULT="rootdelay=10"\n'

    with open(grub_default, "w", encoding="utf-8") as f:
        f.write(content)

    LOG.info("GRUB defaults configured")
```

</details>

<details>
<summary>setup_grub_efi_sync</summary>

Creates GRUB hook script to sync EFI partitions for RAID redundancy.

```python
def setup_grub_efi_sync(chroot_dir, boot_label2):
    """Set up GRUB hook to sync EFI partitions for RAID.

    :param chroot_dir: Chroot directory path
    :param boot_label2: Second EFI partition label
    """
    LOG.info("Setting up GRUB EFI sync hook")

    grub_hook = os.path.join(chroot_dir, "etc", "grub.d", "90_copy_to_boot_efi2")

    with open(grub_hook, "w", encoding="utf-8") as f:
        f.write(
            f"""#!/bin/sh
# Sync GRUB updates to both EFI partitions for RAID redundancy
set -e

if mountpoint --quiet --nofollow /boot/efi; then
    mount LABEL={boot_label2} /boot/efi2 || :
    rsync --times --recursive --delete /boot/efi/ /boot/efi2/
    umount -l /boot/efi2
fi
exit 0
"""
        )

    os.chmod(grub_hook, 0o755)  # nosec B103
    LOG.info("GRUB EFI sync hook created")
```

</details>

<details>
<summary>class DebOCIEFILVMHardwareManager</summary>

Main hardware manager class implementing the `deb_oci_efi_lvm` deploy step.
Orchestrates the full deployment workflow.

```python
class DebOCIEFILVMHardwareManager(hardware.HardwareManager):
    """Hardware manager for OCI EFI LVM RAID deployment."""

    HARDWARE_MANAGER_NAME = "DebOCIEFILVMHardwareManager"
    HARDWARE_MANAGER_VERSION = "1.0"

    def evaluate_hardware_support(self):
        LOG.info("DebOCIEFILVMHardwareManager: " "evaluate_hardware_support called")
        return hardware.HardwareSupport.SERVICE_PROVIDER

    def get_deploy_steps(self, node, ports):
        LOG.info("DebOCIEFILVMHardwareManager: get_deploy_steps called")

        return [
            {
                "step": "deb_oci_efi_lvm",
                "priority": 0,
                "interface": "deploy",
                "reboot_requested": False,
                "argsinfo": {},
            },
        ]

    def deb_oci_efi_lvm(self, node, ports):
        """Deploy Debian-based OCI image with EFI, LVM, and optional RAID.

        :param node: Node dictionary containing deployment configuration
        :param ports: List of port dictionaries for the node
        :raises: ValueError if configuration is invalid
        :raises: RuntimeError if deployment fails
        """
        LOG.info("DebOCIEFILVMHardwareManager: " "deb_oci_efi_lvm called")
        LOG.info("DebOCIEFILVMHardwareManager: node: %s", node)
        LOG.info("DebOCIEFILVMHardwareManager: ports: %s", ports)

        if not is_efi_system():
            raise RuntimeError(
                "This deployment requires EFI boot mode. "
                "System is not booted in EFI mode."
            )

        try:
            # Extract configuration from node
            configdrive_data = get_configdrive_data(node)
            root_device_hints = get_root_device_hints(node, configdrive_data)
            resolved_devices = resolve_root_devices(root_device_hints)
            meta_data = configdrive_data.get("meta_data", {})
            metal3_name = meta_data.get("metal3-name")

            root_device_path = resolved_devices[0]
            second_device = resolved_devices[1] if len(resolved_devices) > 1 else None

            LOG.info(
                "DebOCIEFILVMHardwareManager: " "root_device_path: %s", root_device_path
            )
            if second_device:
                LOG.info(
                    "DebOCIEFILVMHardwareManager: " "second_device: %s (RAID1)",
                    second_device,
                )

            # Get OCI image and architecture-specific configuration
            oci_image = get_oci_image(node, configdrive_data)
            arch_config = get_architecture_config(oci_image)
            LOG.info(
                "DebOCIEFILVMHardwareManager: " "architecture config: %s", arch_config
            )

            # Get disk wipe mode
            is_raid_setup = second_device is not None
            wipe_mode = get_disk_wipe_mode(configdrive_data, is_raid_setup)

            # Clean devices based on wipe mode
            if wipe_mode == "all":
                LOG.info("Cleaning all block devices (wipe_mode: all)")
                clean_all_devices()
                wait_for_device(root_device_path)
                if second_device:
                    wait_for_device(second_device)
            else:  # wipe_mode == 'target'
                LOG.info("Cleaning only target device(s) (wipe_mode: target)")
                wait_for_device(root_device_path)
                clean_device(root_device_path)
                if second_device:
                    wait_for_device(second_device)
                    clean_device(second_device)

            # Partition disk
            is_raid, pv_device = partition_disk(
                root_device_path,
                VG_NAME,
                LV_NAME,
                second_device=second_device,
                raid_device=RAID_DEVICE,
                homehost=metal3_name,
            )

            # Get partition paths
            efi_partition = get_partition_path(root_device_path, 1)
            second_efi_partition = None
            if is_raid and second_device:
                second_efi_partition = get_partition_path(second_device, 1)

            root_lv_path = f"/dev/{VG_NAME}/{LV_NAME}"

            # Create filesystems
            create_filesystems(
                efi_partition,
                root_lv_path,
                boot_label=BOOT_FS_LABEL,
                root_label=ROOT_FS_LABEL,
                second_efi_partition=second_efi_partition,
                boot_label2=BOOT_FS_LABEL2,
            )

            # Mount root filesystem
            root_mount = tempfile.mkdtemp()
            run_command(["mount", root_lv_path, root_mount])

            try:
                # Extract OCI image rootfs
                extract_oci_image(
                    arch_config["oci_image"], arch_config["oci_platform"], root_mount
                )

                # Mount EFI partition
                efi_mount = os.path.join(root_mount, "boot", "efi")
                os.makedirs(efi_mount, exist_ok=True)
                run_command(["mount", efi_partition, efi_mount])

                try:
                    # Set up chroot
                    setup_chroot(root_mount)

                    try:
                        # Install packages
                        install_packages(root_mount, arch_config["grub_packages"])

                        # Configure cloud-init
                        configure_cloud_init(root_mount, configdrive_data)

                        # Write /etc/hosts
                        write_hosts_file(root_mount, metal3_name)

                        # Write fstab
                        write_fstab(
                            root_mount,
                            ROOT_FS_LABEL,
                            BOOT_FS_LABEL,
                            is_raid,
                            BOOT_FS_LABEL2,
                        )

                        # Configure GRUB
                        setup_grub_defaults(root_mount, ROOT_FS_LABEL, is_raid)

                        # RAID-specific configuration
                        if is_raid:
                            write_mdadm_conf(root_mount)
                            setup_grub_efi_sync(root_mount, BOOT_FS_LABEL2)

                            efi2_mount = os.path.join(root_mount, "boot", "efi2")
                            os.makedirs(efi2_mount, exist_ok=True)

                        # Install GRUB to EFI
                        run_command(
                            [
                                "chroot",
                                root_mount,
                                "grub-install",
                                f'--target={arch_config["uefi_target"]}',
                                "--efi-directory=/boot/efi",
                                "--bootloader-id=ubuntu",
                                "--recheck",
                            ]
                        )

                        # Configure initramfs for LVM (required for Debian)
                        configure_initramfs(root_mount, is_raid)

                        # Update GRUB config and initramfs
                        run_command(["chroot", root_mount, "update-grub"])
                        run_command(
                            [
                                "chroot",
                                root_mount,
                                "update-initramfs",
                                "-u",
                                "-k",
                                "all",
                            ]
                        )

                        # Install GRUB to second EFI partition for RAID
                        if is_raid and second_efi_partition:
                            efi2_mount = os.path.join(root_mount, "boot", "efi2")
                            try:
                                run_command(["mount", second_efi_partition, efi2_mount])
                                run_command(
                                    [
                                        "rsync",
                                        "-a",
                                        f"{root_mount}/boot/efi/",
                                        f"{root_mount}/boot/efi2/",
                                    ]
                                )
                                run_command(
                                    [
                                        "chroot",
                                        root_mount,
                                        "grub-install",
                                        f'--target={arch_config["uefi_target"]}',
                                        "--efi-directory=/boot/efi2",
                                        "--bootloader-id=ubuntu",
                                        "--recheck",
                                    ]
                                )
                            except Exception as e:
                                LOG.warning(
                                    "Error installing GRUB to second EFI: %s", e
                                )
                            finally:
                                result = run_command(
                                    ["mountpoint", "-q", efi2_mount], check=False
                                )
                                if result.returncode == 0:
                                    run_command(["umount", "-l", efi2_mount])

                    finally:
                        teardown_chroot(root_mount)

                finally:
                    # Unmount EFI partition
                    result = run_command(["mountpoint", "-q", efi_mount], check=False)
                    if result.returncode == 0:
                        run_command(["umount", "-l", efi_mount])

            finally:
                # Unmount root filesystem
                result = run_command(["mountpoint", "-q", root_mount], check=False)
                if result.returncode == 0:
                    run_command(["umount", "-l", root_mount])

                # Clean up temporary directories
                if root_mount and os.path.exists(root_mount):
                    try:
                        os.rmdir(root_mount)
                        LOG.debug("Cleaned up root mount directory: %s", root_mount)
                    except Exception as e:
                        LOG.warning(
                            "Failed to clean up root mount dir %s: %s", root_mount, e
                        )

            LOG.info(
                "DebOCIEFILVMHardwareManager: " "deb_oci_efi_lvm completed successfully"
            )

        except Exception as e:
            LOG.error("DebOCIEFILVMHardwareManager: " "deb_oci_efi_lvm failed: %s", e)
            raise

        finally:
            # Wait for interactive users to logout
            if has_interactive_users():
                LOG.info(
                    "DebOCIEFILVMHardwareManager: "
                    "interactive users detected, waiting for logout"
                )
                while has_interactive_users():
                    LOG.info(
                        "DebOCIEFILVMHardwareManager: "
                        "users still logged in, checking again "
                        "in 60 seconds"
                    )
                    time.sleep(60)
                LOG.info(
                    "DebOCIEFILVMHardwareManager: " "all interactive users logged out"
                )
```

</details>

<!-- markdownlint-enable MD033 -->

## Supported OCI Images

The hardware manager works with any Debian-based OCI image that has a
functional `apt` package manager. OCI multi-arch images are supported.
Tested images include:

- `ubuntu:24.04`
- `debian:13`

The key benefit of this approach is the ability to create custom OCI
images with your specific OS configuration, packages, and settings.
You can build and maintain your own Docker images and use them directly
as the root filesystem for bare metal deployments. The deployment process
installs additional packages (kernel, GRUB, cloud-init) on top of the
base image.

## Debugging Deployments

If a deployment fails, you can connect to the server via BMC console
during the IPA phase. The hardware manager includes a feature that
waits for interactive users to log out before completing, allowing
you to inspect the system state.

## Limitations and Considerations

The following are limitations of this specific `deb_oci_efi_lvm`
implementation, not of Metal3's custom deploy mechanism itself. The
custom deploy framework is flexible and allows implementing alternative
hardware managers with different capabilities.

1. **EFI only** - This implementation requires UEFI boot mode
1. **Debian-based only** - The package installation assumes `apt` is
   available
1. **Network required** - The IPA needs network access to pull OCI
   images from registries and install packages in target system
1. **Root device hints** - Only `serial` and `wwn` hints are supported
   for disk selection

## Conclusion

The `deb_oci_efi_lvm` hardware manager demonstrates how custom deploy
steps can extend Ironic's capabilities beyond traditional image-based
deployments. The source code and GitHub Actions for building custom IPA
images are available at
[s3rj1k/ironic-python-agent](https://github.com/s3rj1k/ironic-python-agent/tree/custom_deploy).

## Future Improvements

A potential enhancement could add native support for converting OpenStack
`network_data.json` format to cloud-init v1 network configuration during
deployment.

## References

- [Integrating CoreOS Installer with Ironic](https://owlet.today/posts/integrating-coreos-installer-with-ironic/) -
  Dmitry Tantsur's original blog post on custom deploy steps
- [Ironic Deploy Steps Documentation](https://docs.openstack.org/ironic/latest/contributor/deploy-steps.html)
- [Metal3 Custom Deploy Steps Design](https://github.com/metal3-io/metal3-docs/blob/main/design/baremetal-operator/deploy-steps.md)
- [OpenShift CoreOS Install Hardware Manager](https://github.com/openshift/ironic-agent-image/blob/main/hardware_manager/ironic_coreos_install.py)
