---
title: "Scaling to 1000 clusters - Part 1"
date: 2023-05-05
draft: false
categories: ["metal3", "cluster API", "provider", "edge"]
author: Lennart Jern
---

We want to ensure that Metal3 can scale to thousands of nodes and clusters.
However, running tests with thousands of real servers is expensive and we don't have access to any such large environment in the project.
So instead we have been focusing on faking the hardware while trying to keep things as realistic as possible for the controllers.
In this first part we will take a look at the Bare Metal Operator and the [test mode](https://github.com/metal3-io/baremetal-operator/blob/b76dde223937009cebb9da85e6f1793a544675e6/docs/dev-setup.md?plain=1#L62) it offers.
The next part will be about how to fake the Kubernetes API of the workload clusters.
In the final post we will take a look at the issues we ran into and what is being done in the community to address them so that we can keep scaling!

## Some background on how to fool the controllers

With the full Metal3 stack, from Ironic to Cluster API, we have the following controllers that operate on Kubernetes APIs:

- Cluster API Kubeadm control plane controller
- Cluster API Kubeadm bootstrap controller
- Cluster API controller
- Cluster API provider for Metal3 controller
- IP address manager controller
- Bare Metal Operator controller

We will first focus on the controllers that interact with Nodes, Machines, Metal3Machines and BareMetalHosts, i.e. objects related to actual physical machines that we need to fake.
In other words, we are skipping the IP address manager for now.

What do these controllers care about really?
What do we need to do to fool them?
At the Cluster API level, the controllers just care about the Kubernetes resources in the management cluster (e.g. Clusters and Machines) and some resources in the workload cluster (e.g. Nodes and the etcd Pods).
The controllers will try to connect to the workload clusters in order to check the status of the resources there, so if there is no real workload cluster, this is something we will need to fake if we want to fool the controllers.
When it comes to Cluster API provider for Metal3, it connects the abstract high level objects with the BareMetalHosts, so here we will need to make the BareMetalHosts to behave realistically in order to provide a good test.

This is where the Bare Metal Operator test mode comes in.
If we can fake the workload cluster API and the BareMetalHosts, then all the Cluster API controllers and the Metal3 provider will get a realistic test that we can use when working on scalability.

## Bare Metal Operator test mode

The Bare Metal Operator has a test mode, in which it doesn't talk to Ironic.
Instead it just pretends that everything is fine and all actions succeed.
In this mode the BareMetalHosts will move through the state diagram just like they normally would (but quite a bit faster).
To enable it, all you have to do is add the `-test-mode` flag when running the Bare Metal Operator controller.
For convenience there is also a make target (`make run-test-mode`) that will run the Bare Metal Operator directly on the host in test mode.

Here is an example of how to use it.
You will need kind and kubectl installed for this to work, but you don't need the Bare Metal Operator repository cloned.

1. Create a kind cluster and deploy cert-manager (needed for web hook certificates):

   ```bash
   kind create cluster
   # Install cert-manager
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
   ```

1. Deploy the Bare Metal Operator in test mode:

   ```bash
   # Create the namespace where it will run
   kubectl create ns baremetal-operator-system
   # Deploy it in normal mode
   kubectl apply -k https://github.com/metal3-io/baremetal-operator/config/default
   # Patch it to run in test mode
   kubectl patch -n baremetal-operator-system deploy baremetal-operator-controller-manager --type=json \
     -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--test-mode"}]'
   ```

1. In a separate terminal, create a BareMetalHost from the example manifests:

   ```bash
   kubectl apply -f https://github.com/metal3-io/baremetal-operator/raw/main/examples/example-host.yaml
   ```

After applying the BareMetalHost, it will quickly go through `registering` and become `available`.

```console
$ kubectl get bmh
NAME                    STATE         CONSUMER   ONLINE   ERROR   AGE
example-baremetalhost   registering              true             2s
$ kubectl get bmh
NAME                    STATE       CONSUMER   ONLINE   ERROR   AGE
example-baremetalhost   available              true             6s
```

We can now provision the BareMetalHost, turn it off, deprovision, etc.
Just like normal, except that the machine doesn't exist.
Let's try provisioning it!

```bash
kubectl patch bmh example-baremetalhost --type=merge --patch-file=/dev/stdin <<EOF
spec:
  image:
    url: "http://example.com/totally-fake-image.vmdk"
    checksum: "made-up-checksum"
    format: vmdk
EOF
```

You will see it go through `provisioning` and end up in `provisioned` state:

```console
$ kubectl get bmh
NAME                    STATE          CONSUMER   ONLINE   ERROR   AGE
example-baremetalhost   provisioning              true             7m20s

$ kubectl get bmh
NAME                    STATE         CONSUMER   ONLINE   ERROR   AGE
example-baremetalhost   provisioned              true             7m22s
```

## Wrapping up

With Bare Metal Operator in test mode, we have the foundation for starting our scalability journey.
We can easily create BareMetalHost objects and they behave similar to what they would in a real scenario.
A simple bash script will at this point allow us to create as many BareMetalHosts as we would like.
To wrap things up, we will now do just that: put together a script and try generating a few BareMetalHosts.

The script will do the same thing we did before when creating the example BareMetalHost, but it will also give them different names so we don't get naming collisions.
Here it is:

```bash
#!/usr/bin/env bash

set -eu

create_bmhs() {
  n="${1}"
  for (( i = 1; i <= n; ++i )); do
    cat << EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: worker-$i-bmc-secret
type: Opaque
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQ=
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-$i
spec:
  online: true
  bmc:
    address: libvirt://192.168.122.$i:6233/
    credentialsName: worker-$i-bmc-secret
  bootMACAddress: "$(printf '00:60:2F:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))"
EOF
  done
}

NUM="${1:-10}"

create_bmhs "${NUM}"
```

Save it as `produce-available-hosts.sh` and try it out:

```console
$ ./produce-available-hosts.sh 10 | kubectl apply -f -
secret/worker-1-bmc-secret created
baremetalhost.metal3.io/worker-1 created
secret/worker-2-bmc-secret created
baremetalhost.metal3.io/worker-2 created
secret/worker-3-bmc-secret created
baremetalhost.metal3.io/worker-3 created
secret/worker-4-bmc-secret created
baremetalhost.metal3.io/worker-4 created
secret/worker-5-bmc-secret created
baremetalhost.metal3.io/worker-5 created
secret/worker-6-bmc-secret created
baremetalhost.metal3.io/worker-6 created
secret/worker-7-bmc-secret created
baremetalhost.metal3.io/worker-7 created
secret/worker-8-bmc-secret created
baremetalhost.metal3.io/worker-8 created
secret/worker-9-bmc-secret created
baremetalhost.metal3.io/worker-9 created
secret/worker-10-bmc-secret created
baremetalhost.metal3.io/worker-10 created
$ kubectl get bmh
NAME        STATE         CONSUMER   ONLINE   ERROR   AGE
worker-1    registering              true             2s
worker-10   available                true             2s
worker-2    available                true             2s
worker-3    available                true             2s
worker-4    available                true             2s
worker-5    available                true             2s
worker-6    registering              true             2s
worker-7    available                true             2s
worker-8    available                true             2s
worker-9    available                true             2s
```

With this we conclude the first part of the scaling series.
In the next post, we will take a look at how to fake the other end of the stack: the workload cluster API.
