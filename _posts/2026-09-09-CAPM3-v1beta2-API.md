---
title: "What's New in Cluster API Provider Metal3 (CAPM3) v1beta2"
date: 2026-09-09
draft: false
categories: ["metal3", "cluster-api", "capm3", "announcement"]
author: Muhammad Adil Ghaffar
---

Cluster API Provider Metal3 (CAPM3) has a new API version: `v1beta2`. It is
now the storage version, and it brings CAPM3 in line with the upstream
_Cluster API_ `v1beta2` contract. Most of the changes are about making status
easier to read for both humans and tools, tidying up a few spec fields, and
removing options that had been deprecated for a while.

This post walks through what changed, grouped by object, so you can see exactly
what is different for `Metal3Cluster`, `Metal3Machine`, and friends. The good
news up front: you do not have to rewrite everything by hand. CAPM3 still serves
`v1beta1`, and conversion webhooks translate between the two versions
automatically. `v1beta2` is simply where new work happens from now on.

## The big picture

Before diving into each object, it helps to understand the handful of themes
that show up almost everywhere in `v1beta2`. If you understand these themes,
the per-object details will feel very familiar.

- **Standard Kubernetes conditions.** Status conditions now use the standard
   `metav1.Condition` type instead of the older Cluster API condition type.
   Each condition carries the familiar `type`, `status`, `reason`, `message`,
   and `lastTransitionTime` fields, plus an optional `observedGeneration`, so
   they work with `kubectl` and anything else that understands Kubernetes
   conditions. Objects also report a standard `Paused` condition now.
- **`initialization.provisioned` replaces `ready`.** The old boolean
   `status.ready` field is gone. Instead, provisioning progress lives under
   `status.initialization.provisioned`. This matches the Cluster API contract
   and makes the "is my infrastructure up yet?" signal explicit.
- **A tidy `deprecated` bucket.** Legacy fields such as the old-style
   conditions, `failureReason`, and `failureMessage` are grouped under
   `status.deprecated.v1beta1`. These do not behave the way they used to: in
   Cluster API `v1beta1`, a populated `failureReason` / `failureMessage`
   signaled a _terminal_ error that needed manual intervention. `v1beta2`
   removes the concept of terminal errors entirely, so these fields are kept
   only for backward compatibility. Treat them as deprecated and rely on
   conditions instead.
- **References use `apiGroup`, not `apiVersion`.** Following the Cluster API
   `v1beta2` contract, object references such as `infrastructureRef` now use an
   `apiGroup` plus `kind` plus `name`, rather than a full `apiVersion`. This
   lets the API version float without rewriting every reference.
- **Cleaner spec types.** Several fields that used to be pointers are now plain
   values. This is driven by adopting the
   [kube-api-linter](https://github.com/kubernetes-sigs/kube-api-linter), which
   nudges the API toward Kubernetes conventions and removes a class of "is it
   nil or is it empty?" confusion when reading and templating manifests.
- **Maps became lists.** Where the old API keyed data by name, such as
   cluster failure domains and `Metal3DataTemplate` status indexes, `v1beta2`
   uses named lists. Lists work better with server-side apply and diff cleanly.

With those in mind, let's look at each object.

## Metal3Cluster

`Metal3Cluster` describes the cluster-level bits of a Metal3 deployment, mainly
the control plane endpoint and how the provider ID is handled.

- **`noCloudProvider` is gone.** In `v1beta1` this field was already deprecated
   in favor of `cloudProviderEnabled`. In `v1beta2` it has been removed
   entirely, so there is now a single, unambiguous switch. Set
   `cloudProviderEnabled: false` when you want CAPM3 to set `providerID` on the
   `Node` objects itself, and `true` when an external cloud provider does it.
- **Structured failure domains.** `status.failureDomains` moved from a map to a
   named list of failure-domain entries. Lists are friendlier to server-side
   apply and easier to reason about than map keys.
- **Modernized status.** `status.ready` became
   `status.initialization.provisioned`, conditions became `metav1.Condition`,
   and the old `failureReason` / `failureMessage` fields moved under
   `status.deprecated.v1beta1`. The printed columns changed accordingly: you
   will see a `Provisioned` column where `Ready` used to be.

Here is what a `Metal3Cluster` spec looks like in `v1beta2`:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: Metal3Cluster
metadata:
  name: m3cluster
  namespace: metal3
spec:
  controlPlaneEndpoint:
    host: 192.168.111.249
    port: 6443
  cloudProviderEnabled: false
```

And its status, showing the new `Paused` condition, the `reason`, `message`,
and `observedGeneration` on each condition, the `deprecated.v1beta1` copy of
the old-style conditions, and `initialization.provisioned` in place of the old
`ready: true`:

```yaml
status:
  conditions:
  - type: Ready
    status: "True"
    reason: Ready
    message: ""
    observedGeneration: 1
    lastTransitionTime: "2026-09-14T00:10:47Z"
  - type: BaremetalInfrastructureReady
    status: "True"
    reason: Ready
    message: ""
    observedGeneration: 1
    lastTransitionTime: "2026-09-14T00:10:47Z"
  - type: Paused
    status: "False"
    reason: NotPaused
    message: ""
    observedGeneration: 1
    lastTransitionTime: "2026-09-14T00:10:47Z"
  deprecated:
    v1beta1:
      conditions:
      - type: Ready
        status: "True"
        lastTransitionTime: "2026-09-14T00:10:47Z"
      - type: BaremetalInfrastructureReady
        status: "True"
        lastTransitionTime: "2026-09-14T00:10:47Z"
  initialization:
    provisioned: true
  lastUpdated: "2026-09-14T00:10:47Z"
```

## Metal3Machine

`Metal3Machine` is where most day-to-day configuration lives: the image to
deploy, host selection, cleaning behavior, and network data. It also saw the
most spec cleanups.

- **Provider ID format.** CAPM3 sets `spec.providerID` using the readable
   form `metal3://<namespace>/<bmh-name>/<m3m-name>`, so you can see at a glance
   which `BareMetalHost` and `Metal3Machine` a node maps to. The legacy
   UID-based form, `metal3://<bmh-uuid>`, is being phased out.
- **`image.format` is now `image.diskFormat`.** The image disk-format field was
   renamed for clarity. Change `format: raw` to `diskFormat: raw` when you write
   `v1beta2` manifests; the conversion webhook handles existing objects.
- **Pointers became values.** `providerID`, `automatedCleaningMode`, and
   `customDeploy` are now plain values instead of pointers, and `dataTemplate`
   uses a slim name/namespace reference rather than a full object reference.
   Manifests read the same, but the types are simpler and less error-prone.
- **The unused `phase` field was dropped.** `status.phase` was never really used
   in `v1beta1`, so it is not carried over. Rely on conditions and
   `initialization.provisioned` instead.
- **Node address overrides.** You can override the node's `InternalIP` and
   `ExternalIP` through the machine's metadata secret, which is handy for
   overlay networks, VIPs, or externally routable addresses where the addresses
   discovered on the host NICs are not what you want advertised.
- **Modernized status.** Readiness moved to `initialization.provisioned`, and
   the old-style conditions are preserved under `status.deprecated.v1beta1`.
   The condition set was cleaned up too: the terse `AssociateBMH` became
   `AssociateBareMetalHost`, a new `AssociateMetal3MachineMetaData` condition
   was added, and each condition now carries an explicit reason such as
   `AssociateBareMetalHostSuccess` or `Metal3DataSecretsReady`.

A `Metal3Machine` spec in `v1beta2`:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: Metal3Machine
metadata:
  name: controlplane-0
  namespace: metal3
spec:
  automatedCleaningMode: metadata
  image:
    url: http://172.22.0.1/images/UBUNTU_24.04_NODE_IMAGE.img
    checksum: http://172.22.0.1/images/UBUNTU_24.04_NODE_IMAGE.img.sha256sum
    checksumType: sha256
    diskFormat: raw
  hostSelector:
    matchLabels:
      key1: value1
  dataTemplate:
    name: controlplane-metadata
```

And the matching status once the machine is provisioned. The full conditions
live at the top, while the `deprecated.v1beta1.conditions` block keeps the
old-style view, same `type` and `status` but without `reason`, `message`, or
`observedGeneration`, so existing tooling keeps working while you migrate:

```yaml
status:
  conditions:
  - type: Ready
    status: "True"
    reason: Ready
    message: ""
    observedGeneration: 3
    lastTransitionTime: "2026-09-14T00:14:32Z"
  - type: AssociateBareMetalHost
    status: "True"
    reason: AssociateBareMetalHostSuccess
    message: ""
    observedGeneration: 1
    lastTransitionTime: "2026-09-14T00:10:55Z"
  - type: AssociateMetal3MachineMetaData
    status: "True"
    reason: AssociateMetal3MachineMetaDataSuccess
    message: ""
    observedGeneration: 3
    lastTransitionTime: "2026-09-14T00:14:32Z"
  - type: Metal3DataReady
    status: "True"
    reason: Metal3DataSecretsReady
    message: ""
    observedGeneration: 3
    lastTransitionTime: "2026-09-14T00:10:56Z"
  - type: Paused
    status: "False"
    reason: NotPaused
    message: ""
    observedGeneration: 3
    lastTransitionTime: "2026-09-14T00:10:52Z"
  deprecated:
    v1beta1:
      conditions:
      - type: Ready
        status: "True"
        lastTransitionTime: "2026-09-14T00:10:56Z"
      - type: AssociateBMH
        status: "True"
        lastTransitionTime: "2026-09-14T00:10:55Z"
      - type: Metal3DataReady
        status: "True"
        lastTransitionTime: "2026-09-14T00:10:56Z"
  initialization:
    provisioned: true
  lastUpdated: "2026-09-14T00:10:56Z"
```

## Metal3MachineTemplate

`Metal3MachineTemplate` is the template that machine deployments and control
planes stamp out `Metal3Machine` objects from.

- **Templated metadata.** The template resource now carries its own standard
   `metadata` block alongside the `spec`, so labels and annotations you set on
   the template can flow through to the machines it creates.
- **`image.diskFormat` applies here too.** Because the template embeds a
   `Metal3Machine` spec, the `image.format` → `image.diskFormat` rename carries
   over to `spec.template.spec.image`.
- **`nodeReuse` is unchanged.** The `nodeReuse` switch still works exactly as
   before, letting you re-provision the same pool of hosts during upgrades and
   remediation.

## Metal3ClusterTemplate

`Metal3ClusterTemplate` received the same template-level polish as
`Metal3MachineTemplate`: the template resource gained a standard `metadata`
block, and `v1beta2` is now the storage version. The embedded cluster `spec` is
identical to the standalone `Metal3Cluster` spec described above, so the
`cloudProviderEnabled` change applies here too.

## The data objects

The IPAM and metadata flow is handled by `Metal3DataTemplate`,
`Metal3DataClaim`, and `Metal3Data`. All three moved to `v1beta2`, and a few
field names in `Metal3DataTemplate` were tightened up along the way:

- **`*FromIPPool` metadata sources became `*FromPool`.** In `spec.metaData`,
   `ipAddressesFromIPPool` is now `ipAddressesFromPool`, `prefixesFromIPPool`
   is now `prefixesFromPool`, and the sibling gateway and DNS sources follow
   the same pattern. The rename reflects that a pool can be a Metal3 `IPPool`
   or any Cluster API IPAM provider.
- **Pool references are explicit.** Those pool entries now spell out their
   `apiGroup` and `kind` (for example `ipam.metal3.io` and `IPPool`) instead of
   leaving them blank, matching the `apiGroup` theme from earlier.
- **Routes use `prefix`.** In `spec.networkData`, network routes express the
   mask with a `prefix` field rather than the old `netmask`.
- **`Metal3DataTemplate` status indexes are a list.** `status.indexes` changed
   from a map keyed by claim name to a list of `{ index, name }` entries.
- **`Metal3Data` surfaces its `index`.** The allocated index is now visible on
   `Metal3Data.spec.index`.

`Metal3DataClaim` is unchanged apart from the version bump. As always,
conversion webhooks translate existing `v1beta1` objects, but if you author new
manifests directly in `v1beta2`, use the new field names. Here is the
`metaData` rename side by side.

Before, in `v1beta1`:

```yaml
metaData:
  ipAddressesFromIPPool:
  - key: provisioningIP
    name: provisioning-pool
  prefixesFromIPPool:
  - key: provisioningCIDR
    name: provisioning-pool
```

After, in `v1beta2`:

```yaml
metaData:
  ipAddressesFromPool:
  - key: provisioningIP
    name: provisioning-pool
    apiGroup: ipam.metal3.io
    kind: IPPool
  prefixesFromPool:
  - key: provisioningCIDR
    name: provisioning-pool
    apiGroup: ipam.metal3.io
    kind: IPPool
```

## Remediation

The `Metal3Remediation` object also moved to `v1beta2` and picked up the same
status conventions, namely `metav1.Condition` conditions and the `deprecated`
grouping for legacy fields. Its remediation strategy configuration is otherwise
unchanged.

## One more thing: the unhealthy annotation

If you mark hosts as unhealthy so CAPM3 skips them when selecting a
`BareMetalHost`, note that the annotation key changed. From `v1beta2` onwards it
is `capm3.metal3.io/unhealthy` (previously `capi.metal3.io/unhealthy`). Adding
the annotation still keeps a host out of the selection pool, and removing it
returns the host to normal operation.

## What this means for upgrades

You do not need to migrate manifests by hand. CAPM3 continues to serve
`v1beta1`, and conversion webhooks translate objects between `v1beta1` and
`v1beta2` in both directions. Because `v1beta2` is the storage version, objects
are persisted in the new format, and deprecated status fields are populated
during conversion where they still apply, so older tooling keeps working during
the transition.

There is a timeline to keep in mind, though. `v1beta1` is deprecated now, will
stop being served in CAPM3 `v1.16` (around April 2027), and will be removed
entirely in CAPM3 `v1.19` (around April 2028). Once it is unserved, the API
server will no longer accept or return `v1beta1`, so plan to have your manifests,
scripts, and integrations on `v1beta2` well before then.

A practical approach:

- Start reading status from the new fields: `status.initialization.provisioned`
   and the `metav1.Condition` entries in `status.conditions`.
- Update any dashboards or scripts that keyed off `status.ready`,
   `status.phase`, or the old `failureReason` / `failureMessage` locations.
   Because `failureReason` / `failureMessage` are no longer set for terminal
   errors in `v1beta2`, watch conditions instead.
- Move `Metal3Cluster` manifests off `noCloudProvider` and onto
   `cloudProviderEnabled` if you have not already.
- If you author manifests directly in `v1beta2`, rename `image.format` to
   `image.diskFormat`, and switch `Metal3DataTemplate` `*FromIPPool` metadata
   sources to `*FromPool`.

## Wrapping up

`v1beta2` is mostly about consistency: standard Kubernetes conditions, an
explicit provisioning signal, tidier references, and the removal of options that
had lived on borrowed time. Nothing here should force a disruptive change, but
it does give you a cleaner, more predictable API to build on.

Start using `v1beta2` in your clusters, watch the new conditions with
`kubectl describe`, and let us know how it goes. If you spot rough edges or have
ideas, the Metal3 community would love your input: issues, pull requests, and
questions are all welcome on the
[Cluster API Provider Metal3 repository](https://github.com/metal3-io/cluster-api-provider-metal3).
