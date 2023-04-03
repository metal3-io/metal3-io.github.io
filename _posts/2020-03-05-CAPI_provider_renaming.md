---
title: "Cluster API provider renaming"
date: 2020-03-05
draft: false
categories: ["metal3", "baremetal", "cluster API", "provider"]
author: Maël Kimmerlin
---

## Renaming of Cluster API provider

> info "Backwards compatibility for v1alpha3"
> There is no backwards compatibility between v1alpha3 and v1alpha2 releases of
> the Cluster API provider for Metal3.

For the v1alpha3 release of Cluster API, the Metal3 provider was renamed from
`cluster-api-provider-baremetal` to `cluster-api-provider-metal3`. The Custom
Resource Definitions were also modified. This post dives into the changes.

### Repository renaming

From v1alpha3 onwards, the Cluster API provider will be developed in
[cluster-api-provider-metal3](https://github.com/metal3-io/cluster-api-provider-metal3).
The v1alpha1 and v1alpha2 content will remain in
[cluster-api-provider-baremetal](https://github.com/metal3-io/cluster-api-provider-baremetal).
This repository will be archived but kept for the integration in metal3-dev-env.

### Custom Resource Definition modifications

The kind of Custom Resource Definition (CRD) has been modified for the
following objects:

- `BareMetalCluster` -> `Metal3Cluster`
- `baremetalcluster` -> `metal3cluster`
- `BareMetalMachine` -> `Metal3Machine`
- `baremetalmachine` -> `metal3machine`
- `BareMetalMachineTemplate` -> `Metal3MachineTemplate`
- `baremetalmachinetemplate` -> `metal3machinetemplate`

The custom resources deployed need to be modified accordingly.

### Deployment modifications

The prefix of all deployed components for the Metal3 provider was modified
from `capbm-` to `capm3-`. The namespace in which the components are deployed by
default was modified from `capbm-system` to `capm3-system`.
