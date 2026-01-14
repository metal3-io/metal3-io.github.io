---
title: "Baremetal Operator"
date: 2019-09-11T13:00:00+02:00
draft: false
categories: ["openshift", "kubernetes", "metal3", "operator"]
author: Pablo Iranzo Gómez
---

## Introduction

The [baremetal operator](https://github.com/metal3-io/baremetal-operator/), documented [here](https://github.com/metal3-io/baremetal-operator/blob/main/docs/api.md), it's the Operator in charge of definitions of physical hosts, containing information about how to reach the Out of Band management controller, URL with the desired image to provision, plus other properties related with hosts being used for provisioning instances.

Quoting from the project:

> The Bare Metal Operator implements a Kubernetes API for managing bare metal hosts. It maintains an inventory of available hosts as instances of the BareMetalHost Custom Resource Definition. The Bare Metal Operator knows how to:
> Inspect the host’s hardware details and report them on the corresponding BareMetalHost. This includes information about CPUs, RAM, disks, NICs, and more.
> Provision hosts with a desired image
> Clean a host’s disk contents before or after provisioning.

## A bit more in deep approach

The Baremetal Operator (BMO) keeps a mapping of each host and its management interfaces (vendor-based like `iLO`, `iDrac`, `iRMC`, etc) and is controlled via `IPMI`.

All of this is defined in a `CRD`, for example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: metal3-node01-credentials
  namespace: metal3
type: Opaque
data:
  username: YWRtaW4=
  password: YWRtaW4=
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: metal3-node01
  namespace: metal3
spec:
  bmc:
    address: ipmi://172.22.0.2:6230
    credentialsName: metal3-node01-credentials
  bootMACAddress: 00:c2:fc:3b:e1:01
  description: ""
  hardwareProfile: "libvirt"
  online: false
```

With above values (described in [API](https://github.com/metal3-io/baremetal-operator/blob/main/docs/api.md)), we're telling the operator:

- MAC: Defines the mac address of the NIC connected to the network that will be used for the provisioning of the host
- bmc: defines the management controller address and the secret used
- credentialsName: Defines the name of the secret containing username/password for accessing the IPMI service

Once the server is 'defined' via the CRD, the underlying service (provided by `ironic`[^1] as of this writing) is inspected:

[^1]: Ironic was chosen as the initial provider for baremetal provisioning, check [Ironic documentation](https://github.com/metal3-io/metal3-docs/blob/main/design/use-ironic.md) for more details about Ironic usage in Metal³

```console
[root@metal3-kubernetes ~]# kubectl get baremetalhost -n metal3
NAME            STATUS   PROVISIONING STATUS   CONSUMER   BMC                      HARDWARE PROFILE   ONLINE   ERROR
metal3-node01   OK       inspecting                       ipmi://172.22.0.1:6230                      false
```

Once the inspection has finished, the status will change to _ready_ and made available for provisioning.

When we define a machine, we refer to the images that will be used for the actual provisioning in the CRD (`image`):

```yaml
apiVersion: v1
data:
  userData: DATA
kind: Secret
metadata:
  name: metal3-node01-user-data
  namespace: metal3
type: Opaque
---
apiVersion: "cluster.k8s.io/v1alpha1"
kind: Machine
metadata:
  name: metal3-node01
  namespace: metal3
  generateName: baremetal-machine-
spec:
  providerSpec:
    value:
      apiVersion: "baremetal.cluster.k8s.io/v1alpha1"
      kind: "BareMetalMachineProviderSpec"
      image:
        url: http://172.22.0.2/images/CentOS-7-x86_64-GenericCloud-1901.qcow2
        checksum: http://172.22.0.2/images/CentOS-7-x86_64-GenericCloud-1901.qcow2.md5sum
      userData:
        name: metal3-node01-user-data
        namespace: metal3
```

```console
[root@metal3-kubernetes ~]# kubectl create -f metal3-node01-machine.yml
secret/metal3-node01-user-data created
machine.cluster.k8s.io/metal3-node01 created
```

Let's examine the annotation created when provisioning (`metal3.io/BareMetalHost`):

```console
[root@metal3-kubernetes ~]# kubectl get machine -n metal3 metal3-node01 -o yaml
apiVersion: cluster.k8s.io/v1alpha1
kind: Machine
metadata:
  annotations:
    metal3.io/BareMetalHost: metal3/metal3-node01
  creationTimestamp: "2019-07-08T15:30:44Z"
  finalizers:
  - machine.cluster.k8s.io
  generateName: baremetal-machine-
  generation: 2
  name: metal3-node01
  namespace: metal3
  resourceVersion: "6222"
  selfLink: /apis/cluster.k8s.io/v1alpha1/namespaces/metal3/machines/metal3-node01
  uid: 1bfd384a-5467-43b7-98aa-e80e1ace5ce7
spec:
  metadata:
    creationTimestamp: null
  providerSpec:
    value:
      apiVersion: baremetal.cluster.k8s.io/v1alpha1
      image:
        checksum: http://172.22.0.1/images/CentOS-7-x86_64-GenericCloud-1901.qcow2.md5sum
        url: http://172.22.0.1/images/CentOS-7-x86_64-GenericCloud-1901.qcow2
      kind: BareMetalMachineProviderSpec
      userData:
        name: metal3-node01-user-data
        namespace: metal3
  versions:
    kubelet: ""
status:
  addresses:
  - address: 192.168.122.79
    type: InternalIP
  - address: 172.22.0.39
    type: InternalIP
  - address: localhost.localdomain
    type: Hostname
  lastUpdated: "2019-07-08T15:30:44Z"
```

> info ""
> In the output above, the host assigned was the one we've defined earlier as well as the other parameters like IP's, etc generated.

Now, if we check baremetal hosts, we can see how it's getting provisioned:

```console
[root@metal3-kubernetes ~]# kubectl get baremetalhost -n metal3
NAME            STATUS   PROVISIONING STATUS   CONSUMER   BMC                      HARDWARE PROFILE   ONLINE   ERROR
metal3-node01   OK       provisioned                       ipmi://172.22.0.1:6230                     true
```

And also, check it via the `ironic` command:

```console
[root@metal3-kubernetes ~]# export OS_TOKEN=fake-token ; export OS_URL=http://localhost:6385 ; openstack baremetal node list
+--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
| UUID                                 | Name          | Instance UUID                        | Power State | Provisioning State | Maintenance |
+--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
| 7551cfb4-d758-4ad8-9188-859ee53cf298 | metal3-node01 | 7551cfb4-d758-4ad8-9188-859ee53cf298 | power on    | active             | False       |
+--------------------------------------+---------------+--------------------------------------+-------------+--------------------+-------------+
```

## Wrap-up

We've seen how via a CRD we've defined credentials for a baremetal host to make it available to get provisioned and how we've also defined a machine that was provisioned on top of that baremetal host.
