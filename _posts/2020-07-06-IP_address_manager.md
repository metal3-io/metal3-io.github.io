---
title: "Introducing the Metal3 IP Address Manager"
date: 2020-07-06
draft: false
categories: ["metal3", "baremetal", "IPAM", "ip address manager"]
author: Maël Kimmerlin
---

As a part of developing the Cluster API Provider Metal3 (CAPM3) v1alpha4
release, the Metal3 crew introduced a new project : its own IP Address Manager.
This blog post will go through the motivations behind such a project, the
features that it brings, its use in Metal3 and the future work.

## What is the IP Address Manager ?

The IP Address Manager (IPAM) is a controller that provides IP addresses and
manages the allocations of IP subnets. It is not a DHCP server in that it only
reconciles Kubernetes objects and does not answer to any DHCP queries. It
allocates IP addresses on request, but does not handle any use of those
addresses.

This sounds like the description of any IPAM system, no ? Well the twist
is that this manager is based on Kubernetes to specifically handle some
constraints from Metal3. We will go through the different issues that this
project tackles.

When deploying nodes in bare metal environment, there are a lot of possible
variations. This project specifically aims to solve the cases where static
IP address configurations are needed. It is designed to specifically address
this in the [Cluster API (CAPI) context](https://cluster-api.sigs.k8s.io/).

CAPI addresses the deployment of Kubernetes clusters and nodes, using
the Kubernetes API. As such, it uses objects such as Machine Deployments
(similar to deployments for pods) that takes care of creating the requested
number of machines, based on templates. The replicas can be increased by the
user, triggering the creation of new machines based on the provided templates.
This mechanism does not allow for flexibility to be able to provide static
addresses for each machine. The manager adds this flexibility by providing
the address right before provisioning the node.

In addition, all the resources from the source cluster must support the CAPI
pivoting, i.e. being copied and recreated in the target cluster. This means
that all objects must contain all needed information in their spec field to
recreate the status in the target cluster without losing information. All
objects must, through a tree of owner references, be attached to the cluster
object, for the pivoting to proceed properly.

In a nutshell, the manager provides an IP Address allocation service, based
on Kubernetes API and fulfilling the needs of Metal3, specifically the
requirements of CAPI.

## How does it work ?

The manager follows the same logic as the volume allocation in Kubernetes,
with a claim and an object created for that claim. There are three type of
objects defined, the `IPPool`, the `IPClaim` and the `IPAddress` objects.

The `IPPool` objects contain the definition of the IP subnets from which the
Addresses are allocated. It supports both IPv4 and IPv6. The subnets can either
be defined as such or given as a start and end IP addresses with a prefix.
It also supports pre-allocating IP addresses.

The following is an example `IPPool` definition :

```yaml
apiVersion: ipam.metal3.io/v1alpha1
kind: IPPool
metadata:
  name: pool1
spec:
  clusterName: cluster1
  pools:
    - start: 192.168.0.10
      end: 192.168.0.30
      prefix: 25
      gateway: 192.168.0.1
    - subnet: 192.168.1.1/26
    - subnet: 192.168.1.128/25
  prefix: 24
  gateway: 192.168.1.1
  preAllocations:
    claim2: 192.168.0.12
```

An IPv6 `IPPool` would be defined similarly :

```yaml
apiVersion: ipam.metal3.io/v1alpha1
kind: IPPool
metadata:
  name: pool1
spec:
  clusterName: cluster1
  pools:
    - start: 2001:0db8:85a3:0000:0000:8a2e::10
      end: 2001:0db8:85a3:0000:0000:8a2e:ffff:fff0
      prefix: 96
      gateway: 12001:0db8:85a3:0000:0000:8a2e::1
    - subnet: 2001:0db8:85a3:0000:0000:8a2d::/96
  prefix: 96
  gateway: 2001:0db8:85a3:0000:0000:8a2d::1
```


Whenever something requires an IP address from the `IPPool`, it will create an
`IPClaim`. The `IPClaim` contains a pointer to the `IPPool` and an owner reference
to the object that created it.

The following is an example of an `IPClaim`:

```yaml
apiVersion: ipam.metal3.io/v1alpha1
kind: IPClaim
metadata:
  name: claim1
spec:
  pool:
    Name: pool1
status:
  address:
    Name: pool1-192-168-0-13
```

The controller will then reconcile this object and allocate an IP address. It
will create an `IPAddress` object representing the allocated address. It will
then update the `IPPool` status to list the IP Address and the `IPClaim` status
to point to the `IPAddress`.

The following is an example of an `IPAddress`:

```yaml
apiVersion: ipam.metal3.io/v1alpha1
kind: IPAddress
metadata:
  name: pool1-192-168-0-13
spec:
  pool:
    Name: pool1
  claim:
    Name: claim1
  address: 192.168.0.13
  prefix: 24
  gateway: 192.168.0.1
```

After this allocation, the `IPPool` will be looking like :

```yaml
apiVersion: ipam.metal3.io/v1alpha1
kind: IPPool
metadata:
  name: pool1
spec:
  clusterName: cluster1
  pools:
    - start: 192.168.0.10
      end: 192.168.0.30
      prefix: 25
      gateway: 192.168.0.1
    - subnet: 192.168.1.1/26
    - subnet: 192.168.1.128/25
  prefix: 24
  gateway: 192.168.1.1
  preAllocations:
    claim2: 192.168.0.12
status:
  indexes:
    claim1: 192.168.0.13
    claim2: 192.168.0.12
```

## Use in Metal3

The IP Address Manager is used in Metal3 together with the metadata and network
data templates feature. Each Metal3Machine (M3M) and Metal3MachineTemplate
(M3MT) is associated with a Metal3DataTemplate that contains a metadata and /
or a network data template that will be rendered for each Metal3Machine. The
rendered data will then be provided to Ironic. Those templates reference
`IPPool` objects. For each Metal3Machine, an `IPClaim` is created for each
`IPPool`, and the templates are rendered with the allocated `IPAddress`.

This is how we achieve dynamic IP Address allocations in setups that
require static configuration, allowing us to use Machine Deployment and Kubeadm
Control Plane objects from CAPI in hardware labs where DHCP is not supported.

Since each `IPAddress` has an owner reference set to its `IPClaim` object, and
`IPClaim` objects have an owner reference set to the Metal3Data object created
from the Metal3DataTemplate, the owner reference chain links a Metal3Machine to
all the `IPClaim` and `IPAddress` objects created for it, allowing for CAPI
pivoting.

## What now ?

The project is fulfilling its basic requirements, but we are looking into
extending it and covering more use-cases. For example we are looking at
adding an integration with Infoblox and other external IPAM services. Do not
hesitate to open an issue if you have some ideas for new features!

The project can be found
[here](https://github.com/metal3-io/ip-address-manager).
