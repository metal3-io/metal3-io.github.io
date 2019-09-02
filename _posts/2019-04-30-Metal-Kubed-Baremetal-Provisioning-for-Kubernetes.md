---
layout: post
title:  "Metal³: Baremetal Provisioning for Kubernetes"
date:   2019-04-30 20:01:58 +0000
author: Russell Bryant
categories: ["openshift", "kubernetes", "metal3"]
---
Originally posted at <https://blog.russellbryant.net/2019/04/30/metal%c2%b3-metal-kubed-bare-metal-provisioning-for-kubernetes/>

## Project Introduction

There are a number of great open source tools for bare metal host provisioning, including [Ironic](https://docs.openstack.org/ironic/latest/install/refarch/common.html). Metal³ aims to build on these technologies to provide a Kubernetes native API for managing bare metal hosts via a provisioning stack that is also running on Kubernetes. We believe that Kubernetes Native Infrastructure, or managing your infrastructure just like your applications, is a powerful next step in the evolution of infrastructure management.

The Metal³ project is also building integration with the Kubernetes [cluster-api](https://github.com/kubernetes-sigs/cluster-api) project, allowing Metal³ to be used as an infrastructure backend for Machine objects from the Cluster API.

## Metal3 Repository Overview

There is a Metal³ overview and some more detailed design documents in the [metal3-docs](https://github.com/metal3-io/metal3-docs) repository.

The [baremetal-operator](https://github.com/metal3-io/baremetal-operator) is the component that manages bare metal hosts. It exposes a new BareMetalHost custom resource in the Kubernetes API that lets you manage hosts in a declarative way.

Finally, the [cluster-api-provider-baremetal](https://github.com/metal3-io/cluster-api-provider-baremetal) repository includes integration with the [cluster-api](https://github.com/kubernetes-sigs/cluster-api) project. This provider currently includes a Machine actuator that acts as a client of the BareMetalHost custom resources.

## Demo

The project has been going for a few months now, and there’s enough now to show some working code.

For this demonstration, I’ve started with a 3 node Kubernetes cluster installed using [OpenShift](https://www.openshift.com/).

~~~sh
$ kubectl get nodes
NAME       STATUS   ROLES    AGE   VERSION
master-0   Ready    master   24h   v1.13.4+d4ce02c1d
master-1   Ready    master   24h   v1.13.4+d4ce02c1d
master-2   Ready    master   24h   v1.13.4+d4ce02c1d
~~~

Machine objects were created to reflect these 3 masters, as well.

~~~sh
$ kubectl get machines
NAME              INSTANCE   STATE   TYPE   REGION   ZONE   AGE
ostest-master-0                                             24h
ostest-master-1                                             24h
ostest-master-2                                             24h
~~~

For this cluster-api provider, a Machine has a corresponding BareMetalHost object, which corresponds to the piece of hardware we are managing. There is a design document that covers [the relationship between Nodes, Machines, and BareMetalHosts](https://github.com/metal3-io/metal3-docs/blob/master/design/nodes-machines-and-hosts.md).

Since these hosts were provisioned earlier, they are in a special `externally provisioned` state, indicating that we enrolled them in management while they were already running in a desired state. If changes are needed going forward, the baremetal-operator will be able to automate them.

~~~sh
$ kubectl get baremetalhosts
NAME                 STATUS   PROVISIONING STATUS      MACHINE           BMC                         HARDWARE PROFILE   ONLINE   ERROR
openshift-master-0   OK       externally provisioned   ostest-master-0   ipmi://192.168.111.1:6230                      true
openshift-master-1   OK       externally provisioned   ostest-master-1   ipmi://192.168.111.1:6231                      true
openshift-master-2   OK       externally provisioned   ostest-master-2   ipmi://192.168.111.1:6232                      true
~~~

Now suppose we’d like to expand this cluster by adding another bare metal host to serve as a worker node. First we need to create a new BareMetalHost object that adds this new host to the inventory of hosts managed by the baremetal-operator. Here’s the YAML for the new BareMetalHost:

~~~yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: openshift-worker-0-bmc-secret
type: Opaque
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQ=

---
apiVersion: metalkube.org/v1alpha1
kind: BareMetalHost
metadata:
  name: openshift-worker-0
spec:
  online: true
  bmc:
    address: ipmi://192.168.111.1:6233
    credentialsName: openshift-worker-0-bmc-secret
  bootMACAddress: 00:ab:4f:d8:9e:fa
~~~

Now to add the BareMetalHost and its IPMI credentials Secret to the cluster:

~~~sh
$ kubectl create -f worker_crs.yaml
secret/openshift-worker-0-bmc-secret created
baremetalhost.metalkube.org/openshift-worker-0 created
~~~

The list of BareMetalHosts now reflects a new host in the inventory that is ready to be provisioned. It will remain in this `ready` state until it is claimed by a new Machine object.

~~~sh
$ kubectl get baremetalhosts
NAME                 STATUS   PROVISIONING STATUS      MACHINE           BMC                         HARDWARE PROFILE   ONLINE   ERROR
openshift-master-0   OK       externally provisioned   ostest-master-0   ipmi://192.168.111.1:6230                      true
openshift-master-1   OK       externally provisioned   ostest-master-1   ipmi://192.168.111.1:6231                      true
openshift-master-2   OK       externally provisioned   ostest-master-2   ipmi://192.168.111.1:6232                      true
openshift-worker-0   OK       ready                                      ipmi://192.168.111.1:6233   unknown            true
~~~

We have a MachineSet already created for workers, but it scaled down to 0.

~~~sh
$ kubectl get machinesets
NAME              DESIRED   CURRENT   READY   AVAILABLE   AGE
ostest-worker-0   0         0                             24h
~~~

We can scale this MachineSet to 1 to indicate that we’d like a worker provisioned. The baremetal cluster-api provider will then look for an available BareMetalHost, claim it, and trigger provisioning of that host.

`$ kubectl scale machineset ostest-worker-0 --replicas=1`

After the new Machine was created, our cluster-api provider claimed the available host and triggered it to be provisioned.

~~~sh
$ kubectl get baremetalhosts
NAME                 STATUS   PROVISIONING STATUS      MACHINE                 BMC                         HARDWARE PROFILE   ONLINE   ERROR
openshift-master-0   OK       externally provisioned   ostest-master-0         ipmi://192.168.111.1:6230                      true
openshift-master-1   OK       externally provisioned   ostest-master-1         ipmi://192.168.111.1:6231                      true
openshift-master-2   OK       externally provisioned   ostest-master-2         ipmi://192.168.111.1:6232                      true
openshift-worker-0   OK       provisioning             ostest-worker-0-jmhtc   ipmi://192.168.111.1:6233   unknown            true
~~~

This process takes some time. Under the hood, the baremetal-operator is driving Ironic through a provisioning process. This begins with wiping disks to ensure the host comes up in a clean state. It will eventually write the desired OS image to disk and then reboot into that OS. When complete, a new Kubernetes Node will register with the cluster.

~~~sh
$ kubectl get baremetalhosts
NAME                 STATUS   PROVISIONING STATUS      MACHINE                 BMC                         HARDWARE PROFILE   ONLINE   ERROR
openshift-master-0   OK       externally provisioned   ostest-master-0         ipmi://192.168.111.1:6230                      true
openshift-master-1   OK       externally provisioned   ostest-master-1         ipmi://192.168.111.1:6231                      true
openshift-master-2   OK       externally provisioned   ostest-master-2         ipmi://192.168.111.1:6232                      true
openshift-worker-0   OK       provisioned              ostest-worker-0-jmhtc   ipmi://192.168.111.1:6233   unknown            true

$ kubectl get nodes
NAME       STATUS   ROLES    AGE   VERSION
master-0   Ready    master   24h   v1.13.4+d4ce02c1d
master-1   Ready    master   24h   v1.13.4+d4ce02c1d
master-2   Ready    master   24h   v1.13.4+d4ce02c1d
worker-0   Ready    worker   68s   v1.13.4+d4ce02c1d
~~~

The following screen cast demonstrates this process, as well:

[![Machine API driven bare metal worker deployment (OpenShift)](https://asciinema.org/a/c1qITPktXyIIHvzDUket3buwQ.svg)](https://asciinema.org/a/c1qITPktXyIIHvzDUket3buwQ)

Removing a bare metal host from the cluster is very similar. We just have to scale this MachineSet back down to 0.

`$ kubectl scale machineset ostest-worker-0 --replicas=0`

Once the Machine has been deleted, the baremetal-operator will deprovision the bare metal host.

~~~sh
$ kubectl get baremetalhosts
NAME                 STATUS   PROVISIONING STATUS      MACHINE           BMC                         HARDWARE PROFILE   ONLINE   ERROR
openshift-master-0   OK       externally provisioned   ostest-master-0   ipmi://192.168.111.1:6230                      true
openshift-master-1   OK       externally provisioned   ostest-master-1   ipmi://192.168.111.1:6231                      true
openshift-master-2   OK       externally provisioned   ostest-master-2   ipmi://192.168.111.1:6232                      true
openshift-worker-0   OK       deprovisioning                             ipmi://192.168.111.1:6233   unknown            false
~~~

Once the deprovisioning process is complete, the bare metal host will be back to its `ready` state, available in the host inventory to be claimed by a future Machine object.

~~~sh
$ kubectl get baremetalhosts
NAME                 STATUS   PROVISIONING STATUS      MACHINE           BMC                         HARDWARE PROFILE   ONLINE   ERROR
openshift-master-0   OK       externally provisioned   ostest-master-0   ipmi://192.168.111.1:6230                      true
openshift-master-1   OK       externally provisioned   ostest-master-1   ipmi://192.168.111.1:6231                      true
openshift-master-2   OK       externally provisioned   ostest-master-2   ipmi://192.168.111.1:6232                      true
openshift-worker-0   OK       ready                                      ipmi://192.168.111.1:6233   unknown            false
~~~

## Getting Involved

All development is happening on [github](https://github.com/metal3-io). We have a [metal3-dev mailing list](https://groups.google.com/forum/#!forum/metal3-dev) and use #cluster-api-baremetal on [Kubernetes Slack](https://slack.k8s.io/) to chat. Occasional project updates are posted to [@metal3_io on Twitter](https://twitter.com/metal3_io).
