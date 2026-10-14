---
title: "DHCP-less Provisioning with Redfish Virtual Media and Preprovisioning Images"
date: 2026-10-14
draft: false
categories: ["metal3", "baremetal", "ironic", "networking", "virtual media"]
author: Kashif Khan, Adam Rozman
---

DHCP and an untagged provisioning network are not available in every
environment, yet the default Metal3 provisioning flow depends on both.

Metal3 deployments usually run a dnsmasq instance that, among other things,
acts as a DHCP server. For a lot of users the default path is: "connect the
machines to a provisioning network, let Ironic hand out an address over DHCP,
boot the provisioning agent ramdisk (usually the Ironic Python Agent, IPA) over
iPXE". But DHCP is not
always available. In certain operational environments DHCP is simply blocked,
some environments cannot dedicate an untagged provisioning VLAN, and some
operators prefer static addressing for predictability and auditability. There
are also edge computing use cases where the Ironic pod is in a different
L2 network and Ironic only has a route to specific baseboard management
controller (BMC) addresses via
TCP/IP and nothing more.

Metal3 supports a *DHCP-less* provisioning flow built on the
**Redfish virtual media** boot method and can be supplemented with other
features like **preprovisioning network data injection** and
**`preProvisioningImage` (PPI)** customization. This post covers why DHCP is normally
needed, how virtual media removes that requirement, what is in the shared image
versus configured per host, and how to configure a `BareMetalHost` (BMH) to use
all of it, with a step-by-step walkthrough at the end.

Ironic distinguishes two ways of booting the ramdisk, called
[*managed* and *unmanaged*][managed-unmanaged]. With managed boot, Ironic
itself configures the boot device, boot mode and power state of the host. With
unmanaged boot, the boot configuration (DHCP options, iPXE scripts) is provided
by infrastructure outside Ironic, and the host is simply set to boot from the
network. Virtual media and DHCP-less booting only work with managed boot, so
this article only covers the **managed** concept.

## Why DHCP is normally required

To see what we are removing, recall what happens in a standard "managed" Metal3
deployment. Provisioning is performed by a *preprovisioning image*, IPA,
a Linux ramdisk that runs in memory on the target
host and talks back to Ironic. Before IPA can do anything, the host has to:

1. Boot the IPA kernel and initramfs, and
1. Obtain an IP address and a route so the agent can reach the Ironic API.

With network boot (PXE/iPXE), both steps depend on DHCP. The firmware
broadcasts a DHCP request with PXE-specific options, and the DHCP server
replies with the location of the server that hosts the
bootable media. The embedded PXE firmware then fetches the iPXE binary over
TFTP or HTTP and chainloads it, and in most cases iPXE then downloads the IPA.
Once IPA is running it again relies on
DHCP to configure its network interface. This is why network boot requires a
*provisioning network*: an isolated L2 segment, usually an untagged VLAN, where
Ironic can safely run a DHCP server.

That model is simple and reliable, but it has constraints:

- A DHCP server must run on the provisioning network.
- The host must reach Ironic over L2, which limits how the network can be
  segmented.
- NIC bonding, tagged VLANs, and static addressing are difficult or impossible
  during the provisioning phase.
- In the provisioning L2 network, extra caution has to be exercised so that
  either only Ironic's dnsmasq-based DHCP is running, or all the DHCP servers
  in the specific L2 network are configured not to interfere with each
  other.

## How virtual media removes the DHCP requirement

Redfish (DMTF DSP0266) is an HTTP and JSON-based protocol for out-of-band
hardware management. The Redfish protocol is standardized by the Distributed
Management Task Force (DMTF) consortium. DMTF does not provide a specific Redfish client and server
implementation. BMC vendors implement their own server software and embed it
into the BMC firmware. Redfish clients can come from different sources.
Sometimes hardware vendors wrap them into their proprietary management tools,
but there exist many different open-source client implementations for many
different languages. To learn more about what open-source software uses
Redfish technologies, see the
[DMTF Redfish page](https://www.dmtf.org/standards/redfish).

One of Redfish's features is support for *virtual media*-based booting.
As part of the virtual media boot process, the standard allows transferring an
ISO 9660 image or other bootable media as a virtual disk. The transfer
could be conducted via a multitude of TCP/IP-based high-level protocols such
as HTTP, HTTPS, NFS, CIFS, FTP, SFTP, TFTP and SCP. The Redfish protocol also
provides functionality that allows the user to configure and initiate the
booting of the previously transferred image.

In the Redfish API request, the image specification can contain a field called
`TransferProtocolType` that governs which of the above-mentioned protocols is
used by the BMC to acquire the image.

Ironic itself supports a wider selection of transfer protocols, while out of
the box Metal3 users are limited to using either HTTP or HTTPS. The transfer
protocol is handled by the provisioner, which is usually Ironic, so Metal3
users don't need to configure it actively anywhere.

Now let's dive into the main question: how do Redfish and its
**virtual-media** feature remove the L2 and DHCP requirements from the
image transfer process?

Instead of making the fundamentally L2-based (i)PXE protocol handle the
image transfer, Ironic POSTs the URL of the ISO image to the
`VirtualMedia.InsertMedia` action of the BMC's Redfish API, for example
`/redfish/v1/Managers/{id}/VirtualMedia/{id}/Actions/VirtualMedia.InsertMedia`.
Depending on the vendor, the virtual media resource can also be located under
`/redfish/v1/Systems/{id}` instead of `/redfish/v1/Managers/{id}`. Whenever the
BMC is asked to execute a virtual-media boot, the BMC will look up the URL set
by the previously mentioned POST action and the BMC will handle the download
and mounting process based on the transfer protocol.

Initially, the request sent by Ironic (via the [Sushy][sushy] Redfish library)
only specifies the image URL:

```json
{
  "Image": "https://host/path/image.iso"
}
```

The other fields of the request are optional, and they are only added when
needed. If the BMC rejects the first request because it requires one of the
optional fields, the request is retried with the missing field added. A
request with all the transfer-related fields that Ironic may send looks like
this:

```json
{
  "Image": "https://host/path/image.iso",
  "Inserted": true,
  "WriteProtected": true,
  "TransferMethod": "Stream",
  "TransferProtocolType": "HTTPS"
}
```

- `TransferProtocolType` is derived from the scheme of the image URL (`HTTP` or
  `HTTPS`) when the BMC requires it, unless the protocol was explicitly
  configured in Ironic, in which case it is sent in the first request.
- `TransferMethod` is set to `Stream` when the BMC requires it.
- `Inserted` and `WriteProtected` default to `true` in the Redfish schema, so
  they are left out of the POST request, because some BMCs reject the request
  when these fields are present.

Some BMCs don't implement the `VirtualMedia.InsertMedia` action. In that case
Ironic falls back to sending a PATCH request directly to the virtual media
resource, for example `/redfish/v1/Managers/{id}/VirtualMedia/{id}`. The PATCH
request always contains `Inserted` and `WriteProtected` explicitly, because
some BMCs that use PATCH won't attach the virtual media without them.

Because the boot image is delivered *out of band* through the BMC via protocols
that do not rely on L2 connectivity, it is possible to boot hardware over L3
networks, with no DHCP at all.

To use virtual media, the user's hardware needs a BMC that supports the Redfish
virtual media feature, and in Metal3 the user has to select the virtual media
boot method through the BMC address scheme of the `BareMetalHost`.
The most common formats are:

<!-- markdownlint-disable MD013 -->

| Vendor          | BMC address format                                | Notes                                     |
|-----------------|---------------------------------------------------|-------------------------------------------|
| Generic Redfish | `redfish-virtualmedia://<host>:<port>/<systemID>` | **Must not** be used for Dell machines.   |
| Dell iDRAC      | `idrac-virtualmedia://<host>:<port>/<systemID>`   | Use this variant for Dell hardware.       |
| HPE iLO 5+      | `redfish-virtualmedia://<host>:<port>/<systemID>` | Requires recent iLO firmware.             |

<!-- markdownlint-enable MD013 -->

The `<systemID>` is the Redfish path to the particular server, since one Redfish
endpoint can manage several systems. For Dell machines it usually looks like
`/redfish/v1/Systems/System.Embedded.1`, while other vendors often use
`/redfish/v1/Systems/1`. The correct value can be found in the hardware
documentation. The carrier protocol can also be pinned with a `+http` or
`+https` suffix, for example `redfish-virtualmedia+https://...`; HTTPS is used
by default.

Note that adding the http(s) protocol identifier will only affect whether the
provisioner (usually Ironic) will talk to the BMC via http or https, the
protocol used for virtual media transfer is not affected by this BMH spec field.

Note that virtual media is an optional Redfish feature, and on some hardware it
requires an additional license. Check the
[supported hardware][supported-hardware] documentation before relying on this
approach.

## Configuring the ramdisk network with preprovisioning network data

Booting the ramdisk without DHCP is only half the problem. Once IPA is running,
it still needs a working network configuration to reach Ironic.

There are environments and use cases where the IPA network interface
configuration is not an issue. There could still be a DHCP server on the L2
network that is able to assign IPs to the interfaces even if the Ironic DHCP is
not in the same L2 network. Alternatively, users can embed static IP addresses
or use some client tool that discovers the IP addresses by communicating with
some other service outside the Metal3 stack.

In this article the focus will be on environments where DHCP is completely
absent and the upstream OpenStack IPA is in use without any modification unless
it is explicitly stated when PPI use cases are discussed in later sections.
The goal is to demonstrate the out of the box functionality of the upstream
Metal3 stack.

Metal3's answer to the IPA network interface configuration in a DHCP-less setup
is that the user can supply the preprovisioning interface configuration
on a BMH-specific basis via the BMH's `preprovisioningNetworkDataName`
spec.

The secret which the spec refers to describes the networking for the IPA
ramdisk (addresses, routes, bonds, VLANs and DNS), in the
[OpenStack `network_data.json`][network_data] format. It is the same format
used for the deployed operating system's `networkData`, so users who already
write network data for their instances will find it familiar.

The Bare Metal Operator (BMO) will send the content of the secret as a JSON
payload to the relevant
Ironic API endpoint in a very similar manner as it is done for the regular BMH
network data secret referenced by the `networkData` field.

## Difference in preprovisioning network data injection based on IPA format

Unlike the regular network data, the preprovisioning network data is not sent
over the network to IPA, because IPA most likely has no IP address and
therefore no TCP/IP route yet. Instead, Ironic injects it into the boot ISO as
`openstack/latest/network_data.json`.

Whether the injection happens depends on the format of the preprovisioning
image and the way the image is supplied to the BMH.

By default, the preprovisioning image is IPA. Because BMO's provisioner
interface is extensible, non-Ironic-based provisioners might use other
preprovisioning agents.

### Dynamically generated ISO from a kernel+initrd pair

If the user doesn't change anything related to the IPA format, the upstream
IPA-downloader init container downloads IPA as a tar file, which is extracted
into a kernel+initrd pair. For most users, this default pair is well suited for
the role of a preprovisioning image.

When IPA is supplied as a kernel+initrd pair, Ironic converts the pair into
a single node-specific ISO as part of the boot preparation process. During this
conversion, the preprovisioning network data is injected into the ISO image,
well before the ISO is downloaded by the BMC.

The data is applied inside the ramdisk by a first-boot tool. The default
community-supported IPA ramdisk uses [Glean][glean], a lightweight alternative
to *cloud-init*. A custom ramdisk built with *cloud-init* instead works
too, as long as the tool can consume the `network_data.json` format from a
configuration drive. Glean is only able to handle network configuration and
nothing more, it is not a replacement for a general-purpose first-boot
configuration manager.

Virtual media and network data connect here: the virtual media ISO that boots
the ramdisk also contains the `network_data.json`. There is no DHCP and no
separate metadata service; the network config travels with the boot image.

The data is supplied as a Kubernetes secret whose key is `networkData`, and
`BareMetalHost` references it with the `preprovisioningNetworkDataName` field.
The full commands and manifests are in the
[step-by-step walkthrough](#step-by-step-provisioning-a-host-without-dhcp)
below.

Preprovisioning network data is often the same configuration the user wants for
the deployed operating system. If `preprovisioningNetworkDataName` is set but
a separate `networkData` secret is not specified, Metal3 reuses the
preprovisioning secret for the deployed instance as well, so the network only has
to be configured once.

### The pre-built generic ISO

IPA can also be supplied as a pre-built ISO instead of a kernel+initrd
pair. Substituting the generic kernel+initrd pair with an ISO image in Ironic's
global configuration is possible, but it blocks the preprovisioning network
data injection.

Ironic always handles ISO IPA images as externally supplied images that are
ready to be used without any further customization. Even Ironic's node API
treats the two IPA formats separately, and they are configured through
different keys in the node's `driver_info`. A node that boots IPA from a
kernel+initrd pair, which Ironic can turn into a node-specific ISO, looks like
this:

```json
{
  "driver": "redfish",
  "boot_interface": "redfish-virtual-media",
  "driver_info": {
    "redfish_address": "https://192.168.1.13",
    "redfish_system_id": "/redfish/v1/Systems/1",
    "deploy_kernel": "http://172.22.0.2/images/ironic-python-agent.kernel",
    "deploy_ramdisk": "http://172.22.0.2/images/ironic-python-agent.initramfs"
  }
}
```

A node that boots a ready-made IPA ISO uses the `deploy_iso` key instead:

```json
{
  "driver": "redfish",
  "boot_interface": "redfish-virtual-media",
  "driver_info": {
    "redfish_address": "https://192.168.1.13",
    "redfish_system_id": "/redfish/v1/Systems/1",
    "deploy_iso": "http://172.22.0.2/images/ironic-python-agent.iso"
  }
}
```

Ironic treats the `deploy_iso` image as final: it is attached to the BMC as is,
so there is no step where the preprovisioning network data could be injected.
With `deploy_kernel` and `deploy_ramdisk`, Ironic builds the ISO itself and can
add the network data during that build.

### The preProvisioningImage resource

The ISO management approach above makes it clear that users can't rely on
Ironic or other provisioners to customize node-specific preprovisioning ISO
images. There is another way to customize such images though. BMO provides a
custom resource (CR) called `preProvisioningImage` for this specific use case.

When BMO registers a host with the PPI support enabled, it
automatically creates a `preProvisioningImage` Kubernetes resource with the
same name and namespace as the `BareMetalHost`.

To take advantage of the PPI functionality, users have to install a separate
controller manager that acts as the *PPI's image provider*. It reconciles
the `preProvisioningImage` resource, builds the image according to the spec,
records the resulting `imageUrl` in the status, and marks the image `Ready`.
A good example of such a PPI's image provider is the
[image-customization-controller](https://github.com/openshift/image-customization-controller)
of OpenShift.

Note that PPI also provides a status field for the kernel, meaning that a
PPI's image provider can build preprovisioning images both as an ISO and as a
kernel+initrd pair.

The upstream Metal3 project only offers the default PPI's image provider that
is built into BMO, and that provider does not build a customized image. It
returns the image URLs that were preconfigured through environment variables,
and every host gets the same URLs. With the default PPI's image provider, the
preprovisioning network data injection works exactly as it would with the
PPI feature turned off. The network data referenced by the BMH's
`preprovisioningNetworkDataName` spec field is injected by Ironic only if
IPA is provided as a kernel+initrd pair, and not when a pre-built ISO is
used. If both an ISO and a kernel+initrd pair are configured, the default PPI's
image provider [picks the ISO][ppi-format-selection] for virtual media hosts.
To keep the network data injection working, the `DEPLOY_ISO_URL` environment
variable of BMO has to be left unset. The same applies when the PPI feature is
turned off.

Note that this `Ready` condition gates every stage that boots the
preprovisioning image: `inspecting`, `preparing`, `deprovisioning` and
`servicing`. BMO will not proceed with these stages until the host's
`preProvisioningImage` reports `Ready`. So if a host is stuck in one of these
states, for example in `inspecting`, the `preProvisioningImage` status is the
first place to look (the step-by-step walkthrough below shows exactly how).

When a custom PPI's image provider is used, it can build a unique image per
host, for example by baking the network data straight into the ISO. BMO passes
the content of the network data secret to the provider unmodified, so a custom
provider can interpret and embed it however it likes. Either way, the
`BareMetalHost` API the user writes is identical. A PPI's image provider may
also convert the network data to a different format inside the image, so
configuration managers that don't follow the OpenStack network data
conventions can be used as well.

Putting the pieces together, the end-to-end flow is:

1. The user creates a `BareMetalHost` with a virtual media BMC address.
1. BMO creates a `preProvisioningImage` and fills out its spec, referencing the
   network data secret set in the BMH's `preprovisioningNetworkDataName` field.
1. The PPI's image provider returns (or builds) a ramdisk image URL and marks
   the image `Ready`.
1. BMO tells Ironic to boot the host from that image via Redfish virtual media.
1. The BMC mounts the ISO as a virtual CD-ROM; the host boots IPA with no DHCP.
1. IPA reads the static network configuration Metal3 supplied and brings up its
   interfaces.
1. IPA reaches Ironic over the configured L3 network, and inspection or
   provisioning proceeds as usual.

## What is in the image and what is per host

This is the most common question from users who do not want one identical image
for every host. This question can be answered only when the format of the
image is taken into consideration.

### When IPA is a kernel+initrd pair

The base ramdisk image is shared. The IPA kernel, the initramfs or root
filesystem, the agent itself, and the first-boot tool that applies the network
configuration (Glean by default, or cloud-init) are built into the image ahead
of time. In the default flow every host gets the same base image, either from
Ironic's global configuration or from the default PPI's image provider, which
hands the same fixed URLs to every host. Anything that must be code running
inside the ramdisk, such as a custom IPA plugin or an extra service, has to be
part of this image. Code cannot be supplied through network data.

The network configuration is per host and delivered at boot. The
`network_data.json` is not compiled into the shared base image. When Ironic
boots the host over virtual media, it builds a per-host ISO and injects the
network data into it. The first-boot tool inside the ramdisk reads the
injected network data on start-up and applies the addresses, routes,
bonds and VLANs.

Every host boots the same base ramdisk, but each one gets its own network
configuration at boot. This is why a hundred hosts can share one image URL and
still each get a unique static IP.

### When PPI is involved

When the `preProvisioningImage` relies on the default PPI's image provider, the
preprovisioning network data injection is handled the same way as with the
PPI feature turned off, as described in the sections above.

When a `preProvisioningImage` is used together with a custom PPI's image
provider, the rule of thumb is that the preprovisioning image (IPA) and all the
related configuration data are host-specific.

### Per-host kernel arguments (planned)

Per-host kernel command-line arguments through a
`preprovisioningExtraKernelParams` field on the `BareMetalHost` are proposed
in [BMO PR #2576][ppi-kernel-params]. The change is not in a released version
yet, so the field below will be rejected until it ships. Once it lands, it will
be useful for a mixed hardware fleet or for troubleshooting a single machine.

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: host-0
  namespace: my-cluster
spec:
  preprovisioningExtraKernelParams: "console=ttyS0,115200 intel_iommu=on"
  # ... bmc, preprovisioningNetworkDataName, and the rest
```

The proposed behavior depends on the image. With a BMO-generated image, the
arguments come only from the `BareMetalHost`. With an IPA ISO built by a
PPI's image provider, the ISO's own parameters win and the `BareMetalHost`
value is ignored. With a kernel+initrd pair, the kernel arguments coming from
the BMH and the PPI are combined.

### The guiding principle of the preprovisioning stage

By default, software and behavior are part of the image, while the network
configuration and the boot mode are set per host (and per-host kernel
arguments are planned).

Custom PPI's image providers change this picture. They are independent
controller managers that can be plugged into the workflow, and they can build
a unique image for each host with anything baked in, including the network
data itself. Each host then gets its own `imageUrl`. In the PPI model,
everything needed to make IPA usable over L3 is baked into the image.

## Step-by-step: provisioning a host without DHCP

This section walks through the process end to end, from an empty namespace to a
`BareMetalHost` that reaches `available` without a DHCP server. It is meant to
be followed in order to get a first host working.

The walkthrough expects that the BMC address and the BMC credentials of the
`BareMetalHost` are already correctly filled in by the user (including the
BMC credentials secret referenced by `credentialsName`), so these parts are not
explained here.

The walkthrough covers two setups. In the first one, the PPI feature is
disabled in BMO, and Ironic injects the network data into the ISO it builds
from the IPA kernel+initrd pair. In the second one, the PPI feature is enabled
and the default PPI's image provider of BMO is used. Steps 0 to 4 are the same
for both setups, and the differences are pointed out in Step 5 and Step 6.

In short, a DHCP-less host needs:

- a virtual media BMC address (for example `redfish-virtualmedia://` or
  `idrac-virtualmedia://`),
- a network data secret referenced by the BMH's
  `preprovisioningNetworkDataName` field, and
- optionally, for host-specific images, the `preProvisioningImage` support
  enabled in BMO and a PPI's image provider that handles the network data.

### Step 0: Check the prerequisites

Before starting, confirm the following:

- The server has a BMC that supports Redfish **virtual media**. Generic
  Redfish, Dell iDRAC (9, and 8 with recent firmware) and HPE iLO 5+ are the
  regularly tested options. On some hardware virtual media needs an extra
  license, so verify it in the BMC web UI first.
- BMO and Ironic are running in the management cluster.
  This can be checked with `kubectl get pods -n baremetal-operator-system` (the
  namespace may differ depending on the installation).
- BMO is configured with an IPA kernel+initrd pair through its
  `DEPLOY_KERNEL_URL` and `DEPLOY_RAMDISK_URL` environment variables, and
  `DEPLOY_ISO_URL` is left unset. If `DEPLOY_ISO_URL` is set, BMO
  [prefers the pre-built ISO][deploy-image-selection] for virtual media hosts
  and the network data cannot be injected. This applies to both setups.
- The static network the ramdisk should use is known up front. This means the
  IP address, netmask, default gateway and DNS server that let the host reach
  the Ironic API over L3.
- (Optional) The `preProvisioningImage` support is enabled in BMO. This is
  needed only when the user wants to use a PPI's image provider, for example
  to build node-specific IPA images. The feature is controlled by the
  `--build-preprov-image` BMO command-line flag and is off by default.

Pick a namespace to work in. This guide uses `my-cluster`:

```bash
kubectl create namespace my-cluster
```

### Step 1: Find out the MAC address

The `network_data.json` format binds configuration to a specific NIC by its MAC
address. If the MAC of the NIC that is cabled to the
network Ironic lives on is already known, this step can be skipped.

If the MAC is not known yet, the easiest way is to let Metal3 discover it.
Enroll the
host once with just the BMC details (no network data), let it inspect, and read
the discovered NICs from the resulting `HardwareData` resource:

```bash
kubectl get hardwaredata -n my-cluster host-0 \
  -o jsonpath='{.spec.hardware.nics}' | jq .
```

```json
[
  {
    "ip": "192.168.111.25",
    "mac": "00:f8:a8:a0:d0:d2",
    "model": "0x1af4 0x0001",
    "name": "enp2s0"
  },
  {
    "mac": "00:f8:a8:a0:d0:d0",
    "model": "0x1af4 0x0001",
    "name": "enp1s0"
  }
]
```

Note the `mac` of the interface that should be configured, as it is referenced
in the next step. In a strict DHCP-less environment the first inspection also
needs virtual media plus network data, so this step assumes that one
inspection with DHCP available is possible, or that the MAC is already known
from cabling records.

In a more restrictive environment there may be no prior knowledge of the
interfaces, no L2 connection, and no alternative DHCP server handing out IPs
to the machines. Even then there is hope. In these scenarios the user has
nothing more than a BMC address and BMC credentials, and the suggestion is to
use fast inspection, which performs a limited inspection by asking the BMC's
Redfish API for the NIC information, among other details.

Fast inspection usage information can be found
[here][fast-inspection].

### Step 2: Write the network_data.json

Create a file named `host-0-network.json`. Start with the simplest case: one
NIC, a static IPv4 address, a default route and a DNS server. Use the MAC
found in the previous step.

```json
{
  "links": [
    {
      "id": "enp1s0",
      "type": "phy",
      "ethernet_mac_address": "00:f8:a8:a0:d0:d0"
    }
  ],
  "networks": [
    {
      "id": "network0",
      "link": "enp1s0",
      "type": "ipv4",
      "ip_address": "192.168.1.20",
      "netmask": "255.255.255.0",
      "routes": [
        {
          "network": "0.0.0.0",
          "netmask": "0.0.0.0",
          "gateway": "192.168.1.1"
        }
      ]
    }
  ],
  "services": [
    {
      "type": "dns",
      "address": "8.8.8.8"
    }
  ]
}
```

Three things to keep straight in this format:

- `links` describe physical or virtual devices. Each physical `link` is matched
  to real hardware through `ethernet_mac_address`. The `id` is only an
  identifier used to reference the link from other parts of the file (for
  example from `networks`, `bond_links` or `vlan_link`); it is not used to
  rename the physical interface. Both Glean and cloud-init keep the name the
  kernel gave the NIC with the matching MAC, and name VLAN interfaces as
  `<parent>.<vlan_id>`. The exception is bonds: Glean uses the bond link's
  `id` as the bond interface name, while cloud-init generates its own name
  (such as `bond0`).
- `networks` describe L3 configuration and attach to a `link` through the `link`
  field. Use `"type": "ipv4"` for a static address (as above) or
  `"type": "ipv4_dhcp"` if that particular interface should still use DHCP.
- `services` are global helpers such as DNS servers.

If the provisioning traffic runs over a **bonded** pair of NICs on a **tagged
VLAN**, a common reason to use this feature, the same file grows into something
like this:

```json
{
  "links": [
    {
      "id": "eth0",
      "type": "phy",
      "ethernet_mac_address": "00:f8:a8:a0:d0:d0"
    },
    {
      "id": "eth1",
      "type": "phy",
      "ethernet_mac_address": "00:f8:a8:a0:d0:d2"
    },
    {
      "id": "bond0",
      "type": "bond",
      "ethernet_mac_address": "00:f8:a8:a0:d0:d0",
      "bond_links": ["eth0", "eth1"],
      "bond_mode": "802.3ad",
      "bond_xmit_hash_policy": "layer3+4"
    },
    {
      "id": "vlan100",
      "type": "vlan",
      "vlan_link": "bond0",
      "vlan_id": 100
    }
  ],
  "networks": [
    {
      "id": "provisioning",
      "link": "vlan100",
      "type": "ipv4",
      "ip_address": "192.168.1.20",
      "netmask": "255.255.255.0",
      "routes": [
        {
          "network": "0.0.0.0",
          "netmask": "0.0.0.0",
          "gateway": "192.168.1.1"
        }
      ]
    }
  ],
  "services": [
    {
      "type": "dns",
      "address": "8.8.8.8"
    }
  ]
}
```

This is exactly the kind of setup that plain PXE plus DHCP cannot handle during
provisioning, because PXE on most hardware needs untagged VLAN and supplies its
address over DHCP.

Two things to note about bonds. First, the `bond` link needs an
`ethernet_mac_address` of its own (Glean uses it as the bond's address); set it
to one of the member MACs. Second, Glean does not handle `bond_mode`,
`bond_xmit_hash_policy` and the other bond options consistently across
different Linux distributions, so verify the resulting bond configuration in
the ramdisk, and configure the switch side accordingly for the expected mode.

### Step 3: Create the network data secret

Turn the file into a secret. The key inside the secret **must** be `networkData`
or Metal3 will not find it:

```bash
kubectl create secret generic host-0-preprov-networkdata \
  -n my-cluster \
  --from-file=networkData=host-0-network.json
```

Verify it was created with the right key:

```bash
kubectl get secret host-0-preprov-networkdata -n my-cluster \
  -o jsonpath='{.data.networkData}' | base64 -d | jq .
```

### Step 4: Write and apply the BareMetalHost

The two fields that make this a DHCP-less flow are the virtual media BMC
`address` and `preprovisioningNetworkDataName`:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: host-0
  namespace: my-cluster
spec:
  online: true
  bootMode: UEFI
  bootMACAddress: 80:c1:6e:7a:e8:10
  bmc:
    address: redfish-virtualmedia://192.168.1.13/redfish/v1/Systems/1
    credentialsName: host-0-bmc
    disableCertificateVerification: true
  preprovisioningNetworkDataName: host-0-preprov-networkdata
```

A few notes on the fields:

- Use `idrac-virtualmedia://` instead of `redfish-virtualmedia://` for Dell
  hardware, and set the correct `<systemID>` for the vendor
  (`/redfish/v1/Systems/System.Embedded.1` on Dell, `/redfish/v1/Systems/1` on
  many others).
- `bootMACAddress` is the MAC used to identify the host during boot. It is not
  necessarily the same NIC that is configured in `network_data.json`.
- `disableCertificateVerification: true` is convenient in a lab where the BMC
  uses a self-signed certificate. In production, provision a trusted certificate
  and drop this line.
- Because we set `preprovisioningNetworkDataName` but no separate `networkData`,
  Metal3 will reuse this same secret to configure the deployed operating system
  later. If a different network is needed for the final OS, add a `networkData`
  secret reference as well.

Save this manifest into a file and apply it:

```bash
kubectl apply -f host-0.yaml
```

### Step 5: Watch it come up

Watch the host move through its states. With virtual media and preprovisioning
network data configured, the host should go through `registering` and
`inspecting` and land on `available`, all without a DHCP server. This part
looks the same in both setups:

```bash
kubectl get bmh -n my-cluster -w
```

```text
NAME     STATE          CONSUMER   ONLINE   ERROR   AGE
host-0   registering               true             20s
host-0   inspecting                true             45s
host-0   available                 true             3m
```

#### Without the PPI feature

When the PPI feature is disabled, BMO does not create a `preProvisioningImage`,
so the `BareMetalHost` is the resource to check:

```bash
kubectl get bmh host-0 -n my-cluster -o json | jq '.status |
  {operationalStatus, errorMessage, provisioning: (.provisioning | {state, ID, bootMode})}'
```

```json
{
  "operationalStatus": "OK",
  "errorMessage": "",
  "provisioning": {
    "state": "inspecting",
    "ID": "4a1b2c3d-5e6f-4a7b-8c9d-0e1f2a3b4c5d",
    "bootMode": "UEFI"
  }
}
```

The `ID` is the UUID of the Ironic node that belongs to this host, and an empty
`errorMessage` means that BMO has not hit any problem so far. Looking up the
`preProvisioningImage` confirms that the PPI feature is indeed off:

```bash
kubectl get preprovisioningimage host-0 -n my-cluster
```

```text
Error from server (NotFound): preprovisioningimages.metal3.io "host-0" not found
```

#### With the PPI feature and the default PPI's image provider

When the PPI feature is enabled, BMO creates a `preProvisioningImage` for the
host during registration. It shares the host's name and namespace:

```bash
kubectl get preprovisioningimage host-0 -n my-cluster
kubectl get preprovisioningimage host-0 -n my-cluster \
  -o jsonpath='{.status}' | jq .
```

```json
{
  "architecture": "x86_64",
  "format": "initrd",
  "imageUrl": "http://172.22.0.2/images/ironic-python-agent.initramfs",
  "kernelUrl": "http://172.22.0.2/images/ironic-python-agent.kernel",
  "networkData": {
    "name": "host-0-preprov-networkdata",
    "version": "12345"
  },
  "conditions": [
    { "type": "Ready", "status": "True" },
    { "type": "Error", "status": "False" }
  ]
}
```

There are two lines to check. The first one is the `Ready` condition. BMO does
not start inspection until this image reports `Ready`, so if the host is stuck
in `inspecting`, the `preProvisioningImage` status is the first place to look.
The second one is the `format`, which has to be `initrd`. Ironic builds the
node-specific ISO from this kernel+initrd pair and injects the network data into
it. If the `format` is `iso`, the default PPI's image provider hands out the
pre-built ISO from `DEPLOY_ISO_URL`, and the network data is not injected.

### Step 6: Troubleshoot if it gets stuck

If the host does not reach `available`, work through these in order. Most
DHCP-less problems fall into one of these categories:

- **No `preProvisioningImage` appears (PPI setup only).** The PPI feature is
  probably not enabled in BMO. Check that BMO runs with the
  `--build-preprov-image` flag.
- **`preProvisioningImage` exists but is not `Ready` (PPI setup only).** Read
  its `Error` condition and the logs of the PPI's image provider (for the
  default PPI's image provider, these are the BMO logs). The image build or the
  URL it points at is the problem, not the network data yet.
- **The host boots but never talks to Ironic.** In both setups, first make sure
  that IPA is supplied as a kernel+initrd pair (`DEPLOY_ISO_URL` is unset, and
  in the PPI setup the `format` is `initrd`), because a pre-built ISO gets no
  network data. After that, the cause is usually the `network_data.json`.
  Check that `ethernet_mac_address` matches the NIC cabled to the Ironic
  network, that the gateway is reachable, and that DNS resolves. A wrong MAC
  means the configuration applies to no interface.
- **BMC errors during registration.** Inspect the host events and status:

  ```bash
  kubectl describe bmh host-0 -n my-cluster
  kubectl get bmh host-0 -n my-cluster -o jsonpath='{.status.errorMessage}'
  ```

  Certificate and licensing errors from the BMC show up here. On a lab BMC with
  a self-signed certificate, make sure `disableCertificateVerification: true` is
  set.

Once the host is `available`, it has inspected and is ready to be provisioned
like any other Metal3 host, with no DHCP involved. Provisioning it with an
operating system image, and driving it through Cluster API, works the same as in
the standard flow.

## Summary

DHCP-less provisioning comes down to three features working together. Redfish
virtual media delivers the boot image out of band through the BMC, so DHCP or
an untagged provisioning VLAN is no longer needed to start the deploy ramdisk.

The second feature is the preprovisioning network data, delivered through
either the BMH's `preprovisioningNetworkDataName` spec field or via the
`preProvisioningImage` CR, depending on the use case. By default the
preprovisioning network data is applied by Glean from the ISO.

The third feature is the PPI itself. When deeper node-specific preprovisioning
image customizations are needed, the PPI/IPA is built by a custom PPI's image
provider based on the spec of the node-specific PPI CR. Such a provider can
convert the network data to a format that is not compatible with the OpenStack
network data format. It can also install additional software or build any kind
of PPI/IPA that the user needs.

In any case, the goal is to set the ramdisk's static network configuration so
that it can reach Ironic. The base ramdisk image can be shared across hosts,
while the network configuration and the boot mode are always set per host.

If custom PPI/IPA builds are not needed, setting a virtual media BMC
address and a `preprovisioningNetworkDataName` on the `BareMetalHost` is
enough, and Metal3 handles the rest.

This flow fits environments where DHCP is not available, such as regulated data
centers, L3-segmented fabrics, or setups that require static addressing. Users
who try it are encouraged to share their experience with the community, either
in the `#cluster-api-baremetal` channel on the [Kubernetes Slack][slack] or at
the weekly Metal3 community meetings.

For reference documentation, see
[advanced instance customization][advanced-instance-customization] and
[supported hardware][supported-hardware] in the Metal3 user guide.

[network_data]: https://docs.openstack.org/nova/latest/user/metadata.html#openstack-format-metadata
[glean]: https://opendev.org/opendev/glean/
[sushy]: https://opendev.org/openstack/sushy
[supported-hardware]: https://book.metal3.io/bmo/supported_hardware
[advanced-instance-customization]: https://book.metal3.io/bmo/advanced_instance_customization
[ppi-kernel-params]: https://github.com/metal3-io/baremetal-operator/pull/2576
[fast-inspection]: https://github.com/metal3-io/metal3-docs/blob/main/design/baremetal-operator/out-of-band-inspection.md
[managed-unmanaged]: https://docs.openstack.org/ironic/latest/admin/inspection/managed.html
[ppi-format-selection]: https://github.com/metal3-io/baremetal-operator/blob/b25fb168753c0a33352583da2c6b4592f53fd3e0/pkg/controllers/preprovisioningimage_controller.go#L227-L232
[deploy-image-selection]: https://github.com/metal3-io/baremetal-operator/blob/b25fb168753c0a33352583da2c6b4592f53fd3e0/pkg/provisioner/ironic/ironic.go#L581-L591
[slack]: https://kubernetes.slack.com
