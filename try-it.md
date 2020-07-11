---
layout: tryit
title: "Try it: Getting started with Metal3.io"
permalink: /try-it.html
---

<!-- TOC depthFrom:2 insertAnchor:false orderedList:false updateOnSave:true withLinks:true -->

- [1. Environment Setup](#1-environment-setup)
    - [1.1. Prerequisites](#11-prerequisites)
    - [1.2. Setup](#12-setup)
    - [1.3. Using Custom Image](#13-using-custom-image)
- [2. Working with Environment](#2-working-with-environment)
    - [2.1. BareMetalHosts](#21-baremetalhosts)
    - [2.2. Provision Cluster and Machines](#22-provision-cluster-and-machines)
    - [2.3. Deprovision Cluster and Machines](#23-deprovision-cluster-and-machines)
    - [2.4. Image configuration (Centos 7 target hosts only)](#24-image-configuration-centos-7-target-hosts-only)
    - [2.5. Directly Provision BareMetalHost](#25-directly-provision-baremetalhost)
    - [2.6. Running Custom Baremetal-Operator](#26-running-custom-baremetal-operator)
    - [2.7. Running Custom Cluster API Provider Metal3](#27-running-custom-cluster-api-provider-metal3)
    - [2.8. Accessing Ironic API](#28-accessing-ironic-api)

<!-- /TOC -->
<hr>
## 1. Environment-Setup

> info "Naming"
> For the v1alpha3 release, the Cluster API provider for Metal3 was renamed from
> Cluster API provider BareMetal (CAPBM) to Cluster API provider Metal3 (CAPM3). Hence, 
> from v1alpha3 onwards it is Cluster API provider Metal3.

### 1.1. Prerequisites

- System with CentOS 8 or Ubuntu 18.04
- Bare metal preferred, as we will be creating VMs to emulate bare metal hosts
- Run as a user with passwordless sudo access
- Minimum resource requirements for the host machine: 4C CPUs, 16 GB RAM memory.

### 1.2. Setup

> info "Information"
> If you need detailed information regarding the process of creating a Metal³ emulated environment using metal3-dev-env, it is worth taking a look at the blog post ["A detailed walkthrough of the Metal³ development environment"]({% post_url 2020-02-18-metal3-dev-env-install-deep-dive %}).

This is a high-level architecture of the Metal³-dev-env. Note that for Ubuntu based setup, either Kind or Minikube can be used to instantiate an ephemeral cluster, while for CentOS based setup only Minikube is currently supported. Ephemeral cluster creation tool can be manipulated with EPHEMERAL_CLUSTER environment variable. 

<p align="center">
  <img src="assets/images/metal3-dev-env.svg">
</p>

tl;dr - Clone [metal³-dev-env](https://github.com/metal3-io/metal3-dev-env)
and run

```sh
$ make
```

The `Makefile` runs a series of scripts, described here:

- `01_prepare_host.sh` - Installs all needed packages.

- `02_configure_host.sh` - Creates a set of VMs that will be managed as if they
  were bare metal hosts. It also downloads some images needed for Ironic.

- `03_launch_mgmt_cluster.sh` - Launches a management cluster using `minikube` or `kind`
and runs the `baremetal-operator` on that cluster.

- `04_verify.sh` - Runs a set of tests that verify that the deployment completed successfully.

When the environment setup is completed, you should be able to see `BareMetalHost` (bmh) objects in Ready state.

To tear down the environment, run

```sh
$ make clean
```
> info "Note"
> When redeploying metal³-dev-env with a different release version of CAPM3, you
> must set the `FORCE_REPO_UPDATE` variable in `config_${user}.sh` to *true*.

### 1.3. Using Custom Image

Whether you want to run target cluster Nodes with your own image, you can override the three following variables: `IMAGE_NAME`,
`IMAGE_LOCATION`, `IMAGE_USERNAME`. If the requested image with name `IMAGE_NAME` does not
exist in the `IRONIC_IMAGE_DIR` (/opt/metal3-dev-env/ironic/html/images) folder, then it will be automatically
downloaded from the `IMAGE_LOCATION` value configured.

> warning "Warning"
> If you see this error during the installation:
>```
> error: failed to connect to the hypervisor \
> error: Failed to connect socket to '/var/run/libvirt/libvirt-sock':  Permission denied
>```
> You may need to log out then login again, and run `make clean` and `make` again.

## 2. Working with Environment

### 2.1. BareMetalHosts

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
defition file used to create these host objects is in `bmhosts_crs.yaml`.

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

### 2.2. Provision Cluster and Machines

This section describes how to trigger provisioning of a cluster and hosts via
`Machine` objects as part of the Cluster API integration. This uses Cluster API
[v1alpha3](https://github.com/kubernetes-sigs/cluster-api/tree/v0.3.0) and
assumes that metal3-dev-env is deployed with the environment variable
**CAPM3_VERSION** set to **v1alpha3**. The v1alpha3 deployment can be done with
Ubuntu 18.04 or Centos 8 target host images. Please make sure to meet [resource requirements](#11-prerequisites) for successfull deployment:

The following scripts can be used to provision a cluster, controlplane node and worker node.

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

If you look at the yaml representation of the `Machine` object, you will see a 
new annotation that identifies which `BareMetalHost` was chosen to satisfy this
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

You should be able to ssh into your host once provisioning is completed.
The default username for both CentOS & Ubuntu image is `metal3`.
For the IP address, you can either use API endpoint IP of the target cluster 
which is - `192.168.111.249` by default or use predictable IP address of the first 
master node - `192.168.111.100`.

```sh
$ ssh metal3@192.168.111.249
```

### 2.3. Deprovision Cluster and Machines

Deprovisioning of the target cluster is done just by deleting `Cluster` and `Machine` objects or by executing the deprovisioning scripts in reverse order than provisioning:

```sh
$ ./scripts/deprovision/worker.sh
$ ./scripts/deprovision/controlplane.sh
$ ./scripts/deprovision/cluster.sh
```

Note that you can easily deprovision worker Nodes by decreasing the number of replicas in the `MachineDeployment` object created when executing the `provision_worker.sh` script:

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

### 2.4. Image Configuration (Centos 7 target hosts only)

If you want to deploy Ubuntu hosts, please skip this section.

As shown in the [prerequisites](#11-prerequisites) section, the preferred OS image for CentOS is version 8. Actually, for both the system where the metal3-dev-env environment is configured and the target cluster nodes.

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

### 2.5. Directly Provision BareMetalHost

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