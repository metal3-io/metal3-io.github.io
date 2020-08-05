---
layout: tryit
title: "Try it: Getting started with Metal3.io"
permalink: /try-it.html
---

<!-- TOC depthFrom:2 insertAnchor:false orderedList:false updateOnSave:true withLinks:true -->

- [1. Instructions](#1-instructions)
    - [1.1. Prerequisites](#11-prerequisites)
    - [1.2. Metal3-dev-env setup](#12-metal3-dev-env-setup)
    - [1.3. Using a custom image](#13-using-a-custom-image)
- [2. Working with the Environment](#2-working-with-the-environment)
    - [2.1. Bare Metal Hosts](#21-bare-metal-hosts)
    - [2.2. Provisioning Cluster and Machines](#22-provisioning-cluster-and-machines)
    - [2.3. Deprovisioning Cluster and Machines](#23-deprovisioning-cluster-and-machines)
    - [2.4. Centos target hosts only, image configuration](#24-centos-target-hosts-only-image-configuration)
    - [2.5. Directly Provisioning Bare Metal Hosts](#25-directly-provisioning-bare-metal-hosts)
    - [2.6. Running Custom Baremetal-Operator](#26-running-custom-baremetal-operator)
    - [2.7. Running Custom Cluster API Provider Metal3](#27-running-custom-cluster-api-provider-metal3)
    - [2.8. Accessing Ironic API](#28-accessing-ironic-api)

<!-- /TOC -->
<hr>
## 1. Instructions

> info "Naming"
> For the v1alpha3 release, the Cluster API provider for metal3 was renamed from
> Cluster API provider BareMetal to Cluster API provider Metal3. Hence, if
> working with v1alpha1 or v1alpha2, it will be Cluster API provider Baremetal
> (CAPBM) in this documentation and deployments, but from v1alpha3 onwards it
> will be Cluster API provider Metal3 (CAPM3).

### 1.1. Prerequisites

- System with CentOS 8 or Ubuntu 18.04
- Bare metal preferred, as we will be creating VMs to emulate bare metal hosts
- Run as a user with passwordless sudo access
- Minimum resource requirements for the host machine: 4C CPUs, 16 GB RAM memory.

> warning "Warning"
> The system can be running CentOS 7. However, note that there is an ongoing process to move to latest CentOS version. Therefore, in order to avoid future issues you might find, CentOS 8 is the preferred CentOS choice.

### 1.2. Metal3-dev-env setup

> info "Information"
> If you need detailed information regarding the process of creating a Metal³ emulated environment using metal3-dev-env, it is worth taking a look at the blog post ["A detailed walkthrough of the Metal³ development environment"]({% post_url 2020-02-18-metal3-dev-env-install-deep-dive %}).

This is a high-level architecture of the metal³-dev-env.

![](assets/images/metal3-dev-env.svg)

tl;dr - Clone [metal³-dev-env](https://github.com/metal3-io/metal3-dev-env)
and run

```sh
$ make
```

The `Makefile` runs a series of scripts, described here:

- `01_prepare_host.sh` - Installs all needed packages.

- `02_configure_host.sh` - Creates a set of VMs that will be managed as if they
  were bare metal hosts. It also downloads some images needed for Ironic.

- `03_launch_mgmt_cluster.sh` - Launches a management cluster using `minikube`
and runs the `baremetal-operator` on that cluster.

- `04_verify.sh` - Runs a set of tests that verify that the deployment completed
  successfully

To tear down the environment, run

```sh
$ make clean
```

> info "Note"
> you can also run some tests for provisioning and deprovisioning machines by
> running:
>
> ```sh
> $ make test
> ```

The vast majority of configurations for the environment are stored in `config_${user}.sh`. You
can configure the following

| Name                           | Option                                                                                                                                                                                                                                                   | Allowed values                       | Default                                                      |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------ |
| EPHEMERAL_CLUSTER              | Tool for running management/ephemeral cluster.  | minikube, kind   | Ubuntu default is kind, while CentOS is minikube. |
| EXTERNAL_SUBNET                | This is the subnet used on the "baremetal" libvirt network, created as the primary network interface for the virtual bare metalhosts.                                                                                                                    | <CIDR>                               | 192.168.111.0/24                                             |
| SSH_PUB_KEY                    | This SSH key will be automatically injected into the provisioned host by the provision_host.sh script.                                                                                                                                                   | <file path>                          | ~/.ssh/id_rsa.pub                                            |
| CONTAINER_RUNTIME              | Select the Container Runtime                                                                                                                                                                                                                             | "docker", "podman"                   | "podman"                                                     |
| BMOREPO                        | Set the Baremetal Operator repository to clone                                                                                                                                                                                                           | <URL>                                | https://github.com/metal3-io/baremetal-operator.git          |
| BMOBRANCH                      | Set the Baremetal Operator branch to checkout                                                                                                                                                                                                            |                                      | master                                                       |
| CAPM3REPO                      | Set the Cluster Api Metal3 provider repository to clone                                                                                                                                                                                                  | <URL>                                | https://github.com/metal3-io/cluster-api-provider-metal3.git |
| CAPM3BRANCH                    | Set the Cluster Api Metal3 provider branch to checkout                                                                                                                                                                                                   |                                      | master                                                       |
| FORCE_REPO_UPDATE              | Force deletion of the BMO and CAPM3 repositories before cloning them again                                                                                                                                                                               | "true", "false"                      | "false"                                                      |
| BMO_RUN_LOCAL                  | Run a local baremetal operator instead of deploying in Kubernetes                                                                                                                                                                                        | "true", "false"                      | "false"                                                      |
| CAPM3_RUN_LOCAL                | Run a local CAPI operator instead of deploying in Kubernetes                                                                                                                                                                                             | "true", "false"                      | "false"                                                      |
| SKIP_RETRIES                   | Do not retry on failure during verifications or tests of the environment. This should be false. It could only be set to false for verifications of a dev env deployment that fully completed. Otherwise failures will appear as resources are not ready. | "true", "false"                      | "false"                                                      |
| TEST_TIME_INTERVAL             | Interval between retries after verification or test failure (seconds)                                                                                                                                                                                    | <int>                                | 10                                                           |
| TEST_MAX_TIME                  | Number of maximum verification or test retries                                                                                                                                                                                                           | <int>                                | 120                                                          |
| BMC_DRIVER                     | Set the BMC driver                                                                                                                                                                                                                                       | "ipmi", "redfish"                    | "ipmi"                                                       |
| IMAGE_OS                       | OS of the image to boot the nodes from, overriden by IMAGE\_\* if set                                                                                                                                                                                    | "Centos", "Cirros", "FCOS", "Ubuntu" | "Centos"                                                     |
| IMAGE_NAME                     | Image for target hosts deployment                                                                                                                                                                                                                        |                                      | "CentOS-8-GenericCloud-8.1.1911-20200113.3.x86_64.qcow2"                    |
| IMAGE_LOCATION                 | Location of the image to download                                                                                                                                                                                                                        | <URL>                                | https://cloud.centos.org/centos/8/x86_64/images/                     |
| IMAGE_USERNAME                 | Image username for ssh                                                                                                                                                                                                                                   |                                      | "metal3"                                                     |
| IRONIC_IMAGE                   | Container image for local ironic services                                                                                                                                                                                                                |                                      | "quay.io/metal3-io/ironic"                                   |
| VBMC_IMAGE                     | Container image for vbmc container                                                                                                                                                                                                                       |                                      | "quay.io/metal3-io/vbmc"                                     |
| SUSHY_TOOLS_IMAGE              | Container image for sushy-tools container                                                                                                                                                                                                                |                                      | "quay.io/metal3-io/sushy-tools"                              |
| CAPM3_VERSION                   | Version of Cluster API provider Metal3                                                                                                                                                                                                                                   | "v1alpha3", "v1alpha4"   | "v1alpha3"                                                   |
| CLUSTER_APIENDPOINT_IP         | API endpoint IP for target cluster                                                                                                                                                                                                                        | "x.x.x.x/x"                          | "192.168.111.249"                                            |
| CLUSTER_PROVISIONING_INTERFACE | Cluster provisioning Interface                                                                                                                                                                                                                           | "ironicendpoint"                     | "ironicendpoint"                                             |
| POD_CIDR                       | Pod CIDR                                                                                                                                                                                                                                                 | "x.x.x.x/x"                          | "192.168.0.0/18"                                             |
| KUBERNETES_VERSION                       | Kubernetes version                                                                                                                                                                                                                                                 | "x.x.x"                          | "1.18.0"                                             |
| KUBERNETES_BINARIES_VERSION                       | Version of kubelet, kubeadm and kubectl                                                                                                                                                                                                                                                 | "x.x.x-xx" or "x.x.x"                          | same as KUBERNETES_VERSION                                             |
| KUBERNETES_BINARIES_CONFIG_VERSION                       | Version of kubelet.service and 10-kubeadm.conf files                                                                                                                                                                                                                                                 | "vx.x.x"                          | "v0.2.7"                                             |

<br>

There also other variables that are used throughout the metal3-dev-env environment configuration in scripts or Ansible playbooks. Below, are listed some of the variables that might be adapted to your requirements.

> note "Note"
> It is recommended modifying or adding variables in `config_${user}.sh` config file instead of exporting them in the shell. By doing that, it is assured that they are persisted.


| Name                           | Option                                                                                                                                                                                                                                                   | Allowed values                       | Default                                                      |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------ |
| NUM_NODES                | Set the number of virtual machines to be provisioned. This VMs will be further configured as control-plane or worker Nodes      |   | 2 |
| VM_EXTRADISKS            | Add extra disks to the virtual machines provisioned. By default the size of the extra disk is set in the libvirt Ansible role to 8 GB        | "true", "false" | "false" |
| DEFAULT_HOSTS_MEMORY     | Set the default memory size in MB for the virtual machines provisioned.        |  | 4096 |
| CLUSTER_NAME             | Set the name of the target cluster                        |  | test1 |

> note "Note"
> The IMAGE_USERNAME for ssh has been changed to `metal3` for both Centos and Ubuntu images.
<br>

### 1.3. Using a custom image

Whether you want to run target cluster Nodes with your own image, you can override the three following variables: `IMAGE_NAME`,
`IMAGE_LOCATION`, `IMAGE_USERNAME`. If the requested image with name `IMAGE_NAME` does not
exist in the `IRONIC_IMAGE_DIR` (/opt/metal3-dev-env/ironic/html/images) folder, then it will be automatically
downloaded from the `IMAGE_LOCATION` value configured.

> warning "Warning"
> If you see this error during the installation:
>
> ```sh
> error: failed to connect to the hypervisor
> error: Failed to connect socket to '/var/run/libvirt/libvirt-sock':  Permission denied
> ```
>
> You may need to log out then login again, and run `make clean` and `make` again.

## 2. Working with the Environment

### 2.1. Bare Metal Hosts

This environment creates a set of VMs to manage as if they were bare metal
hosts. You can see the VMs using `virsh`.

```sh
$ sudo virsh list
 Id    Name                           State
----------------------------------------------------
 6     minikube                       running
 9     node_0                         running
 10    node_1                         running
```

Each of the VMs (aside from the `minikube` management cluster VM) are
represented by `BareMetalHost` objects in our management cluster. The yaml
used to create these host objects is in `bmhosts_crs.yaml`.

```sh
$ kubectl get baremetalhosts -n metal3
NAME     STATUS   PROVISIONING STATUS   CONSUMER   BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0   OK       ready                            ipmi://192.168.111.1:6230   unknown            true
node-1   OK       ready                            ipmi://192.168.111.1:6231   unknown            true
```

You can also look at the details of a host, including the hardware information
gathered by doing pre-deployment introspection.

```sh
$ kubectl get baremetalhost -n metal3 -o yaml node-0
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"metal3.io/v1alpha1","kind":"BareMetalHost","metadata":{"annotations":{},"name":"node-0","namespace":"metal3"},"spec":{"bmc":{"address":"ipmi://192.168.111.1:6230","credentialsName":"node-0-bmc-secret"},"bootMACAddress":"00:f8:16:dd:3b:9b","online":true}}
  creationTimestamp: "2020-02-05T09:09:44Z"
  finalizers:
  - baremetalhost.metal3.io
  generation: 1
  name: node-0
  namespace: metal3
  resourceVersion: "16312"
  selfLink: /apis/metal3.io/v1alpha1/namespaces/metal3/baremetalhosts/node-0
  uid: 99f4c905-b850-45e0-bf1b-61b12f91182b
spec:
  bmc:
    address: ipmi://192.168.111.1:6230
    credentialsName: node-0-bmc-secret
  bootMACAddress: 00:f8:16:dd:3b:9b
  online: true
status:
  errorMessage: ""
  goodCredentials:
    credentials:
      name: node-0-bmc-secret
      namespace: metal3
    credentialsVersion: "1242"
  hardware:
    cpu:
      arch: x86_64
      clockMegahertz: 2399.998
      count: 4
      model: Intel Xeon E3-12xx v2 (Ivy Bridge)
    firmware:
      bios:
        date: 04/01/2014
        vendor: SeaBIOS
        version: 1.10.2-1ubuntu1
    hostname: node-0
    nics:
    - ip: 192.168.111.20
      mac: 00:f8:16:dd:3b:9d
      model: 0x1af4 0x0001
      name: eth1
      pxe: false
      speedGbps: 0
      vlanId: 0
    - ip: 172.22.0.47
      mac: 00:f8:16:dd:3b:9b
      model: 0x1af4 0x0001
      name: eth0
      pxe: true
      speedGbps: 0
      vlanId: 0
    ramMebibytes: 8192
    storage:
    - hctl: "0:0:0:0"
      model: QEMU HARDDISK
      name: /dev/sda
      rotational: true
      serialNumber: drivMetal3-dev-env setupe-scsi0-0-0-0
      sizeBytes: 53687091200
      vendor: QEMU
    systemVendor:
      manufacturer: QEMU
      productName: Standard PC (Q35 + ICH9, 2009)
      serialNumber: ""
  hardwareProfile: unknown
  lastUpdated: "2020-02-05T10:10:49Z"
  operationHistory:
    deprovision:
      end: null
      start: null
    inspect:
      end: "2020-02-05T09:15:08Z"
      start: "2020-02-05T09:11:33Z"
    provision:
      end: null
      start: null
    register:
      end: "2020-02-05T09:11:33Z"
      start: "2020-02-05T09:10:32Z"
  operationalStatus: OK
  poweredOn: true
  provisioning:
    ID: b605df1d-7674-44ad-9810-20ad3e3c558b
    image:
      checksum: ""
      url: ""
    state: ready
  triedCredentials:
    credentials:
      name: node-0-bmc-secret
      namespace: metal3
    credentialsVersion: "1242"
```

### 2.2. Provisioning Cluster and Machines

This section describes how to trigger provisioning of a cluster and hosts via
`Machine` objects as part of the Cluster API integration. This uses Cluster API
[v1alpha3](https://github.com/kubernetes-sigs/cluster-api/tree/v0.3.0) and
assumes that metal3-dev-env is deployed with the environment variable
**CAPM3_VERSION** set to **v1alpha3**. The v1alpha3 deployment can be done with
Ubuntu 18.04 or Centos 8 target host images. Please make sure to meet [resource requirements](#11-prerequisites) for successfull deployment:

```sh
$ ./scripts/provision/cluster.sh
$ ./scripts/provision/controlplane.sh
$ ./scripts/provision/worker.sh
```

At this point, the `Machine` actuator will respond and try to claim a
`BareMetalHost` for this `Machine`. You can check the logs of the actuator
here:

```sh
$ kubectl logs -n capm3 pod/capm3-manager-7bbc6897c7-bp2pw -c manager

09:10:38.914458       controller-runtime/controller "msg"="Starting Controller"  "controller"="metal3cluster"
09:10:38.926489       controller-runtime/controller "msg"="Starting workers"  "controller"="metal3machine" "worker count"=1
10:54:16.943712       Host matched hostSelector for Metal3Machine
10:54:16.943772       2 hosts available while choosing host for bare metal machine
10:54:16.944087       Associating machine with host
10:54:17.516274       Finished creating machine
10:54:17.518718       Provisioning BaremetalHost

```

If you look at the yaml representation of the `Machine`, you will see a new
annotation that identifies which `BareMetalHost` was chosen to satisfy this
`Machine` request.

```sh
$ kubectl get machine centos -n metal3 -o yaml

...
  annotations:
    metal3.io/BareMetalHost: metal3/node-1
...
```

You can also see in the list of `BareMetalHosts` that one of the hosts is now
provisioned and associated with a `Machine`.

```sh
$ kubectl get baremetalhosts -n metal3

NAME     STATUS   PROVISIONING STATUS   CONSUMER               BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0   OK       provisioning          test1-md-0-m87bq       ipmi://192.168.111.1:6230   unknown            true
node-1   OK       provisioning          test1-controlplane-0   ipmi://192.168.111.1:6231   unknown            true
```

You should be able to ssh into your host once provisioning is complete. See
the libvirt DHCP leases to find the IP address for the host that was
provisioned. In this case, it’s `node-1`.

```sh
$ sudo virsh net-dhcp-leases baremetal

Expiry Time          MAC address        Protocol  IP address                Hostname        Client ID or DUID
-------------------------------------------------------------------------------------------------------------------
2020-02-05 11:52:39  00:f8:16:dd:3b:9d  ipv4      192.168.111.20/24         node-0          -
2020-02-05 11:59:18  00:f8:16:dd:3b:a1  ipv4      192.168.111.21/24         node-1          -
```

The default username for the CentOS image is `metal3`.

```sh
$ ssh metal3@192.168.111.21
```

### 2.3. Deprovisioning Cluster and Machines

Deprovisioning of the target cluster is done just by deleting `Cluster` and `Machine` objects or by executing the deprovisioning scripts in reverse order than provisioning:

```sh
$ ./scripts/v1alphaX/deprovision_worker.sh
$ ./scripts/v1alphaX/deprovision_controlplane.sh
$ ./scripts/v1alphaX/deprovision_cluster.sh
```

Note that you can easily deprovision _worker_ Nodes by decreasing the number of replicas in the `MachineDeployment` object created when executing the `provision_worker.sh` script:

```sh
$ kubectl scale machinedeployment test1-md-0 --replicas=0
```

> warning "Warning"
> control-plane and cluster are very tied together. This means that you are not able to deprovision the control-plane of a cluster and then provision a new one within the same cluster. Therefore, in case you want to deprovision the control-plane you need to **deprovision the cluster** as well and provision both again.

Below, it is shown how the deprovisioning can be executed in a more manual way by just deleting the proper Custom Resources (CR)


```sh
$ kubectl delete machine test1-md-0-m87bq -n metal3
machine.cluster.x-k8s.io "test1-md-0-m87bq" deleted

$ kubectl delete machine test1-controlplane-0 -n metal3
machine.cluster.x-k8s.io "test1-controlplane-0" deleted

$ kubectl delete cluster test1 -n metal3
cluster.cluster.x-k8s.io "test1" deleted
```

Once the deprovisioning is started, you can see that the `BareMetalHost` and `Cluster` are going
through a deprovisioning process too.

```sh
$ kubectl get baremetalhosts -n metal3
NAME     STATUS   PROVISIONING STATUS   CONSUMER               BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0   OK       deprovisioning        test1-md-0-m87bq       ipmi://192.168.111.1:6230   unknown            false
node-1   OK       deprovisioning        test1-controlplane-0   ipmi://192.168.111.1:6231   unknown            false

$ kubectl get cluster -n metal3
NAME    PHASE
test1   deprovisioning
```

### 2.4. Centos target hosts only, image configuration

If you want to deploy Ubuntu hosts, please skip this section.

As shown in the [prerequisites](#11-prerequisites) section, the preferred OS image for CentOS is version 8. Actually, for both the system where the metal3-dev-env environment is configured and the target cluster nodes.

> warning "Warning"
> There is an ongoing effort to move from CentOS 7 to CentOS 8, this means that in a near future CentOS 7 will not be supported or at least tested. Therefore, we suggest moving to CentOS 8 if possible.

Wheter you still want to deploy Centos 7 for the target hosts, the following variables needs to be modified:


```
IMAGE_NAME_CENTOS="centos-updated.qcow2"
IMAGE_LOCATION_CENTOS="http://artifactory.nordix.org/artifactory/airship/images/centos.qcow2"
IMAGE_OS=Centos
```

Additionally, you can let the Ansible `provision_controlplane.sh` and `provision_worker.sh` download the image automatically following the variables listed above or download the properly configured CentOS 7 image from the following location into the `IRONIC_IMAGE_DIR`:

```sh
curl -LO http://artifactory.nordix.org/artifactory/airship/images/centos.qcow2
mv centos.qcow2 /opt/metal3-dev-env/ironic/html/images/centos-updated.qcow2
md5sum /opt/metal3-dev-env/ironic/html/images/centos-updated.qcow2 | \
awk '{print $1}' > \
/opt/metal3-dev-env/ironic/html/images/centos-updated.qcow2.md5sum
```

### 2.5. Directly Provisioning Bare Metal Hosts

It’s also possible to provision via the `BareMetalHost` interface directly
without using the Cluster API integration.

There is a helper script available to trigger provisioning of one of these
hosts. To provision a host with CentOS, run:

```sh
$ ./provision_host.sh node-0
```

The `BareMetalHost` will go through the provisioning process, and will
eventually reboot into the operating system we wrote to disk.

```sh
$ kubectl get baremetalhost node-0 -n metal3
NAME       STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0     OK       provisioned                     ipmi://192.168.111.1:6230   unknown            true
```

`provision_host.sh` will inject your SSH public key into the VM. To find the IP
address, you can check the DHCP leases on the `baremetal` libvirt network.

```sh
$ sudo virsh net-dhcp-leases baremetal

 Expiry Time          MAC address        Protocol  IP address                Hostname        Client ID or DUID
-------------------------------------------------------------------------------------------------------------------
 2019-05-06 19:03:46  00:1c:cc:c6:29:39  ipv4      192.168.111.20/24         node-0          -
 2019-05-06 19:04:18  00:1c:cc:c6:29:3d  ipv4      192.168.111.21/24         node-1          -
```

The default user for the CentOS image is `metal3`.

```sh
ssh metal3@192.168.111.20
```

There is another helper script to deprovision a host.

```sh
$ ./deprovision_host.sh node-0
```

You will then see the host go into a `deprovisioning` status:

```sh
$ kubectl get baremetalhost node-0 -n metal3
NAME       STATUS   PROVISIONING STATUS   MACHINE   BMC                         HARDWARE PROFILE   ONLINE   ERROR
node-0     OK       deprovisioning                  ipmi://192.168.111.1:6230   unknown            true
```

### 2.6. Running Custom Baremetal-Operator

The `baremetal-operator` comes up running in the cluster by default, using an
image built from the [metal3-io/baremetal-operator](https://github.com/metal3-io/baremetal-operator) repository. If you’d like to test changes to the
`baremetal-operator`, you can follow this process.

First, you must scale down the deployment of the `baremetal-operator` running
in the cluster.

```sh
kubectl scale deployment metal3-baremetal-operator -n metal3 --replicas=0
```

To be able to run `baremetal-operator` locally, you need to install
[operator-sdk](https://github.com/operator-framework). After that, you can run
the `baremetal-operator` including any custom changes.

```sh
cd ~/go/src/github.com/metal3-io/baremetal-operator
make run
```

### 2.7. Running Custom Cluster API Provider Metal3

There are two Cluster API related managers running in the cluster. One
includes set of generic controllers, and the other includes a custom Machine
controller for Metal3. If you want to try changes to
`cluster-api-provider-metal3`, you want to shut down the custom Machine
controller manager first.

```sh
$ kubectl scale statefulset capm3-controller-manager -n capm3-system --replicas=0
```

Then you can run the custom Machine controller manager out of your local git tree.

```sh
cd ~/go/src/github.com/metal3-io/cluster-api-provider-metal3
make run
```

### 2.8. Accessing Ironic API

Sometimes you may want to look directly at Ironic to debug something.
The metal3-dev-env repository contains a clouds.yaml file with
connection settings for Ironic.

metal3-dev-env will install the openstack command line tool on the
provisioning host as part of setting up the cluster. The openstack tool
will look for clouds.yaml in the current directory or you can copy it to
~/.config/openstack/clouds.yaml. Version 3.19.0 or higher is needed to
interact with Ironic using clouds.yaml.

Example:

```sh
[notstack@metal3 metal3-dev-env]$ export OS_CLOUD=metal3
[notstack@metal3 metal3-dev-env]$ openstack baremetal node list
+--------------------------------------+--------+---------------+-------------+--------------------+-------------+
| UUID                                 | Name   | Instance UUID | Power State | Provisioning State | Maintenance |
+--------------------------------------+--------+---------------+-------------+--------------------+-------------+
| 882cf206-d688-43fa-bf4c-3282fcb00b12 | node-0 | None          | None        | enroll             | False       |
| ac257479-d6c6-47c1-a649-64a88e6ff312 | node-1 | None          | None        | enroll             | False       |
+--------------------------------------+--------+---------------+-------------+--------------------+-------------+
```

To view a particular node's details, run the below command. The
`last_error`, `maintenance_reason`, and `provisioning_state` fields are
useful for troubleshooting to find out why a node did not deploy.

```sh
[notstack@metal3 metal3-dev-env]$ export OS_CLOUD=metal3
[notstack@metal3 metal3-dev-env]$ openstack baremetal node show 882cf206-d688-43fa-bf4c-3282fcb00b12
+------------------------+------------------------------------------------------------+
| Field                  | Value                                                      |
+------------------------+------------------------------------------------------------+
| allocation_uuid        | None                                                       |
| automated_clean        | None                                                       |
| bios_interface         | no-bios                                                    |
| boot_interface         | ipxe                                                       |
| chassis_uuid           | None                                                       |
| clean_step             | {}                                                         |
| conductor              | localhost.localdomain                                      |
| conductor_group        |                                                            |
| console_enabled        | False                                                      |
| console_interface      | no-console                                                 |
| created_at             | 2019-10-07T19:37:36+00:00                                  |
| deploy_interface       | direct                                                     |
| deploy_step            | {}                                                         |
| description            | None                                                       |
| driver                 | ipmi                                                       |
| driver_info            | {u'ipmi_port': u'6230', u'ipmi_username': u'admin', u'deploy_kernel': u'http://172.22.0.2/images/ironic-python-agent.kernel', u'ipmi_address': u'192.168.111.1', u'deploy_ramdisk': u'http://172.22.0.2/images/ironic-python-agent.initramfs', u'ipmi_password': u'******'} |
| driver_internal_info   | {u'agent_enable_ata_secure_erase': True, u'agent_erase_devices_iterations': 1, u'agent_erase_devices_zeroize': True, u'disk_erasure_concurrency': 1, u'agent_continue_if_ata_erase_failed': False}                                                                          |
| extra                  | {}                                                         |
| fault                  | clean failure                                              |
| inspect_interface      | inspector                                                  |
| inspection_finished_at | None                                                       |
| inspection_started_at  | None                                                       |
| instance_info          | {}                                                         |
| instance_uuid          | None                                                       |
| last_error             | None                                                       |
| maintenance            | True                                                       |
| maintenance_reason     | Timeout reached while cleaning the node. Please check if the ramdisk responsible for the cleaning is running on the node. Failed on step {}.                                                                                                                                |
| management_interface   | ipmitool                                                   |
| name                   | master-0                                                   |
| network_interface      | noop                                                       |
| owner                  | None                                                       |
| power_interface        | ipmitool                                                   |
| power_state            | power on                                                   |
| properties             | {u'cpu_arch': u'x86_64', u'root_device': {u'name': u'/dev/sda'}, u'local_gb': u'50'}                                                                                                                                                                                        |
| protected              | False                                                      |
| protected_reason       | None                                                       |
| provision_state        | clean wait                                                 |
| provision_updated_at   | 2019-10-07T20:09:13+00:00                                  |
| raid_config            | {}                                                         |
| raid_interface         | no-raid                                                    |
| rescue_interface       | no-rescue                                                  |
| reservation            | None                                                       |
| resource_class         | baremetal                                                  |
| storage_interface      | noop                                                       |
| target_power_state     | None                                                       |
| target_provision_state | available                                                  |
| target_raid_config     | {}                                                         |
| traits                 | []                                                         |
| updated_at             | 2019-10-07T20:09:13+00:00                                  |
| uuid                   | 882cf206-d688-43fa-bf4c-3282fcb00b12                       |
| vendor_interface       | ipmitool                                                   |
+-------------------------------------------------------------------------------------+
```
