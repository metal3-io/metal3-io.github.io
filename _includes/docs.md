## APIs

1. Enroll nodes by creating `BareMetalHost` resources. This would either be
   manually or done by a component doing node discovery and introspection.

   See the documentation in the
   [baremetal-operator](https://github.com/metal3-io/baremetal-operator/blob/master/docs/api.md) repository for details.

2. Use the machine API to allocate a machine.

   See the documentation in the
   [cluster-api-provider-baremetal](https://github.com/metal3-io/cluster-api-provider-baremetal/blob/master/docs/api.md)
   repository for details.

3. The new Machine is associated with an available `BareMetalHost`, which triggers
   provisioning of that host to join the cluster. This association is done by
   the Actuator when it sets the `MachineRef` field on the `BareMetalHost`.

## Design Documents

The design documents for Metal3 are all publicly available. Refer to the [metal3-io/metal3-docs github repository](https://github.com/metal3-io/metal3-docs) for details.

## Around the Web

### Conference Talks

- [Metal³: Deploy Kubernetes on Bare Metal - Yolanda Robla - Shift Dev 2019]({% post_url 2020-01-20-metal3_deploy_kubernetes_on_bare_metal %})
- [Introducing metal3 kubernetes native bare metal host management - Kubecon NA 2019]({% post_url 2019-12-04-Introducing_metal3_kubernetes_native_bare_metal_host_management %})
- [Extend Your Data Center to the Hybrid Edge - Red Hat Summit, May 2019]({% post_url 2019-11-13-Extend_Your_Data_Center_to_the_Hybrid_Edge-Red_Hat_Summit %})
- [OpenStack Ironic and Bare Metal Infrastructure: All Abstractions Start Somewhere - Chris Hoge, OpenStack Foundation; Julia Kreger, Red Hat]({% post_url 2019-10-31-OpenStack-Ironic-and-Bare-Metal-Infrastructure_All-Abstractions-Start-Somewhere %})
- [Kubernetes-native Infrastructure: Managed Baremetal with Kubernetes Operators and OpenStack Ironic - Steve Hardy, Red Hat]({% post_url 2019-11-07-Kubernetes-native_Infrastructure-Managed_Baremetal_with_Kubernetes_Operators_and_OpenStack_Ironic %})

### In The News

- [The New Stack: Metal3 Uses OpenStack’s Ironic for Declarative Bare Metal Kubernetes]({% post_url 2019-05-13-The_new_stack_Metal3_Uses_OpenStack_Ironic_for_Declarative_Bare_Metal_Kubernetes %})
- [The Register: Raise some horns: Red Hat's MetalKube aims to make Kubernetes on bare machines simple]({% post_url 2019-04-12-Raise_some_horns_Red_Hat_s_MetalKube_aims_to_make_Kubernetes_on_bare_machines_simple %})

### Blog Posts

- [Metal³ Blog posts](/blog/)
