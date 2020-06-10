---
title: "Metal³ development environment walkthrough part 2: Deploying a new baremetal cluster"
draft: false
categories: ["metal3", "kubernetes", "cluster API", "metal3-dev-env"]
author: Himanshu Roy
---

## Introduction

This blog post describes how to deploy a bare metal cluster, a virtual one for simplicity, using [Metal³/metal3-dev-env](https://github.com/metal3-io/metal3-dev-env). We will briefly discuss the steps involved in setting up the cluster as well as some of the customization available. If you want to know more about the architecture of Metal³, this [blogpost]({%post_url 2020-02-27-talk-kubernetes-finland-metal3 %}) can be helpful.

This post builds upon the [detailed metal3-dev-env walkthrough blogpost]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %}) which describes in detail the steps involved in the environment set up and management cluster configuration. Here we will use that environment to deploy a new Kubernetes cluster using Metal³.

Before we get started, there are a couple of requirements we are expecting to be fulfilled.

<br/>

## Requirements

- Metal³ is already deployed and working,  if not please follow the instructions in the previously mentioned [detailed metal3-dev-env walkthrough blogpost]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %}).
- The appropriate environment variables are setup via shell or in the `config_${user}.sh` file, for example -
  - CAPI_VERSION
  - NUM_NODES
  - CLUSTER_NAME

<br/>


## Overview of Config and Resource types
In this section we give a brief overview of the important config files and resources used as part of the BAREMETAL-Cluster deployment. The following sub-sections shows where and which config files, resources are created and give a brief description about some of them. These will help you understand the technical details of the cluster deployment. You can also skip this section, visit the next section about *provisioning* first and then revisit this 


### Config Files and Resources Types

!["A list of files under manifests directory for CLUSTER_NAME=bmetalcluster"](/assets/2020-06-18-Metal3-dev-env-BareMetal-Cluster-Deployment/manifest-directory.png)  
> info "Note"
> All these files are generated under the path `https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/files` as part of the provisioning process. When you do a provisioning for the first time, this directory is created and is subsequently used to store the templates and config files generated for deploying the baremetal cluster.

<br/>

Some of the configuration files generated as part of provisioning a cluster, in a centos based environment, are :

| Name           | Description                                       | Path                          |
| ------------------- | ---------------------------------------------| ----------------------------- |
| clusterctl env file   | Cluster parameters and details  | `${Manifests}/clusterctl_env_centos.rc` |
| manifest file    | Generated using clusterctl-tool, contains list of resources  | `${Manifests}/manifests.yaml`  |
| **base** directory | directory for [`kustomization`](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) resource files, templates of resources created while provisioning               | `${Manifests}/base` |
| [kustomization](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) file | copied from templates for kustomization in [templates-directory](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/templates)               | `${Maifests}/kustomization.yaml` |

<br/>

> Note : the `base` directory has templates for the resources that are created while provisioning
>  - [`kustomize-tool`](https://github.com/kubernetes-sigs/kustomize) is used to build manifests in the base directory
>  - Cluster, Controlplane and MachineDeployment manifests are generated in `base` directory
>  - worker manifests are generated and added using kustomize-tool
>  - All the resources created as part of provisioning have their templates under the ‘base’ directory 

<br/>


Here are some of the resources that are created as part of provisioning :

| Name                | Description                                       |
| ------------------- | ------------------------------------------------- | 
| Cluster | Cluster API resource for managing a cluster |
| Metal3Cluster | Corresponding Metal3 resource generated as part of BareMetalCluster deployment, and managed by `Cluster`|
| KubeadmControlPlane | Cluster API resource for managing the Controlplane, it also manages the `Machine` object for Controlplane, and has the **KubeadmConfig** for the Controlplane |
| MachineDeployment | Cluster API resource for managing workers via `MachineSet` object, it can be used to add/remove workers by scaling Up/Down |
| MachineSet | Cluster API resource for managing `Machine` objects for worker nodes |
| Machine | Cluster API resource for managing nodes - Controlplane or Workers. In case of Controlplane, its directly managed by `KubeadmControlPlane`, whereas for Workers it's managed by a `MachineSet`|
| Metal3Machine | Corresponding Metal3 resource for managing Baremetal Nodes, it's managed by a `Machine` resource |
| Metal3MachineTemplate | Metal3 resource which acts as a template when creating a Controlplane or a Worker node |
| KubeadmConfigTemplate | A template of `KubeadmConfig`, for Workers, used to generate KubeadmConfig when a new worker node is provisioned |

> **Note** : The corresponding `KubeadmConfig` is copied to the Controlplane/Worker at the time of provisioning.  
  
<br/>


## BareMetal Cluster Deployment

The deployment scripts primarily use ansible and the existing Kubernetes management cluster (based on minikube ) for deploying the bare-metal cluster. Make sure that some of the environment variables used for Metal³ deployment are set, if you didn't use `config_${user}.sh` for setting the environment varilables.

| Parameter           | Description                  | Default                  |
| ------------------- | ---------------------------- | ------------------------ |
| CAPI_VERSION        | Version of Metal3 API4       | v1alpha3        |
| POD_CIDR            | Pod Network CIDR             | 192.168.0.0/18           |
| CLUSTER_NAME        | Name of bare metal cluster   | test1                    |

<br/>


### Steps Involved

All the scripts for cluster provisioning or deprovisioning are located at - [`${metal3-dev-env}/scripts/v1alphaX/`](https://github.com/metal3-io/metal3-dev-env/tree/master/scripts/v1alphaX). The scripts call a common playbook which handles all the tasks that are available.

> info "Note"
> Here is a depiction of the common steps, mainly involving generating templates and config files. 

<br/>

!["A diagram depicting the Generate Templates workflow"](/assets/2020-06-18-Metal3-dev-env-BareMetal-Cluster-Deployment/metal3-generate-templates.png)
<br/>
<br/>

The steps involved in the process are :

- The script calls an ansible playbook with necessary parameter ( from env variables and defaults )
- The playbook executes the role -, [`${metal3-dev-env}/vm-setup/roles/v1aX_integration_test`](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test), which runs the corresponding [task_file](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/tasks) for provisioning/deprovisioning the cluster/controlplane or a worker
- There are [templates](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test/templates) in the role, which are copied to the `manifest` directory. They are used for generating configuration for the cluster and kubeadm, which is then supplied to the Kubernetes module of ansible to create the cluster.
- During provisioning, first the `clusterctl` env file is generated, then and `manifest` file is created/updated using the `clusterctl` tool, which is then supplied to `kustomize` tool to create the config files for provisioning the resource, from the available templates.
- The manifests are generated for - cluster, controlplane and machinedeployment, and the worker manifests are merged with the deployment manifests.
- Finally a yaml file is generated with all the details for the cluster/controlplane/worker, which is then passed to K8s module in ansible which creates the resources.
- There are also manifests stored in ${Manifests} directory - [`${metal3-dev-env}/vm-setup/roles/v1aX_integration_test/files/manifests`](https://github.com/metal3-io/metal3-dev-env/tree/master/vm-setup/roles/v1aX_integration_test), for the cluster which can be used to deprovision the cluster at a later point in time.
> **Note** : * the `manifests` directory is not present but created when you first use the scripts.*
- Centos or Ubuntu images [are downloaded](https://github.com/metal3-io/metal3-dev-env/blob/master/vm-setup/roles/v1aX_integration_test/tasks/download_image.yml) when provisioning a controlplane or a worker  

<br/>
<br/>





!["An Overview of various resources generated while provisioning and their relationship amongst themselves"](/assets/2020-06-18-Metal3-dev-env-BareMetal-Cluster-Deployment/metal3-bmetal-arch-overview.png)  
<br/>
<br/>


### Provision Cluster
This script, located at the path - `${metal3-dev-env}/scripts/v1alphaX/provision_clusters.sh`, provisions the cluster by creating a `Metal3Cluster` resource. 

<br/>
To see if you have a successful Cluster resource creation( the cluster still doesn't have a Controlplane or Workers ), just do :

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

This script, located at the path - `${metal3-dev-env}/scripts/v1alphaX/provision_clusters.sh`, provisions the controlplane or the master of the cluster. As part of the controlplane provisioning, the generated manifests are for cluster, controlplane and machinedeployment. The `MachineDeployment` creates a `Machine` which picks up a BareMetalHost satisfying its requirements as the controlplane node, and it is then provisioned by the BareMetalOperator. there are other resources created in the process of provisioning, like `KubeadmControlPlane` and `Metal3MachineTemplate` resource which are involved in the provisioning process.

> info "Note"
> It takes some time for the provisioning of the Controlplane, you can watch the process using some steps shared a bit later

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
> The `BareMetalHosts` resource is created when `Metal³/metal3-dev-env` was deployed. It is a kubernetes resource that represents a Baremetal Machine, with all its details and configuration, and is managed by the `BareMetalOperator`. You can also use the short representation instead, i.e. `bmh` ( short for `BareMetalHosts`) in the command above.

> You should see all the nodes that were created at the time of metal3 deployment, along with their current status as the provisioning progresses
> info "Note"
> All the baremetal hosts listed above were created when Metal³ was deployed in the *detailed metal3-dev-env walkthrough blogpost*.


```console
kubectl get Machine -n metal3 -w
```
> This shows the status of Machine associated with controlplane and we can watch the status of provisioning under PHASE 

<br/>
Once the provisioning is finished, let's get the host-ip : 

```console
sudo virsh net-dhcp-leases baremetal
```
> info "Note"
> *baremetal is one of the 2 networks that were created at the time of Metal3 deployment, the other being “provisioning” which is used - as you have guessed - for provisioning the bare metal cluster. More details about networking setup in the metal3-dev-env environment are described in the - detailed metal3-dev-env walkthrough blogpost.*

<br/>
You can login to the master node if you want, and can check the deployment status

```console
ssh metal3@{master-node-ip}
```
<br/>
<br/>


### Provision Workers

The script is located at `${metal3-dev-env-path}/scripts/v1alphaX/provision_worker.sh` and it provisions a node to be added as a worker to the baremetal cluster. It selects one of the remaining nodes and provisions it and adds it to the baremetal cluster ( which only has a master at this point ). The resources created for workers are - `MachineDeployment` which can be scaled up to add more workers to the cluster, and it also created a `MachineSet` which then creates a `Machine` managing the node.

> info "Note"
> Similar to a Controlplane provisioning, a Worker provisioning also takes some time, and you can watch the process using steps shared a bit later. This will also apply when you scale Up/Down workers at a later point in time.

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
ssh metal3@{master-node-ip}
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

All of the previous components have corresponding deprovisioning scripts which use config files, in the previously mentioned manifest directory, and use them to clean up worker, controlplane and cluster.
For example if you wish to deprovision the cluster, you would do :

```console
sh ${metal3-dev-env-path}/scripts/v1alphaX/deprovision_cluster.sh
```
> This will use the already generated cluster definition file, generated when the cluster was provisioned, and supply it to **Kubernetes** ansible module to remove/deprovision the cluster. The cluster definition file according to the parameters in above examples, will be - `${Manifests}/v1alpha3_cluster_bmetalcluster_centos.yaml`. You can find it in the Snapshot shared at the beginning of this blogpost where we show a directory structure.


## Summary

In this blogpost we saw how to deploy a baremetal cluster once we have a Metal³(metal3-dev-env repo) deployed and by that point we will already have the nodes ready to be used for a baremetal cluster deployment. In the first section we show the various configuration files, templates, resource types and their meanings. Then we see the workflow of an important component of provisioning - generating templates. After that we see a general overview of how all resources are related and at what point are they created - provision_cluster/controlplane/worker. In each of the provisioning sections we see the steps to monitor the provisioning and how to confirm if its successful or not, with brief explanations wherever required. Finally we see the deprovisioning section which uses the resource definitions generated at the time of provisioning to deprovision  cluster, controlplane or worker.

Here are a few resources which you might find useful if you want to explore further, some of them have already been shared earlier.

 - [Metal3-Documentation](https://metal3.io/)
   - [Metal3-Try-it](https://metal3.io/try-it.html)
 - [Metal³/metal3-dev-env](https://github.com/metal3-io/metal3-dev-env)
 - [Detailed metal3-dev-env walkthrough blogpost]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %})
 - [Kubernetes Metal3 Talk]({%post_url 2020-02-27-talk-kubernetes-finland-metal3 %})
 - [Metal3-Docs-github](https://github.com/metal3-io/metal3-docs)