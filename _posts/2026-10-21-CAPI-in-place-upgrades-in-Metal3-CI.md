---
title: "Testing Cluster API In-Place Updates in the Metal3 CI"
date: 2026-10-21
draft: false
categories: ["metal3", "cluster-api", "capm3", "testing"]
author: Muhammad Adil Ghaffar
---

Cluster API has always upgraded clusters by replacing machines. To upgrade a
Metal3 cluster, you create a new infrastructure machine template, a
`Metal3MachineTemplate`, with the new configuration, for example a new node
image. Then you point the `KubeadmControlPlane` or the `MachineDeployment` to
it and set the new Kubernetes version. With _ClusterClass_, the topology
controller generates and assigns the new templates for you, but the process
underneath is the same: Cluster API deprovisions the old machines and
provisions new ones.

The order of these two steps depends on the rollout strategy:

- **Surge first** (`maxSurge: 1`): Cluster API creates a new machine, waits
  until it is ready, and then deletes an old one. You need a spare host for
  this.
- **Delete first** (`maxSurge: 0` on `KubeadmControlPlane`, or
  `maxUnavailable > 0` on `MachineDeployment`): Cluster API deletes an old
  machine first, and its host can then be reused for the new machine.
- **`OnDelete`** (`MachineDeployment` only): Cluster API creates a new machine
  only after you delete an old one yourself.

This immutable approach is simple and safe, but on bare metal it can be
expensive. Every replacement means a full provisioning cycle: cleaning, writing
an image to disk, and rebooting, often on servers that take many minutes just
to get through firmware.

Cluster API now offers another tool: _in-place updates_. In this post we give a
short introduction to the feature, and then show how the Metal3 project tests it
in CI with a small _Runtime Extension_ that upgrades Kubernetes by SSHing into
the nodes. In CI, the nodes are virtual machines that Metal3 manages as
`BareMetalHost` objects, not physical servers.

## What are in-place updates?

In-place updates let Cluster API apply changes to an existing machine instead of
deleting it and creating a new one. The feature is built on the
[Runtime SDK](https://cluster-api.sigs.k8s.io/tasks/experimental-features/runtime-sdk/),
so Cluster API itself does not know _how_ to update a machine. It asks an
external component, an update extension, whether it can handle a change and
then asks it to perform the change.

The important part is that the user experience does not change. You still
declare the desired state, for example by bumping `spec.version` on a
`KubeadmControlPlane` or by rotating a machine template. Cluster API then picks
the best strategy to reach that state:

- **In-place** if a registered extension says it can cover _all_ the changes.
- **Rollout** (the classic replace-the-machine flow) if it cannot.

Cluster API still owns the rollout logic: which machines to update, and how to
respect `maxSurge` and `maxUnavailable`. Some rules worth knowing:

- A machine updating in-place counts as not available, because an in-place
  update is always potentially disruptive.
- For control plane machines with `maxSurge: 1`, a new machine is created first.
  In-place updates start once there is enough buffer. `KubeadmControlPlane`
  skips in-place updates if they could hurt control plane health.
- For workers with `maxUnavailable: 0`, a new machine is also created first.
- Workers using the `OnDelete` rollout strategy are never updated in-place.

The feature is experimental. Cluster API calls the hooks only when the
`InPlaceUpdates` feature gate is enabled, and today only one extension can be
registered for the in-place hooks.

### The three hooks

An update extension implements three hooks:

- **`CanUpdateMachine`**: called by `KubeadmControlPlane` for a control plane
  machine. The request contains the _current_ and _desired_ `Machine`,
  infrastructure machine, and bootstrap config. The extension answers with
  JSON patches that describe which changes it can handle in-place.
- **`CanUpdateMachineSet`**: the same question, but asked by the
  `MachineDeployment` controller for all the machines of a `MachineSet`. Here
  the request contains the `MachineSet`, infrastructure machine template, and
  bootstrap config template.
- **`UpdateMachine`**: called by the `Machine` controller to actually perform
  the update. The request contains only the desired state, so the extension
  must know the current state of the machine itself.

The "can update" hooks work by patching. Cluster API applies the returned
patches to the _current_ objects. If the result matches the desired objects,
the extension covers everything and the update goes in-place. If anything is
left over, Cluster API falls back to a rollout.

`UpdateMachine` is long-running by design and uses the common retry response:

```yaml
apiVersion: hooks.runtime.cluster.x-k8s.io/v1alpha1
kind: UpdateMachineResponse
status: Success # or Failure
message: "error message if status == Failure"
retryAfterSeconds: 10
```

- `Success` with `retryAfterSeconds > 0` means the update is still in progress.
- `Success` with `retryAfterSeconds: 0` means the update is done.
- `Failure` means the update failed.

For the full API details, see the
[Cluster API book](https://cluster-api.sigs.k8s.io/tasks/experimental-features/runtime-sdk/implement-in-place-update-hooks.html).

## Why this matters for Metal3

For a Kubernetes patch or minor version upgrade on bare metal, a rollout means
deprovisioning a host, cleaning it, and provisioning it again with a new image.
An in-place update can instead upgrade `kubeadm`, `kubelet`, and `kubectl` on
the running node and restart `kubelet`. The `Machine`, the `Metal3Machine`, and
the `BareMetalHost` all stay the same.

Cluster API ships the hooks, but someone must implement the actual update logic.
Cluster API Provider Metal3 (CAPM3) does not ship a production update extension.
To make sure CAPM3 works correctly with the in-place flow, we built a _test
extension_ and an end-to-end test that run in the Metal3 CI.

## The CAPM3 test extension

The test extension lives in
[`test/extension`](https://github.com/metal3-io/cluster-api-provider-metal3/tree/main/test/extension)
in the CAPM3 repository. It is adapted from the upstream Cluster API test
extension and is a normal controller-runtime manager that serves the three
hooks through the Runtime SDK webhook server:

```go
runtimeExtensionWebhookServer.AddExtensionHandler(server.ExtensionHandler{
    Hook:        runtimehooksv1.CanUpdateMachine,
    Name:        "can-update-machine",
    HandlerFunc: inPlaceUpdateExtensionHandlers.DoCanUpdateMachine,
})
// ... the same for CanUpdateMachineSet and UpdateMachine
```

It runs in the `test-extension-system` namespace of the management cluster.
Cluster API discovers it through an `ExtensionConfig`, which limits it to
clusters in the `metal3` namespace:

```yaml
apiVersion: runtime.cluster.x-k8s.io/v1beta2
kind: ExtensionConfig
metadata:
  annotations:
    runtime.cluster.x-k8s.io/inject-ca-from-secret: test-extension-system/test-extension-webhook-service-cert
  name: test-extension
spec:
  clientConfig:
    service:
      name: test-extension-webhook-service
      namespace: test-extension-system
      port: 443
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: In
      values:
      - metal3
```

### Declaring what can be updated in-place

The `CanUpdateMachine` and `CanUpdateMachineSet` handlers follow the same
pattern. They take a copy of the current objects, copy over the fields the
extension knows how to change, and then compute a JSON patch between the
original and the modified copy. The extension handles these fields:

- **`Machine.spec.version`**: the Kubernetes version itself.
- **`Metal3Machine.spec.image`** and **`spec.dataTemplate`**: the upgrade test
  also points the control plane at a new `Metal3MachineTemplate` with a newer
  node image. Accepting these fields keeps the template change from forcing a
  rollout. The running host keeps its current image; only the spec changes.
  The next section explains why the new image is still needed.
- **`KubeadmConfig` `ClusterConfiguration.featureGates`**: during a version
  upgrade, `KubeadmControlPlane` manages some version-dependent kubeadm feature
  gates by itself. Because the extension really runs `kubeadm upgrade` on the
  node, it can absorb that diff too.

The last item came from a real CI failure. Without it, `KubeadmControlPlane`
saw a leftover diff in the bootstrap config, fell back to a rollout, and the
test failed because the machines got new UIDs. It is a good example of the
"all or nothing" rule: the extension must cover _every_ change, or Cluster API
replaces the machine.

For example, the version check is as simple as it gets:

```go
func canUpdateMachineSpec(current, desired *clusterv1.MachineSpec) {
    if current.Version != desired.Version {
        current.Version = desired.Version
    }
}
```

### Why a new node image is still needed

An in-place upgrade changes the Kubernetes binaries on the running node, but it
does not touch the image that Metal3 writes to disk for _new_ machines. That
image comes from `Metal3MachineTemplate.spec.template.spec.image`.

If you bump only the Kubernetes version and keep the old template, the existing
nodes run the new version, but the template still points to the old image.
The next time the control plane or a `MachineDeployment` scales up, or a machine
is remediated, Cluster API creates a new machine from that template. The new
host boots the old image, with the old `kubeadm` and `kubelet` binaries, and
then tries to join a cluster that runs a newer Kubernetes version. Depending on
the version skew, the join fails, or the cluster ends up with mixed node
versions.

For this reason, an in-place upgrade on Metal3 has two parts:

- **Upgrade the running nodes** in-place through the update extension.
- **Point the template to a node image for the new version**, so that machines
  created later start on the correct version.

The extension accepts the `image` change in `CanUpdateMachine` and
`CanUpdateMachineSet` for exactly this reason. Without it, the template change
would force a rollout. With it, the existing hosts are not reprovisioned, and
new machines get the new image.

### Upgrading the node over SSH

`DoUpdateMachine` is where the real work happens. The extension must first find
out _where_ the machine is. On Metal3 the IP address comes from the IP Address
Manager, so the extension follows the ownership chain:

```text
Machine -> Metal3Machine -> Metal3Data -> IPClaim -> IPAddress
```

It picks the `IPClaim` from the `baremetalv4-pool` pool and reads the address
from the matching `IPAddress`. The SSH user defaults to `metal3`, or the first
user from the desired `KubeadmConfig` if one is set.

With the IP and user known, the extension connects with
`golang.org/x/crypto/ssh` and runs a standard kubeadm upgrade with `sudo`:

1. Write a `yum` repository file that points to `pkgs.k8s.io` for the target
   minor version.
1. Run `yum clean all` and `yum makecache`.
1. Install the target `kubeadm` version.
1. Run `kubeadm upgrade node`.
1. Install the target `kubelet` and `kubectl` versions.
1. Run `systemctl daemon-reload` and `systemctl restart kubelet`.

Before it builds any command, the extension checks the target version against
`^\d+\.\d+\.\d+$`. The version ends up in shell commands, so this check blocks
shell injection through the version string.

An upgrade takes much longer than a webhook call is allowed to take, so the
handler is asynchronous and keeps a small in-memory state map:

- **First call**: store the machine as "started", run the upgrade in a
  goroutine, and return `Success` with `retryAfterSeconds: 15`.
- **Next calls**: SSH to the node and run `kubelet --version`. If it reports the
  target version, clear the state and return `Success` with
  `retryAfterSeconds: 0`. If not, ask Cluster API to retry in 15 seconds.
- **Background failure**: the goroutine sets an error flag, and the next call
  returns `Failure`.

The private SSH key comes from a `ssh-key` secret in the `test-extension-system`
namespace. The deployment mounts it read-only at `/home/nonroot/.ssh/id_rsa`
and runs as a non-root user:

```yaml
volumes:
- name: ssh-key
  secret:
    secretName: ssh-key
    defaultMode: 0400
    items:
    - key: id_rsa
      path: id_rsa
      mode: 0400
```

This approach is fine for a CI environment, but it is not a production design.
The extension skips SSH host key checks, keeps its state in memory, and assumes
a CentOS-like node image with `yum`. A real update extension would need proper
host key checks, durable state, and support for the node operating systems you
actually run.

## Running it in the Metal3 CI

The Metal3 CI does not use physical servers. It creates virtual machines on the
CI host and registers them as `BareMetalHost` objects, so Metal3 provisions
them through Ironic in the same way as real hardware. The in-place upgrade test
uses five of these virtual machines.

To make in-place updates work, the management cluster needs the feature gates,
the extension, an SSH key, and an `ExtensionConfig`.

### Feature gates

`clusterctl init` reads these variables and sets the matching feature gates on
the Cluster API controllers:

```bash
export EXP_RUNTIME_SDK=true      # Runtime SDK, needed for any Runtime Extension
export EXP_IN_PLACE_UPDATES=true # InPlaceUpdates, makes Cluster API call the hooks
export CLUSTER_TOPOLOGY=true     # ClusterClass, also enabled in the CI job
```

### Installing the extension with clusterctl

The CI builds the extension image from the source tree and loads it into the
_kind_ management cluster. The extension is declared as a
`RuntimeExtensionProvider` in the e2e configuration:

```yaml
- name: test-extension
  type: RuntimeExtensionProvider
  versions:
  - name: v1.15.99
    value: "${PWD}/test/extension/config/default"
    contract: v1beta2
```

`clusterctl init` then installs it together with the other providers. The
equivalent command looks like this:

```bash
clusterctl init \
  --core cluster-api \
  --bootstrap kubeadm \
  --control-plane kubeadm \
  --infrastructure metal3 \
  --ipam metal3 \
  --runtime-extension test-extension
```

### SSH key and ExtensionConfig

The extension pod mounts the `ssh-key` secret, and `clusterctl init` waits for
all provider deployments to become available. So the secret must exist _before_
the init. The e2e suite creates the `test-extension-system` namespace and the
secret from `~/.ssh/id_rsa`, the private half of the key that is provisioned on
the nodes. By hand, this is:

```bash
kubectl create namespace test-extension-system
kubectl -n test-extension-system create secret generic ssh-key \
  --from-file=id_rsa="${HOME}/.ssh/id_rsa"
```

Finally, the test applies the `ExtensionConfig` shown earlier, so that Cluster
API discovers the hooks.

### What the test checks

The test creates a workload cluster with three control plane machines on an
older Kubernetes version. Then it points the `KubeadmControlPlane` to a new
`Metal3MachineTemplate` with a matching node image, bumps `spec.version`, and
sets `maxSurge` to `0`. The test then checks that:

- **No machine is replaced.** Every control plane `Machine` keeps the UID it
  had before the upgrade. If the extension misses even one changed field,
  Cluster API falls back to a rollout, the UIDs change, and the test fails.
- **All machines run the new version.** All three control plane machines reach
  `Running` on the target Kubernetes version.
- **New machines use the new image.** The test scales the control plane to five
  replicas. The two new machines must boot the new node image and join on the
  new version.

## Wrapping up

In-place updates give Cluster API a second way to reach the desired state, and
on bare metal that can save a lot of reprovisioning time. Cluster API keeps the
same declarative workflow, and decides per change whether an extension can
handle it or whether a rollout is needed.

The CAPM3 test extension is intentionally small. It handles the Kubernetes
version, the image and data template fields, and the kubeadm feature gates. It
upgrades nodes over SSH and proves in CI that the machines survive the upgrade.
If you plan to write your own update extension for Metal3, it is a practical
starting point. Look at how it finds the node IP, how it handles long-running
updates, and which fields it must declare to avoid a fallback rollout.

The feature is still experimental, and we would like to hear about your use
cases. Try it out, and share your findings in the
[Cluster API Provider Metal3 repository](https://github.com/metal3-io/cluster-api-provider-metal3)
or in the Metal3 community channels.
