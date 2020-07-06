---
title: "Metal³ development environment walkthrough part 2: Deploying a new bare metal cluster"
draft: false
categories: ["metal3", "kubernetes", "cluster API", "metal3-dev-env"]
author: Himanshu Roy
---

## Introduction

This blog post describes how to deploy a bare metal cluster, a virtual one for simplicity, using [Metal³/metal3-dev-env](https://github.com/metal3-io/metal3-dev-env). We will briefly discuss the steps involved in setting up the cluster as well as some of the customization available. If you want to know more about the architecture of Metal³, this [blogpost]({%post_url 2020-02-27-talk-kubernetes-finland-metal3 %}) can be helpful.

This post builds upon the [detailed metal3-dev-env walkthrough blogpost]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %}) which describes in detail the steps involved in the environment set up and management cluster configuration. Here we will use that environment to deploy a new Kubernetes cluster using Metal³.

Before we get started, there are a couple of requirements we are expecting to be fulfilled.


## Requirements

- Metal³ is already deployed and working,  if not please follow the instructions in the previously mentioned [detailed metal3-dev-env walkthrough blogpost]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %}).
- The appropriate environment variables are setup via shell or in the `config_${user}.sh` file, for example -
  - CAPI_VERSION
  - NUM_NODES
  - CLUSTER_NAME


## Overview of Config and Resource types
In this section we give a brief overview of the important config files and resources used as part of the bare metal cluster deployment. 
The following sub-sections show the config files and resources that are created and give a brief description about some of them. This will help you understand the technical details of the cluster deployment. You can also choose to skip this section, visit the next section about *provisioning* first and then revisit this.


### Config Files and Resources Types

!["The directory tree for the ansible role used for deployment"](/assets/2020-06-18-Metal3-dev-env-BareMetal-Cluster-Deployment/manifest-directory.png)  
> info "Note"
> Among these the config files are rendered under the path `https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/files` as part of the provisioning process.

<br/>

A description of some of the files part of provisioning a cluster, in a centos based environment :

| Name           | Description                                       | Path                          |
| ------------------- | ---------------------------------------------| ----------------------------- |
| (de)provisioning scripts| Scripts to trigger provisioning or deprovisioning of cluster, control plane or worker | `${metal3-dev-env}/scripts/v1alphaX/` |
| [templates directory](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/templates) | Templates for cluster, control plane, worker definitions | `${metal3-dev-env}/vm-setup/roles/v1aX_integration_test/templates` |
| clusterctl env file   | Cluster parameters and details  | `${Manifests}/clusterctl_env_centos.rc` |
| [generate templates](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/tasks/generate_templates.yml) | Renders cluster, control plane and worker definitions in the `Manifest` directory | `${metal3-dev-env}/vm-setup/roles/v1aX_integration_test/tasks/generate_templates.yml` |
| [main vars file](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/vars/main.yml)    | Variable file that assigns all the defaults used during deployment  | `${metal3-dev-env}/vm-setup/roles/v1aX_integration_test/vars/main.yml`  |


<br/>


Here are some of the resources that are created as part of provisioning :

| Name                | Description                                       |
| ------------------- | ------------------------------------------------- | 
| Cluster | a Cluster API resource for managing a cluster |
| Metal3Cluster | Corresponding Metal3 resource generated as part of bare metal cluster deployment, and managed by `Cluster`|
| KubeadmControlPlane | Cluster API resource for managing the control plane, it also manages the `Machine` object, and has the **KubeadmConfig** |
| MachineDeployment | Cluster API resource for managing workers via `MachineSet` object, it can be used to add/remove workers by scaling Up/Down |
| MachineSet | Cluster API resource for managing `Machine` objects for worker nodes |
| Machine | Cluster API resource for managing nodes - control plane or workers. In case of Controlplane, its directly managed by `KubeadmControlPlane`, whereas for Workers it's managed by a `MachineSet`|
| Metal3Machine | Corresponding Metal3 resource for managing bare metal nodes, it's managed by a `Machine` resource |
| Metal3MachineTemplate | Metal3 resource which acts as a template when creating a control plane or a worker node |
| KubeadmConfigTemplate | A template of `KubeadmConfig`, for Workers, used to generate KubeadmConfig when a new worker node is provisioned |

> **Note** : The corresponding `KubeadmConfig` is copied to the control plane/worker at the time of provisioning.  
  
<br/>


## Bare Metal Cluster Deployment

The deployment scripts primarily use ansible and the existing Kubernetes management cluster (based on minikube ) for deploying the bare-metal cluster. Make sure that some of the environment variables used for Metal³ deployment are set, if you didn't use `config_${user}.sh` for setting the environment variables.

| Parameter           | Description                  | Default                  |
| ------------------- | ---------------------------- | ------------------------ |
| CAPI_VERSION        | Version of Metal3 API4       | v1alpha3        |
| POD_CIDR            | Pod Network CIDR             | 192.168.0.0/18           |
| CLUSTER_NAME        | Name of bare metal cluster   | test1                    |

<br/>


### Steps Involved

All the scripts for cluster provisioning or deprovisioning are located at - [`${metal3-dev-env}/scripts/v1alphaX/`](https://github.com/metal3-io/metal3-dev-env/tree/master/scripts/v1alphaX). The scripts call a common playbook which handles all the tasks that are available.


The steps involved in the process are :

- The script calls an ansible playbook with necessary parameter ( from env variables and defaults )
- The playbook executes the role -, [`${metal3-dev-env}/vm-setup/roles/v1aX_integration_test`](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test), which runs the main [task_file](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/tasks/main.yml) for provisioning/deprovisioning the cluster, control plane or a worker
- There are [templates](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/templates) in the role, which are used to render configurations in the `Manifest` directory. These configurations use kubeadm and are supplied to the Kubernetes module of ansible to create the cluster.
- During provisioning, first the `clusterctl` env file is generated, then the cluster, control plane and worker definition templates for `clusterctl` are generated at `${HOME}/.cluster-api/overrides/infrastructure-metal3/${CAPM3RELEASE}`.
- Using the templates generated in previous step, the definitions for resources related to cluster, control plane and worker are rendered using `clusterctl`.
- Centos or Ubuntu image [is downloaded](https://github.com/metal3-io/metal3-dev-env/blob/master/vm-setup/roles/v1aX_integration_test/tasks/download_image.yml) in the next step.
- Finally using the above definitions, which are passed to the `K8s` module in ansible, the corresponding resource( cluster/control plane/worker ) is provisioned.
- These same definitions are reused at the time of deprovisioning the corresponding resource, again using the `K8s` module in ansible
> **Note** : The manifest directory is created when provisioning is triggered for the first time and is subsequently used to store the config files that are rendered for deploying the bare metal cluster.

<br/>
<br/>





!["An Overview of various resources generated while provisioning and their relationship amongst themselves"](/assets/2020-06-18-Metal3-dev-env-BareMetal-Cluster-Deployment/metal3-bmetal-arch-overview.png)  
<br/>
<br/>


### Provision Cluster
This script, located at the path - `${metal3-dev-env}/scripts/v1alphaX/provision_clusters.sh`, provisions the cluster by creating a `Metal3Cluster` and a `Cluster` resource. 

<br/>
To see if you have a successful Cluster resource creation( the cluster still doesn't have a control plane or workers ), just do :

```console
kubectl get Metal3Cluster ${CLUSTER_NAME} -n metal3
```
> This will return the cluster deployed, and you can check the cluster details by describing the returned resource.

<br/>
Here is what a `Cluster` resource looks like :

```console
kubectl describe Cluster ${CLUSTER_NAME} -n metal3
```

```yaml
apiVersion: cluster.x-k8s.io/v1alpha3
kind: Cluster
metadata:
  [......]
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
      - 192.168.0.0/18
    services:
      cidrBlocks:
      - 10.96.0.0/12
  controlPlaneEndpoint:
    host: 192.168.111.249
    port: 6443
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1alpha3
    kind: KubeadmControlPlane
    name: bmetalcluster
    namespace: metal3
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
    kind: Metal3Cluster
    name: bmetalcluster
    namespace: metal3
status:
  infrastructureReady: true
  phase: Provisioned
```
  
<br/>
<br/>

### Provision Controlplane

This script, located at the path - `${metal3-dev-env}/scripts/v1alphaX/provision_clusters.sh`, provisions the control plane member of the cluster using the rendered definition of control plane explained in the **Steps Involved** section. The `KubeadmControlPlane` creates a `Machine` which picks up a BareMetalHost satisfying its requirements as the control plane node, and it is then provisioned by the Bare Metal Operator. A `Metal3MachineTemplate` resource is also created as part of the provisioning process.

> info "Note"
> It takes some time for the provisioning of the control plane, you can watch the process using some steps shared a bit later

```console
kubectl get KubeadmControlPlane ${CLUSTER_NAME} -n metal3
kubectl describe KubeadmControlPlane ${CLUSTER_NAME} -n metal3
```

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1alpha3
kind: KubeadmControlPlane
metadata:
  [....]
  ownerReferences:
  - apiVersion: cluster.x-k8s.io/v1alpha3
    blockOwnerDeletion: true
    controller: true
    kind: Cluster
    name: bmetalcluster
    uid: aec0f73b-a068-4992-840d-6330bf943d22
  resourceVersion: "44555"
  selfLink: /apis/controlplane.cluster.x-k8s.io/v1alpha3/namespaces/metal3/kubeadmcontrolplanes/bmetalcluster
  uid: 99487c75-30f1-4765-b895-0b83b0e5402b
spec:
  infrastructureTemplate:
    apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
    kind: Metal3MachineTemplate
    name: bmetalcluster-controlplane
    namespace: metal3
  kubeadmConfigSpec:
    files:
    - content: |
        [....]
  replicas: 1
  version: v1.18.0
status:
  replicas: 1
  selector: cluster.x-k8s.io/cluster-name=bmetalcluster,cluster.x-k8s.io/control-plane=
  unavailableReplicas: 1
  updatedReplicas: 1
```

```console
kubectl get Metal3MachineTemplate ${CLUSTER_NAME}-controlplane -n metal3
```

<br/>

To track the progress of provisioning, you can try the following:

```console 
kubectl get BareMetalHosts -n metal3 -w
```
> The `BareMetalHosts` resource is created when `Metal³/metal3-dev-env` was deployed. It is a kubernetes resource that represents a bare metal Machine, with all its details and configuration, and is managed by the `Bare Metal Operator`. You can also use the short representation instead, i.e. `bmh` ( short for `BareMetalHosts`) in the command above.

> You should see all the nodes that were created at the time of metal3 deployment, along with their current status as the provisioning progresses
> info "Note"
> All the bare metal hosts listed above were created when Metal³ was deployed in the *detailed metal3-dev-env walkthrough blogpost*.


```console
kubectl get Machine -n metal3 -w
```
> This shows the status of Machine associated with control plane and we can watch the status of provisioning under PHASE 

<br/>
Once the provisioning is finished, let's get the host-ip : 

```console
sudo virsh net-dhcp-leases baremetal
```
> info "Note"
> `baremetal` is one of the 2 networks that were created at the time of Metal3 deployment, the other being “provisioning” which is used - as you have guessed - for provisioning the bare metal cluster. More details about networking setup in the metal3-dev-env environment are described in the - [detailed metal3-dev-env walkthrough blogpost]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %}).

<br/>
You can login to the control plane node if you want, and can check the deployment status using two methods.

```console
ssh metal3@{control-plane-node-ip}
ssh metal3@192.168.111.249
```
<br/>
<br/>


### Provision Workers

The script is located at `${metal3-dev-env-path}/scripts/v1alphaX/provision_worker.sh` and it provisions a node to be added as a worker to the bare metal cluster. It selects one of the remaining nodes and provisions it and adds it to the bare metal cluster ( which only has a control plane node at this point ). The resources created for workers are - `MachineDeployment` which can be scaled up to add more workers to the cluster and `MachineSet` which then creates a `Machine` managing the node.

> info "Note"
> Similar to a control plane provisioning, a worker provisioning also takes some time, and you can watch the process using steps shared a bit later. This will also apply when you scale Up/Down workers at a later point in time.

<br/>
This is what a `MachineDeployment` looks like

```console
kubectl describe MachineDeployment ${CLUSTER_NAME} -n metal3
```

```yaml
apiVersion: cluster.x-k8s.io/v1alpha3
kind: MachineDeployment
metadata:
  [....]
  ownerReferences:
  - apiVersion: cluster.x-k8s.io/v1alpha3
    kind: Cluster
    name: bmetalcluster
    uid: aec0f73b-a068-4992-840d-6330bf943d22
  resourceVersion: "66257"
  selfLink: /apis/cluster.x-k8s.io/v1alpha3/namespaces/metal3/machinedeployments/bmetalcluster
  uid: f598da43-0afe-44e4-b793-cd5244c13f4e
spec:
  clusterName: bmetalcluster
  minReadySeconds: 0
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 1
  selector:
    matchLabels:
      cluster.x-k8s.io/cluster-name: bmetalcluster
      nodepool: nodepool-0
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
    type: RollingUpdate
  template:
    metadata:
      labels:
        cluster.x-k8s.io/cluster-name: bmetalcluster
        nodepool: nodepool-0
    spec:
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1alpha3
          kind: KubeadmConfigTemplate
          name: bmetalcluster-workers
      clusterName: bmetalcluster
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
        kind: Metal3MachineTemplate
        name: bmetalcluster-workers
      version: v1.18.0
status:
  observedGeneration: 1
  phase: ScalingUp
  replicas: 1
  selector: cluster.x-k8s.io/cluster-name=bmetalcluster,nodepool=nodepool-0
  unavailableReplicas: 1
  updatedReplicas: 1
```

<br/>
To check the status we can follow steps similar to Controlplane case :

```console
kubectl get bmh -n metal3 -w
```
> We can see the live status of the node being provisioned. As mentioned before `bmh` is short representation for `BareMetalHosts`.

```console
kubectl get Machine -n metal3 -w
```
> This shows the status of Machines associated with workers, apart from the one for Controlplane, and we can watch the status of provisioning under PHASE 

```console
sudo virsh net-dhcp-leases baremetal
```
> To get the nodes IP

```console
ssh metal3@{control-plane-node-ip}
kubectl get nodes
```
> To check if its added to the cluster

```console
ssh metal3@{node-ip}
```   
> If you want to login to the node

```console
kubectl scale --replicas=3 MachineDeployment ${CLUSTER_NAME} -n metal3
```
> We can add or remove workers to the cluster, we can scale up the MachineDeployment up or down, in this example we are adding 2 more worker nodes, making the total nodes = 3

<br/>
<br/>

### Deprovisioning

All of the previous components have corresponding deprovisioning scripts which use config files, in the previously mentioned manifest directory, and use them to clean up worker, control plane and cluster.

This step will use the already generated cluster/control plane/worker definition file, and supply it to **Kubernetes** ansible module to remove/deprovision the resource. You can find it, under the `Manifest` directory, in the Snapshot shared at the beginning of this blogpost where we show the file structure.

For example if you wish to deprovision the cluster, you would do :

```console
sh ${metal3-dev-env-path}/scripts/v1alphaX/deprovision_worker.sh
sh ${metal3-dev-env-path}/scripts/v1alphaX/deprovision_controlplane.sh
sh ${metal3-dev-env-path}/scripts/v1alphaX/deprovision_cluster.sh
```
> Note :
> The reason for running the `deprovision_worker.sh` and `deprovision_controlplane.sh` scripts is that not all objects are cleared when we just run the `deprovision_cluster.sh` script. Following this, if you want to deprovision control plane it is recommended to deprovision the cluster itself since we can't provision a new control plane with the same cluster. For worker deprovisioning, we only need to run the worker script.


## Summary

In this blogpost we saw how to deploy a bare metal cluster once we have a Metal³(metal3-dev-env repo) deployed and by that point we will already have the nodes ready to be used for a bare metal cluster deployment. 

In the first section we show the various configuration files, templates, resource types and their meanings.Then we see the common steps involved in the provisioning process. After that we see a general overview of how all resources are related and at what point are they created - provision cluster/control plane/worker. 

In each of the provisioning sections we see the steps to monitor the provisioning and how to confirm if its successful or not, with brief explanations wherever required. Finally we see the deprovisioning section which uses the resource definitions generated at the time of provisioning to deprovision  cluster, control plane or worker.

Here are a few resources which you might find useful if you want to explore further, some of them have already been shared earlier.

 - [Metal3-Documentation](https://metal3.io/)
   - [Metal3-Try-it](https://metal3.io/try-it.html)
 - [Metal³/metal3-dev-env](https://github.com/metal3-io/metal3-dev-env)
 - [Detailed metal3-dev-env walkthrough blogpost]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %})
 - [Kubernetes Metal3 Talk]({%post_url 2020-02-27-talk-kubernetes-finland-metal3 %})
 - [Metal3-Docs-github](https://github.com/metal3-io/metal3-docs)