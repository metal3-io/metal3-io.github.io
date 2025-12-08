---
title: "One cluster - multiple providers"
date: 2022-07-08
draft: false
categories: ["metal3", "cluster API", "provider", "hybrid", "edge"]
author: Lennart Jern
---

Running on bare metal has both benefits and drawbacks. You can get the
best performance possible out of the hardware, but it can also be quite
expensive and maybe not necessary for _all_ workloads. Perhaps a hybrid
cluster could give you the best of both? Raw power for the workload that
needs it, and cheap virtualized commodity for the rest. This blog post
will show how to set up a cluster like this using the Cluster API backed
by the Metal3 and BYOH providers.

## The problem

Imagine that you have some bare metal servers that you want to use for
some specific workload. Maybe the workload benefits from the specific
hardware or there are some requirements that make it necessary to run it
there. The rest of the organization already uses Kubernetes and the
cluster API everywhere so of course you want the same for this as well.
Perfect, grab Metal³ and start working!

But hold on, this would mean that you use some of the servers for
running the Kubernetes control plane and possibly all the cluster API
controllers. If there are enough servers this is probably not an issue,
but do you really want to "waste" these servers on such generic
workloads that could be running anywhere? This can become especially
painful if you need multiple control plane nodes. Each server is
probably powerful enough to run all the control planes and controllers,
but it would be a single point of failure...

What if there was a way to use a different cluster API infrastructure
provider for some nodes? For example, use the Openstack infrastructure
provider for the control plane and Metal³ for the workers. Let's do an
experiment!

## Setting up the experiment environment

This blog post will use the [Bring your own
host](https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost)
(BYOH) provider together with Metal³ as a proof of concept to show what
is currently possible.

The BYOH provider was chosen as the second provider for two reasons:

1. Due to its design (you provision the host yourself), it is very easy
   to adapt it to the test (e.g. use a VM in the same network that the
   metal3-dev-env uses).
2. It is one of the providers that is known to work when combining
   multiple providers for a single cluster.

We will be using the
[metal3-dev-env](https://github.com/metal3-io/metal3-dev-env) on Ubuntu
as a starting point for this experiment. Note that it makes substantial
changes to the machine where it is running, so you may want to use a
dedicated lab machine instead of your laptop for this. If you have not
done so already, clone it and run `make`. This should give you a
management cluster with the Metal³ provider installed and two
BareMetalHosts ready for provisioning.

The next step is to add the BYOH provider and a ByoHost.

```bash
clusterctl init --infrastructure byoh
```

For the ByoHost we will use Vagrant.
You can install it with `sudo apt install vagrant`.
Then copy the Vagrantfile below to a new folder and run `vagrant up`.

```Vagrantfile
# -*- mode: ruby -*-
hosts = {
    "control-plane1" => { "memory" => 2048, "ip" => "192.168.10.10"},
    # "control-plane2" => { "memory" => 2048, "ip" => "192.168.10.11"},
    # "control-plane3" => { "memory" => 2048, "ip" => "192.168.10.12"},
}


Vagrant.configure("2") do |config|
    # Choose which box you want below
    config.vm.box = "generic/ubuntu2004"
    config.vm.synced_folder ".", "/vagrant", disabled: true
    config.vm.provider :libvirt do |libvirt|
      # QEMU system connection is required for private network configuration
      libvirt.qemu_use_session = false
    end


    # Loop over all machine names
    hosts.each_key do |host|
        config.vm.define host, primary: host == hosts.keys.first do |node|
            node.vm.hostname = host
            node.vm.network :private_network, ip: hosts[host]["ip"],
              libvirt__forward_mode: "route"
            node.vm.provider :libvirt do |lv|
                lv.memory = hosts[host]["memory"]
                lv.cpus = 2
            end
        end
    end
end
```

Vagrant should now have created a new VM to use as a ByoHost. Now we
just need to run the BYOH agent in the VM to make it register as a
ByoHost in the management cluster. The BYOH agent needs a kubeconfig
file to do this, so we start by copying it to the VM:

```bash
{%- comment -%}
Raw is needed to escape the double curly braces.
{%- endcomment -%}
{% raw %}
cp ~/.kube/config ~/.kube/management-cluster.conf
# Ensure that the correct IP is used (not localhost)
export KIND_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kind-control-plane)
sed -i 's/    server\:.*/    server\: https\:\/\/'"$KIND_IP"'\:6443/g' ~/.kube/management-cluster.conf
scp -i .vagrant/machines/control-plane1/libvirt/private_key \
  /home/ubuntu/.kube/management-cluster.conf vagrant@192.168.10.10:management-cluster.conf
{% endraw %}
```

Next, install the prerequisites and host agent in the VM and run it.

```bash
vagrant ssh
sudo apt install -y socat ebtables ethtool conntrack
wget https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost/releases/download/v0.2.0/byoh-hostagent-linux-amd64
mv byoh-hostagent-linux-amd64 byoh-hostagent
chmod +x byoh-hostagent
sudo ./byoh-hostagent --namespace metal3 --kubeconfig management-cluster.conf
```

You should now have a management cluster with both the Metal³ and BYOH
providers installed, as well as two BareMetalHosts and one ByoHost.

```console
$ kubectl -n metal3 get baremetalhosts,byohosts
NAME                             STATE       CONSUMER   ONLINE   ERROR   AGE
baremetalhost.metal3.io/node-0   available              true             18m
baremetalhost.metal3.io/node-1   available              true             18m


NAME                                                     AGE
byohost.infrastructure.cluster.x-k8s.io/control-plane1   73s
```

## Creating a multi-provider cluster

The trick is to create both a Metal3Cluster and a ByoCluster that are
owned by one common Cluster. We will use the ByoCluster for the control
plane in this case. First the Cluster:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  labels:
    cni: mixed-cluster-crs-0
    crs: "true"
  name: mixed-cluster
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/16
    serviceDomain: cluster.local
    services:
      cidrBlocks:
      - 10.128.0.0/12
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: mixed-cluster-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: ByoCluster
    name: mixed-cluster
```

Add the rest of the BYOH manifests to get a control plane.
The code is collapsed here for easier reading.
Please click on the line below to expand it.

<!-- markdownlint-disable MD033 -->

<details>
  <summary>KubeadmControlPlane, ByoCluster and ByoMachineTemplate</summary>
  <!-- Enable markdown parsing of the content. -->
  <div markdown="1">

<!-- markdownlint-enable MD033 -->

{%- raw %}

```yaml
#{% raw %}
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  labels:
    nodepool: pool0
  name: mixed-cluster-control-plane
spec:
  kubeadmConfigSpec:
    clusterConfiguration:
      apiServer:
        certSANs:
        - localhost
        - 127.0.0.1
        - 0.0.0.0
        - host.docker.internal
      controllerManager:
        extraArgs:
          enable-hostpath-provisioner: "true"
    files:
    - content: |
        apiVersion: v1
        kind: Pod
        metadata:
          creationTimestamp: null
          name: kube-vip
          namespace: kube-system
        spec:
          containers:
          - args:
            - start
            env:
            - name: vip_arp
              value: "true"
            - name: vip_leaderelection
              value: "true"
            - name: vip_address
              value: 192.168.10.20
            - name: vip_interface
              value: {{ .DefaultNetworkInterfaceName }}
            - name: vip_leaseduration
              value: "15"
            - name: vip_renewdeadline
              value: "10"
            - name: vip_retryperiod
              value: "2"
            image: ghcr.io/kube-vip/kube-vip:v0.3.5
            imagePullPolicy: IfNotPresent
            name: kube-vip
            resources: {}
            securityContext:
              capabilities:
                add:
                - NET_ADMIN
                - SYS_TIME
            volumeMounts:
            - mountPath: /etc/kubernetes/admin.conf
              name: kubeconfig
          hostNetwork: true
          volumes:
          - hostPath:
              path: /etc/kubernetes/admin.conf
              type: FileOrCreate
            name: kubeconfig
        status: {}
        owner: root:root
        path: /etc/kubernetes/manifests/kube-vip.yaml
    initConfiguration:
      nodeRegistration:
        criSocket: /var/run/containerd/containerd.sock
        ignorePreflightErrors:
        - Swap
        - DirAvailable--etc-kubernetes-manifests
        - FileAvailable--etc-kubernetes-kubelet.conf
    joinConfiguration:
      nodeRegistration:
        criSocket: /var/run/containerd/containerd.sock
        ignorePreflightErrors:
        - Swap
        - DirAvailable--etc-kubernetes-manifests
        - FileAvailable--etc-kubernetes-kubelet.conf
  machineTemplate:
    infrastructureRef:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: ByoMachineTemplate
      name: mixed-cluster-control-plane
  replicas: 1
  version: v1.23.5
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: ByoCluster
metadata:
  name: mixed-cluster
spec:
  bundleLookupBaseRegistry: projects.registry.vmware.com/cluster_api_provider_bringyourownhost
  bundleLookupTag: v1.23.5
  controlPlaneEndpoint:
    host: 192.168.10.20
    port: 6443
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: ByoMachineTemplate
metadata:
  name: mixed-cluster-control-plane
spec:
  template:
    spec: {}
#{% endraw %}
```

  </div>
</details>

So far this is a "normal" Cluster backed by the BYOH provider. But now
it is time to do something different. Instead of adding more ByoHosts as
workers, we will add a Metal3Cluster and MachineDeployment backed by
BareMetalHosts! Note that the `controlPlaneEndpoint` of the
Metal3Cluster must point to the same endpoint that the ByoCluster is
using.

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Cluster
metadata:
  name: mixed-cluster
spec:
  controlPlaneEndpoint:
    host: 192.168.10.20
    port: 6443
  noCloudProvider: true
```

<!-- markdownlint-disable MD033 -->

<details>
  <summary>IPPools</summary>
  <div markdown="1">

<!-- markdownlint-enable MD033 -->

```yaml
apiVersion: ipam.metal3.io/v1alpha1
kind: IPPool
metadata:
  name: provisioning-pool
spec:
  clusterName: mixed-cluster
  namePrefix: test1-prov
  pools:
  - end: 172.22.0.200
    start: 172.22.0.100
  prefix: 24
---
apiVersion: ipam.metal3.io/v1alpha1
kind: IPPool
metadata:
  name: baremetalv4-pool
spec:
  clusterName: mixed-cluster
  gateway: 192.168.111.1
  namePrefix: test1-bmv4
  pools:
  - end: 192.168.111.200
    start: 192.168.111.100
  prefix: 24
```

  </div>
</details>

These manifests are quite large but they are just the same as would be
used by the metal3-dev-env with some name changes here and there. The
key thing to note is that all references to a Cluster are to the one we
defined above. Here is the MachineDeployment:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  labels:
    cluster.x-k8s.io/cluster-name: mixed-cluster
    nodepool: nodepool-0
  name: test1
spec:
  clusterName: mixed-cluster
  replicas: 1
  selector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: mixed-cluster
      nodepool: nodepool-0
  template:
    metadata:
      labels:
        cluster.x-k8s.io/cluster-name: mixed-cluster
        nodepool: nodepool-0
    spec:
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: KubeadmConfigTemplate
          name: test1-workers
      clusterName: mixed-cluster
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: test1-workers
      nodeDrainTimeout: 0s
      version: v1.23.5
```

Finally, we add the Metal3MachineTemplate, Metal3DataTemplate and
KubeadmConfigTemplate. Here you may want to add your public ssh key in
the KubeadmConfigTemplate (the last few lines).

<!-- markdownlint-disable MD033 -->

<details>
  <summary>Metal3MachineTemplate, Metal3DataTemplate and KubeadmConfigTemplate</summary>
  <!-- Enable markdown parsing of the content. -->
  <div markdown="1">

<!-- markdownlint-enable MD033 -->

```yaml
#{% raw %}
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: test1-workers
spec:
  template:
    spec:
      dataTemplate:
        name: test1-workers-template
      image:
        checksum: http://172.22.0.1/images/UBUNTU_22.04_NODE_IMAGE_K8S_v1.23.5-raw.img.md5sum
        checksumType: md5
        format: raw
        url: http://172.22.0.1/images/UBUNTU_22.04_NODE_IMAGE_K8S_v1.23.5-raw.img
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3DataTemplate
metadata:
  name: test1-workers-template
  namespace: metal3
spec:
  clusterName: mixed-cluster
  metaData:
    ipAddressesFromIPPool:
    - key: provisioningIP
      name: provisioning-pool
    objectNames:
    - key: name
      object: machine
    - key: local-hostname
      object: machine
    - key: local_hostname
      object: machine
    prefixesFromIPPool:
    - key: provisioningCIDR
      name: provisioning-pool
  networkData:
    links:
      ethernets:
      - id: enp1s0
        macAddress:
          fromHostInterface: enp1s0
        type: phy
      - id: enp2s0
        macAddress:
          fromHostInterface: enp2s0
        type: phy
    networks:
      ipv4:
      - id: baremetalv4
        ipAddressFromIPPool: baremetalv4-pool
        link: enp2s0
        routes:
        - gateway:
            fromIPPool: baremetalv4-pool
          network: 0.0.0.0
          prefix: 0
    services:
      dns:
      - 8.8.8.8
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: KubeadmConfigTemplate
metadata:
  name: test1-workers
spec:
  template:
    spec:
      files:
      - content: |
          network:
            version: 2
            renderer: networkd
            bridges:
              ironicendpoint:
                interfaces: [enp1s0]
                addresses:
                - {{ ds.meta_data.provisioningIP }}/{{ ds.meta_data.provisioningCIDR }}
        owner: root:root
        path: /etc/netplan/52-ironicendpoint.yaml
        permissions: "0644"
      - content: |
          [registries.search]
          registries = ['docker.io']
          [registries.insecure]
          registries = ['192.168.111.1:5000']
        path: /etc/containers/registries.conf
      joinConfiguration:
        nodeRegistration:
          kubeletExtraArgs:
            cgroup-driver: systemd
            container-runtime: remote
            container-runtime-endpoint: unix:///var/run/crio/crio.sock
            feature-gates: AllAlpha=false
            node-labels: metal3.io/uuid={{ ds.meta_data.uuid }}
            provider-id: metal3://{{ ds.meta_data.uuid }}
            runtime-request-timeout: 5m
          name: "{{ ds.meta_data.name }}"
      preKubeadmCommands:
      - netplan apply
      - systemctl enable --now crio kubelet
      users:
      - name: metal3
        # sshAuthorizedKeys:
        # - add your public key here for debugging
        sudo: ALL=(ALL) NOPASSWD:ALL
#{% endraw %}
```

  </div>
</details>

The result of all this is a Cluster with two Machines, one from the
Metal³ provider and one from the BYOH provider.

```console
$ k -n metal3 get machine
NAME                                CLUSTER         NODENAME                PROVIDERID                                      PHASE     AGE     VERSION
mixed-cluster-control-plane-48qmm   mixed-cluster   control-plane1          byoh://control-plane1/jf5uye                    Running   7m41s   v1.23.5
test1-8767dbccd-24cl5               mixed-cluster   test1-8767dbccd-24cl5   metal3://0642d832-3a7c-4ce9-833e-a629a60a455c   Running   7m18s   v1.23.5
```

Let's also check that the workload cluster is functioning as expected.
Get the kubeconfig and add Calico as CNI.

```bash
clusterctl get kubeconfig -n metal3 mixed-cluster > kubeconfig.yaml
export KUBECONFIG=kubeconfig.yaml
kubectl apply -f https://docs.projectcalico.org/v3.20/manifests/calico.yaml
```

Now check the nodes.

```console
$ kubectl get nodes
NAME                    STATUS   ROLES                  AGE   VERSION
control-plane1          Ready    control-plane,master   88m   v1.23.5
test1-8767dbccd-24cl5   Ready    <none>                 82m   v1.23.5
```

Going back to the management cluster, we can inspect the state of the
cluster API resources.

```console
$ clusterctl -n metal3 describe cluster mixed-cluster
NAME                                                                        READY  SEVERITY  REASON  SINCE  MESSAGE
Cluster/mixed-cluster                                                       True                     13m
├─ClusterInfrastructure - ByoCluster/mixed-cluster
├─ControlPlane - KubeadmControlPlane/mixed-cluster-control-plane            True                     13m
│ └─Machine/mixed-cluster-control-plane-hp2fp                               True                     13m
│   └─MachineInfrastructure - ByoMachine/mixed-cluster-control-plane-vxft5
└─Workers
  └─MachineDeployment/test1                                                 True                     3m57s
    └─Machine/test1-7f77dfb7c8-j7x4q                                        True                     9m32s
```

## Conclusion

As we have seen in this post, it is possible to combine at least some
infrastructure providers when creating a single cluster. This can be
useful for example if a provider has a high cost or limited resources.
Furthermore, the use case is not addressed by MachineDeployments since
they would all be from the same provider (even though they can have
different properties).

There is some room for development and improvement though. The most
obvious thing is perhaps that Clusters only have one
`infrastructureRef`. This means that the cluster API controllers are not
aware of the "secondary" infrastructure provider(s).

Another thing that may be less obvious is the reliance on Nodes and
Machines in the Kubeadm control plane provider. It is not an issue in
the example we have seen here since both Metal³ and BYOH creates Nodes.
However, there are some projects where Nodes are unnecessary. See for
example [Kamaji](https://github.com/clastix/kamaji), which aims to
integrate with the cluster API. The idea here is to run the control
plane components in the management cluster as Pods. Naturally, there
would not be any control plane Nodes or Machines in this case. (A second
provider would be used to add workers.) But the Kubeadm control plane
provider expects there to be both Machines and Nodes for the control
plane, so a new provider is likely needed to make this work as desired.

This issue can already be seen in the
[vcluster](https://github.com/loft-sh/cluster-api-provider-vcluster)
provider, where the Cluster stays in `Provisioning` state because it is
"Waiting for the first control plane machine to have its
`status.nodeRef` set". The idea with vcluster is to reuse the Nodes of
the management cluster but provide a separate control plane. This gives
users better isolation than just namespaces without the need for another
"real" cluster. It is for example possible to have different custom
resource definitions in each vcluster. But since vcluster runs all the
pods (including the control plane) in the management cluster, there will
never be a control plane Machine or `nodeRef`.

There is already one implementation of a control plane provider without
Nodes, i.e. the EKS provider. Perhaps this is the way forward. One
implementation for each specific case. It would be nice if it was
possible to do it in a more generic way though, similar to how the
Kubeadm control plane provider is used by almost all infrastructure
providers.

To summarize, there is already some support for mixed clusters with
multiple providers. However, there are some issues that make it
unnecessarily awkward. Two things that could be improved in the cluster
API would be the following:

1. Make the `cluster.infrastructureRef` into a list to allow multiple
   infrastructure providers to be registered.
2. Drop the assumption that there will always be control plane Machines
   and Nodes (e.g. by implementing a new control plane provider).
