# Title: Scaling Kubernetes with Metal3: Simulating 1000 Clusters with Fake Ironic Agents
## Introduction

If you’ve ever tried scaling out Kubernetes clusters in a bare-metal environment, you’ll know that testing at large scale comes with some serious challenges. Most of us don’t have access to enough physical servers—or even virtual machines—to simulate the kinds of large-scale environments we need for stress-testing, especially when it comes to deploying hundreds or even thousands of clusters.

That’s where this experiment comes in.

Using Metal3, we set out to simulate a massive environment—provisioning 1000 single-node Kubernetes clusters—without any actual hardware. The trick? A combination of Fake Ironic Python Agents (IPA) and Fake Kubernetes API servers. These tools allowed us to run a fully realistic Metal3 provisioning workflow while simulating thousands of nodes and clusters, all without needing a single real machine.

The motivation behind this was simple: to create a scalable testing environment that lets us validate Metal3’s performance, workflow, and reliability, without the need for an expensive hardware lab or virtual machine fleet. By simulating nodes and clusters, we could push the limits of Metal3’s provisioning process in a cost-effective and time-efficient way.

In this post, I’ll walk you through exactly how it all works, from setting up multiple Ironic services, to faking hardware nodes and clusters, to the lessons learned. Whether you’re a Metal3 user or just curious about how to test large-scale Kubernetes environments, it'll surely be a good read. Let’s get started!

## Prerequisites & Setup
Before we dive into the fun stuff, let’s make sure we’re on the same page. You don’t need to be a Metal3 expert to follow along, but having a bit of background will help!

#### What You’ll Need to Know:

Let’s start by making sure you’re familiar with some of the key tools and concepts that power Metal3 workflow. Please feel free to skip this part if you're confident with your Metal3 skills

##### Cluster API (CAPI)
CAPI is a project that simplifies the deployment and management of Kubernetes clusters. It provides a consistent way to create, update, and scale clusters through a set of Kubernetes-native APIs. The magic of CAPI is that it abstracts away many of the underlying details, so you can manage clusters on different platforms (cloud, bare metal, etc.) in a unified way.

##### Cluster API Provider Metal3 (CAPM3)
CAPM3 extends CAPI to work specifically with Metal3 environments. It connects the dots between CAPI, BMO, and Ironic, allowing Kubernetes clusters to be deployed on bare-metal infrastructure. It handles tasks like provisioning new nodes, registering them with Kubernetes, and scaling clusters.
##### Bare Metal Operator (BMO)
BMO is a controller that runs inside a Kubernetes cluster and works alongside Ironic to manage bare-metal infrastructure. It automates the lifecycle of bare-metal hosts, managing things like registering new hosts, powering them on or off, and monitoring their status.

###### Bare Metal Host (BMH)
A BMH is the kubernetes representation of a baremetal node. It contains the information of how to reach the node it represents, and its desired state is monitored closely by BMO. When BMO notices that a BMH object state is requested to change (either by a human user or CAPM3), it will decide what needs to be done, and tell Ironic.

##### Ironic & Ironic Python Agent (IPA)
- Ironic is a bare-metal provisioning tool that handles tasks like booting servers, installing operating systems, and configuring hardware. Think of Ironic as the piece of software that manages actual physical servers. In a Metal3 workflow, Ironic receives orders from BMO, and translates into actionable steps.
- Ironic Python Agent (IPA) is the software that runs on each bare-metal node to carry out Ironic’s instructions. It interacts with the hardware directly, like wiping disks, configuring networks, and handling boot processes.

__Quick Intro: How Ironic and IPA Work Together in Metal3__
Ironic is the bare-metal provisioning tool used in Metal3. Think of it as the system that manages actual servers—turning them on, installing operating systems, and so on. When you want to deploy a Kubernetes cluster on bare-metal hardware, Ironic is the one making sure that each physical server is up and running with the right setup.

The Ironic Python Agent (IPA) plays a super important role here. It’s a little program that runs on the bare-metal machines Ironic is provisioning. You can think of IPA as the "hands" of Ironic—it actually touches the hardware to do things like:

- Booting up the machine.
- Installing the operating system.
- Configuring network settings.

In a normal Metal3 workflow, BMO translates the kubernetes reconciling logic to concrete actions and forward them to Ironic, which tells the IPA what to do. For example, BMO might notice that  Ironic might tell IPA to boot up a server and install an image, and IPA will carry out these tasks. Once the node is ready, Ironic passes control back to CAPI and CAPM3, which can then set up Kubernetes clusters on these provisioned machines.


## The Experiment: Simulating 1000 Kubernetes Clusters
The goal of this experiment was to push Metal3 to simulate 1000 single-node Kubernetes clusters on fake hardware. Instead of provisioning real machines, we used Fake Ironic Python Agents (Fake IP) and Fake Kubernetes API Servers (FKAS) to simulate nodes and control planes, respectively. This setup allowed us to test a massive environment without the need for physical infrastructure.

### Step 1: Setting Up the environment
As you may have known, a typical Metal3 workflow requires existence of several components: bootstrap kubernetes cluster, special networks, baremetal nodes, etc. As we are working on simulating environment, we will start with a newly spawn Ubuntu VM, create a cluster with minikube, add networks with libvirt, and so on (If you're familiar with the Metal3's dev-env, this step is similar to what script [01](), [02] and a part of [03] do). We will not go into details on this part, but you can find the related setup from [this script]() if you are interested.

**Note**: If you intend to follow along, note that going to 1000 nodes requires a large environment and will take a long time. In our setup, we had a VM with 24 cores and 32GB of RAM, of which we assigned 14 cores and 20GB of RAM to the minikube VM, and the whole process took roughly 48 hours. If your environment is less powerful, consider reducing the number of nodes you want to provision. Something like 100 nodes will require very minimum resource and time, while still be an impressive outcome.
### Step 2: Install BMO and Ironics

In Metal3’s typical workflow, we usually rely on **Kustomize** to install Ironic and BMO. Kustomize helps us define configurations for Kubernetes resources, making it easier to customize and deploy services. However, the current Kustomize overlay we use for Metal3 is designed to configure **only a single Ironic instance**. This setup works well for smaller environments, but it becomes a bottleneck when you’re trying to scale up and handle thousands of nodes.

That’s where Ironic’s **special mode** comes into play. Ironic has the ability to run **multiple Ironic conductors** while sharing the same database. The best part? Workload balancing between conductors happens automatically. This means that no matter which Ironic conductor receives a request, the load is evenly distributed across all conductors, ensuring efficient provisioning. To achieve this requires separation of **ironic conductor** from the database, from which the conductor part can be scaled up. Each **conductor** will have its own `PROVISIONING_IP`, hence the need of having a specialized `configMap`.

We used [Helm]() for this purpose. In our Helm chart, **Ironic conductor** container and **HTTP server (httpd)** container are separated into a new pod, while the rest of the ironic package (mostly `mariadb` - ironic database) stays in another pod. A list of `PROVISIONING_IP`s is provided by the chart's `values.yaml`, and for each ip, an  **ironic conductor** pod is created, along with a configmap whose values rendered with the ip's value. This way, we can dynamically scale up/down ironic (or more specifically **ironic conductors** by simply adding/removing ips.

BMO, on the other hand, still works well with kustomize, as we do not need to scale it. As with normal metal3 workflow, BMO and Ironic will need to share some authentication, so that they can work together with TLS.

You can check out the full Ironic helm chart [here]()

### Step 2: Creating Fake Nodes with Fake Ironic Python Agents
As we mentioned at the beginning, instead of using real hardware, we will use a new tool called **Fake Ironic Python Agent**, or **Fake IPA** to simulate the nodes.

Setting up **Fake IPA** is quite straight-forward, as **Fake IPA** runs as containers in the host machine, but first, we need to create the list of "nodes" that we will use (Fake IPA requires to have that list ready when it starts). A "node" typically looks like this


```shell
'{
      "uuid": $uuid,
      "name": $node_name,
      "power_state": "Off",
      "external_notifier": "True",
      "nics": [
	{"mac": $macaddr, "ip": "192.168.0.100"}
```

All of the variables (`uuid`, `node_name`, `macaddress`) can be dynamically generated in any way you want (check [this script]() out if you need an idea), but we will need to store these information in so that we can generate the BMH objects that match those "nodes". The `ip` is, on other hand, not important. It could be anything.

Note that in this step, we also need to start up the **sushy-tools** container. It is a tool that simulates the [Baseboard Management Controller](https://www.techtarget.com/searchnetworking/definition/baseboard-management-controller) for non-baremetal hardware, and we have been using it extensively inside Metal3 dev-env and CI to control and provision VMs as if they are baremetal nodes. Similarly to how ironic controls the BMC to install IPA on the node, in this setup Ironic will ask **sushy-tools** the same thing, but as **sushy-tools** was configured with **Fake IPA** endpoint, it will simply fake the installation, and in the end forward **Ironic** traffic to the **Fake IPA** container.

Another piece of information we will need is the cert that **Ironic** will use in its communication with **IPA**. IPA is supposed to get it from Ironic, but as **Fake IPA** cannot do that (at least not yet), we will have to get the cert and provide it in **Fake IPA** config.

```shell

mkdir cert
kubectl get secret -n baremetal-operator-system ironic-cert -o json -o=jsonpath="{.data.ca\.crt}" | base64 -d >cert/ironic-ca.crt
```

Also note that one set of **sushy-tools** and **Fake IPA** containers won't be enough to provision 1000 nodes. Just like **Ironic**, they need to be scaled up extensively (about 20-30 pairs will be sufficient for 1000 nodes), but fortunately the scaling is very easy. We just need to give them different ports. For convenience, we can use the same config file for both **sushy-tools** and **Fake IPA**, even though not all of them will be used by both the containers.

```shell

for i in $(seq 1 "$N_SUSHY"); do
  container_conf_dir="$SUSHY_CONF_DIR/sushy-$i"
  fake_ipa_port=$((9901 + (($i % ${N_FAKE_IPA:-1}))))
  port=$((8000 + i))
  ports+=(${port})
  ports+=(${fake_ipa_port})
  mkdir -p "${container_conf_dir}"
  cat <<'EOF' >"${container_conf_dir}"/htpasswd
admin:$2b$12$/dVOBNatORwKpF.ss99KB.vESjfyONOxyH.UgRwNyZi1Xs/W2pGVS
EOF
  # Set configuration options
  cat <<EOF >"${container_conf_dir}"/conf.py
import collections

SUSHY_EMULATOR_LIBVIRT_URI = "${LIBVIRT_URI}"
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = False
SUSHY_EMULATOR_VMEDIA_VERIFY_SSL = False
SUSHY_EMULATOR_AUTH_FILE = "/root/sushy/htpasswd"
SUSHY_EMULATOR_FAKE_DRIVER = True
SUSHY_EMULATOR_LISTEN_PORT = $((8000 + i))
EXTERNAL_NOTIFICATION_URL = "http://${ADVERTISE_HOST}:${fake_ipa_port}"
FAKE_IPA_API_URL = "${API_URL}"
FAKE_IPA_URL = "http://${ADVERTISE_HOST}:${fake_ipa_port}"
FAKE_IPA_INSPECTION_CALLBACK_URL = "${CALLBACK_URL}"
FAKE_IPA_ADVERTISE_ADDRESS_IP = "${ADVERTISE_HOST}"
FAKE_IPA_ADVERTISE_ADDRESS_PORT = "${fake_ipa_port}"
FAKE_IPA_CAFILE = "/root/cert/ironic-ca.crt"
SUSHY_FAKE_IPA_LISTEN_IP = "${ADVERTISE_HOST}"
SUSHY_FAKE_IPA_LISTEN_PORT = "${fake_ipa_port}"
SUSHY_EMULATOR_FAKE_IPA = True
SUSHY_EMULATOR_FAKE_SYSTEMS = $(cat nodes.json)
EOF

  # Start sushy-tools
  docker run -d --net host --name "sushy-tools-${i}" \
    -v "${container_conf_dir}":/root/sushy \
    "${SUSHY_TOOLS_IMAGE}"

  # Start fake-ipa
  docker run \
    -d --net host --name fake-ipa-${i} \
    -v "${container_conf_dir}":/app \
    -v "$(realpath cert)":/root/cert \
    "${FAKEIPA_IMAGE}"
done
```

In this setup, we made it so that all the **sushy-tools** containers will listen on the port range running from 8001, 8002,..., while the **Fake IPA** containers have ports 9001, 9002,... This will likely cause a problem if you have more than 1000 **sushy-tools** containers, but if that's the case, simply choose a less crowded range (for e.g. 700x and 900x) will help.

### Step 3: Add the BMH objects

Now that we have **sushy-tools** and **Fake IPA** containers running, we can already generate the manifest for BMH objects, and apply them to the cluster. A BMH object will look like this

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: {name}-bmc-secret
  labels:
      environment.metal3.io: baremetal
type: Opaque
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQ=
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: {name}
spec:
  online: true
  bmc:
    address: redfish+http://192.168.222.1:{port}/redfish/v1/Systems/{uuid}
    credentialsName: {name}-bmc-secret
  bootMACAddress: {random_mac}
  bootMode: legacy
```
In this manifest:
- `name` is the node name that we generated in the previous step.
- `uuid` is the random uuid that we generated for the same node.
- `random_mac` is a random mac address for the boot. It's NOT the same as the NIC mac address that we generated for the node.
- `port` is the listening port on one of the **sushy-tools** containers that we created in the previous step. Since every **sushy-tools** and **Fake IPA** container has information
about ALL the nodes, we can decide what container to locate the "node". In general, it's a good idea to spread them out, so all containers are loaded equally.

We can go ahead and run `kubectl apply -f` on one (or all of) the BMH manifests. What you expect to see is that a BMH object is created, and its state will change from `registering` to `available` after awhile. It means **ironic** acknowledged that the node is valid, in good state and ready to be provisioned.

### Step 4: Deploy the fake nodes to kubernetes clusters

In a normal Metal3 workflow, after having the BMH objects in `available` state, we can go ahead and provision new kubernetes clusters with `clusterctl`. However, with fake nodes, things get a tiny bit more complex. At the end of the provisioning process, **Cluster API** expects that there is a new kubernetes API server created for the new cluster, from which it will check if all nodes are up, all the control planes have `apiserver`, `etcd`, etc. pods up and running, and so on. It is where the [**Fake Kubernetes API Server** (FKAS)]() comes in.

As the **FKAS README** linked above already described how it works, we won't go into details. Basically, we will just need to send **FKAS** a `register` request, and it will give us an IP and a port, which we can plug into our cluster template, and then run `clusterctl generate cluster`.

Under the hood, **FKAS** generates unique API servers for different clusters. Each of the fake API servers does the following jobs:
- Mimicking API Calls: The Fake Kubernetes API server was set up to respond to the essential Kubernetes API calls made during provisioning.
- Node Registration: When CAPM3 registered nodes, the Fake API server returned success responses, making Metal3 believe the nodes had joined a real Kubernetes cluster.
- Cluster Health and Status: The Fake API responded with "healthy" statuses, allowing CAPI/CAPM3 to continue its workflow without interruption.
- Node Creation and Deletion: When CAPI queried for node status or attempted to add/remove nodes, the Fake API server responded with realistic responses, ensuring the provisioning process continued smoothly.
- Pretending to Host Kubelets: The Fake API server also simulated kubelet responses, which allowed CAPI/CAPM3 to interact with the fake clusters as though they were managing real nodes.

In the end, we should expect to see `clusterctl describe cluster` response with OK status. In this experiment, we provisioned every of the 1000 fake nodes to a single-node cluster, but it's possible to increase the number of control-planes and worker nodes by changing `--control-plane-machine-count` and `worker-machine-count` parameters in `clusterctl generate cluster` command.

## Results & Performance Insights
