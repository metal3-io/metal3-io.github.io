---
title: "Scaling to 1000 clusters - Part 2"
date: 2023-05-17
draft: false
categories: ["metal3", "cluster API", "provider", "edge"]
author: Lennart Jern
---

In [part 1]({% link _posts/2023-05-05-Scaling_part_1.md %}), we introduced the Bare Metal Operator test mode and saw how it can be used to play with BareMetalHosts without Ironic and without any actual hosts.
Now we will take a look at the other end of the stack and how we can fake the workload cluster API's.

## Test setup

The end goal is to have one management cluster where the Cluster API and Metal3 controllers run.
In this cluster we would generate BareMetalHosts and create Clusters, Metal3Clusters, etc to benchmark the controllers.
To give them a realistic test, we also need to fake the workload cluster API's.
These will run separately in "backing" clusters to avoid interfering with the test (e.g. by using up all the resources in the management cluster).
Here is a diagram that describes the setup:

![diagram of test setup](/assets/2023-05-17-Scaling_part_2/scaling-fake-clusters.drawio.png)

How are we going to fake the workload cluster API's then?
The most obvious solution is to just run the real deal, i.e. the `kube-apiserver`.
This is what would be run in a real workload cluster, together with the other components that make up the Kubernetes control plane.

If you want to follow along and try to set this up yourself, you will need at least the following tools installed:

- [kind](https://kind.sigs.k8s.io/docs/user/quick-start)
- [kubectl](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl)
- [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [clusterctl](https://cluster-api.sigs.k8s.io/user/quick-start.html#install-clusterctl)
- [openssl](https://github.com/openssl/openssl)
- [curl](https://curl.se/)
- [wget](https://www.gnu.org/software/wget/)

This has been tested with Kubernetes v1.25, kind v0.19 and clusterctl v1.4.2.
All script snippets are assumed to be for the `bash` shell.

## Running the Kubernetes API server

There are many misconceptions, maybe even superstitions, about the Kubernetes control plane.
The fact is that it is in no way special.
It consists of a few programs that can be run in any way you want: in a container, as a systemd unit or directly executed at the command line.
They can run on a Node or outside of the cluster.
You can even run multiple instances on the same host as long as you avoid port collisions.

For our purposes we basically want to run as little as possible of the control plane components.
We just need the API to be available and possible for us to populate with data that the controllers expect to be there.
In other words, we need the API server and etcd.
The scheduler is not necessary since we won't run any actual workload (we are just pretending the Nodes are there anyway) and the controller manager would just get in the way when we want to fake resources.
It would, for example, try to update the status of the (fake) Nodes that we want to create.

The API server will need an etcd instance to connect to.
It will also need some TLS configuration, both for connecting to etcd and for handling service accounts.
One simple way to generate the needed certificates is to use kubeadm.
But before we get there we need to think about how the configuration should look like.

For simplicity, we will simply run the API server and etcd in a kind cluster for now.
It would then be easy to run them in some other Kubernetes cluster later if needed.
Let's create it right away:

```bash
kind create cluster
# Note: This has been tested with node image
# kindest/node:v1.26.3@sha256:61b92f38dff6ccc29969e7aa154d34e38b89443af1a2c14e6cfbd2df6419c66f
```

To try to cut down on the resources required, we will also use a single multi-tenant etcd instance instead of one per API server.
We can rely on the internal service discovery so the API server can find etcd via an address like `etcd-server.etd-system.svc.cluster.local`, instead of using IP addresses.
Finally, we will need an endpoint where the API is exposed to the cluster where the controllers are running, but for now we can focus on just getting it up and running with `127.0.0.1:6443` as the endpoint.

Based on the above, we can create a `kubeadm-config.yaml` file like this:

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  certSANs:
  - 127.0.0.1
clusterName: test
controlPlaneEndpoint: 127.0.0.1:6443
etcd:
  local:
    serverCertSANs:
    - etcd-server.etcd-system.svc.cluster.local
    peerCertSANs:
    - etcd-0.etcd.etcd-system.svc.cluster.local
kubernetesVersion: v1.25.3
certificatesDir: /tmp/test/pki
```

We can now use this to generate some certificates and upload them to the cluster:

```bash
# Generate CA certificates
kubeadm init phase certs etcd-ca --config kubeadm-config.yaml
kubeadm init phase certs ca --config kubeadm-config.yaml
# Generate etcd peer and server certificates
kubeadm init phase certs etcd-peer --config kubeadm-config.yaml
kubeadm init phase certs etcd-server --config kubeadm-config.yaml

# Upload certificates
kubectl create namespace etcd-system
kubectl -n etcd-system create secret tls test-etcd --cert /tmp/test/pki/etcd/ca.crt --key /tmp/test/pki/etcd/ca.key
kubectl -n etcd-system create secret tls etcd-peer --cert /tmp/test/pki/etcd/peer.crt --key /tmp/test/pki/etcd/peer.key
kubectl -n etcd-system create secret tls etcd-server --cert /tmp/test/pki/etcd/server.crt --key /tmp/test/pki/etcd/server.key
```

### Deploying a multi-tenant etcd instance

Now it is time to deploy etcd!

```bash
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/manifests/v2/etcd.yaml \
  | sed "s/CLUSTER/test/g" | kubectl -n etcd-system apply -f -
kubectl -n etcd-system wait sts/etcd --for=jsonpath="{.status.availableReplicas}"=1
```

As mentioned before, we want to create a [multi-tenant etcd](https://etcd.io/docs/v3.5/op-guide/authentication/rbac/) that many API servers can share.
For this reason, we will need to create a root user and enable authentication for etcd:

```bash
# Create root role
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  role add root
# Create root user
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user add root --new-user-password="rootpw"
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user grant-role root root
# Enable authentication
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  auth enable
```

At this point we have a working etcd instance with authentication and TLS enabled.
Each client will need to have an etcd user to interact with this instance so we need to create an etcd user for the API server.
We already created a root user before so this should look familiar.

```bash
## Create etcd tenant
# Create user
kubectl -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user add test --new-user-password=test
# Create role
kubectl -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  role add test
# Add read/write permissions for prefix to the role
kubectl -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  role grant-permission test --prefix=true readwrite "/test/"
# Give the user permissions from the role
kubectl -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user grant-role test test
```

From etcd's point of view, everything is now ready.
The API server could theoretically use `etcdctl` and authenticate with the username and password that we created for it.
However, that is not how the API server works.
It expects to be able to authenticate using client certificates.
Luckily, etcd supports this so we just have to generate the certificates and sign them so that etcd trusts them.
The key thing is to set the common name in the certificate to the name of the user we want to authenticate as.

Since `kubeadm` always sets the same common name, we will here use `openssl` to generate the client certificates so that we get control over it.

```bash
# Generate etcd client certificate
openssl req -newkey rsa:2048 -nodes -subj "/CN=test" \
 -keyout "/tmp/test/pki/apiserver-etcd-client.key" -out "/tmp/test/pki/apiserver-etcd-client.csr"
openssl x509 -req -in "/tmp/test/pki/apiserver-etcd-client.csr" \
  -CA /tmp/test/pki/etcd/ca.crt -CAkey /tmp/test/pki/etcd/ca.key -CAcreateserial \
  -out "/tmp/test/pki/apiserver-etcd-client.crt" -days 365
```

### Deploying the API server

In order to deploy the API server, we will first need to generate some more certificates.
The client certificates for connecting to etcd are already ready, but it also needs certificates to secure the exposed API itself, and a few other things.
Then we will also need to create secrets from all of these certificates:

```bash
kubeadm init phase certs ca --config kubeadm-config.yaml
kubeadm init phase certs apiserver --config kubeadm-config.yaml
kubeadm init phase certs sa --cert-dir /tmp/test/pki

kubectl create ns workload-api
kubectl -n workload-api create secret tls test-ca --cert /tmp/test/pki/ca.crt --key /tmp/test/pki/ca.key
kubectl -n workload-api create secret tls test-etcd --cert /tmp/test/pki/etcd/ca.crt --key /tmp/test/pki/etcd/ca.key
kubectl -n workload-api create secret tls "test-apiserver-etcd-client" \
  --cert "/tmp/test/pki/apiserver-etcd-client.crt" \
  --key "/tmp/test/pki/apiserver-etcd-client.key"
kubectl -n workload-api create secret tls apiserver \
  --cert "/tmp/test/pki/apiserver.crt" \
  --key "/tmp/test/pki/apiserver.key"
kubectl -n workload-api create secret generic test-sa \
  --from-file=tls.crt="/tmp/test/pki/sa.pub" \
  --from-file=tls.key="/tmp/test/pki/sa.key"
```

With all that out of the way, we can finally deploy the API server!
For this we will use a normal Deployment.

```bash
# Deploy API server
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/manifests/v2/kube-apiserver-deployment.yaml |
  sed "s/CLUSTER/test/g" | kubectl -n workload-api apply -f -
kubectl -n workload-api wait --for=condition=Available deploy/test-kube-apiserver
```

Time to check if it worked!
We can use port-forwarding to access the API, but of course we will need some authentication method for it to be useful.
With kubeadm we can generate a kubeconfig based on the certificates we already have.

```bash
kubeadm kubeconfig user --client-name kubernetes-admin --org system:masters \
  --config kubeadm-config.yaml > kubeconfig.yaml
```

Now open another terminal and set up port-forwarding to the API server:

```bash
kubectl -n workload-api port-forward svc/test-kube-apiserver 6443
```

Back in the original terminal, you should now be able to reach the workload API server:

```bash
kubectl --kubeconfig kubeconfig.yaml cluster-info
```

Note that it won't have any Nodes or Pods running.
It is completely empty since it is running on its own.
There is no kubelet that registered as a Node or applied static manifests, there is no scheduler or controller manager.
Exactly like we want it.

## Faking Nodes and other resources

Let's take a step back and think about what we have done so far.
We have deployed a Kubernetes API server and a multi-tenant etcd instance.
More API servers can be added in the same way, so it is straight forward to scale.
All of it runs in a kind cluster, which means that it is easy to set up and we can switch to any other Kubernetes cluster if needed later.
Through Kubernetes we also get an easy way to access the API servers by using port-forwarding, without exposing all of them separately.

The time has now come to think about what we need to put in the workload cluster API to convince the Cluster API and Metal3 controllers that it is healthy.
First of all they will expect to see Nodes that match the Machines and that they have a provider ID set.
Secondly, they will expect to see healthy control plane Pods.
Finally, they will try to check on the etcd cluster.

The final point is a problem, but we can work around it for now by configuring [external etcd](https://cluster-api.sigs.k8s.io/tasks/external-etcd.html).
It will lead to a different code path for the bootstrap and control plane controllers, but until we have something better it will be a good enough test.

Creating the Nodes and control plane Pods is really easy though.
We are just adding resources and there are no controllers or validating web hooks that can interfere.
Try it out!

```bash
# Create a Node
kubectl --kubeconfig=kubeconfig.yaml create -f https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/fake-node.yaml
# Check that it worked
kubectl --kubeconfig=kubeconfig.yaml get nodes
# Maybe label it as part of the control plane?
kubectl --kubeconfig=kubeconfig.yaml label node fake-node node-role.kubernetes.io/control-plane=""
```

Now add a Pod:

```bash
kubectl --kubeconfig=kubeconfig.yaml create -f https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-apiserver-pod.yaml
# Set status on the pods (it is not added when using create/apply).
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-apiserver-pod-status.yaml |
  kubectl --kubeconfig=kubeconfig.yaml -n kube-system patch pod kube-apiserver-node-name \
    --subresource=status --patch-file=/dev/stdin
```

You should be able to see something like this:

```console
$ kubectl --kubeconfig kubeconfig.yaml get pods -A
NAMESPACE     NAME                       READY   STATUS    RESTARTS   AGE
kube-system   kube-apiserver-node-name   1/1     Running   0          16h
$ kubectl --kubeconfig kubeconfig.yaml get nodes
NAME        STATUS   ROLES    AGE   VERSION
fake-node   Ready    <none>   16h   v1.25.3
```

Now all we have to do is to ensure that the API returns information that the controllers expect.

## Hooking up the API server to a Cluster API cluster

We will now set up a fresh cluster where we can run the Cluster API and Metal3 controllers.

```bash
# Delete the previous cluster
kind delete cluster
# Create a fresh new cluster
kind create cluster
# Initialize Cluster API with Metal3
clusterctl init --infrastructure metal3
## Deploy the Bare Metal Opearator
# Create the namespace where it will run
kubectl create ns baremetal-operator-system
# Deploy it in normal mode
kubectl apply -k https://github.com/metal3-io/baremetal-operator/config/default
# Patch it to run in test mode
kubectl patch -n baremetal-operator-system deploy baremetal-operator-controller-manager --type=json \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--test-mode"}]'
```

You should now have a cluster with the Cluster API, Metal3 provider and Bare Metal Operator running.
Next, we will prepare some files that will come in handy later, namely a cluster template, BareMetalHost manifest and Kubeadm configuration file.

```bash
# Download cluster-template
CLUSTER_TEMPLATE=/tmp/cluster-template.yaml
# https://github.com/metal3-io/cluster-api-provider-metal3/blob/main/examples/clusterctl-templates/clusterctl-cluster.yaml
CLUSTER_TEMPLATE_URL="https://raw.githubusercontent.com/metal3-io/cluster-api-provider-metal3/main/examples/clusterctl-templates/clusterctl-cluster.yaml"
wget -O "${CLUSTER_TEMPLATE}" "${CLUSTER_TEMPLATE_URL}"

# Save a manifest of a BareMetalHost
cat << EOF > /tmp/test-hosts.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: worker-1-bmc-secret
type: Opaque
data:
  username: YWRtaW4=
  password: cGFzc3dvcmQ=
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-1
spec:
  online: true
  bmc:
    address: libvirt://192.168.122.1:6233/
    credentialsName: worker-1-bmc-secret
  bootMACAddress: "00:60:2F:10:E9:A7"
EOF

# Save a kubeadm config template
cat << EOF > /tmp/kubeadm-config-template.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  certSANs:
    - localhost
    - 127.0.0.1
    - 0.0.0.0
    - HOST
clusterName: test
controlPlaneEndpoint: HOST:6443
etcd:
  local:
    serverCertSANs:
      - etcd-server.etcd-system.svc.cluster.local
    peerCertSANs:
      - etcd-0.etcd.etcd-system.svc.cluster.local
kubernetesVersion: v1.25.3
certificatesDir: /tmp/CLUSTER/pki
EOF
```

With this we have enough to start creating the workload cluster.
First, we need to set up some certificates.
This should look very familiar from earlier when we created certificates for the Kubernetes API server and etcd.

```bash
mkdir -p /tmp/pki/etcd
CLUSTER="test"
NAMESPACE=etcd-system
CLUSTER_APIENDPOINT_HOST="test-kube-apiserver.${NAMESPACE}.svc.cluster.local"

sed -e "s/NAMESPACE/${NAMESPACE}/g" -e "s/\/CLUSTER//g" -e "s/HOST/${CLUSTER_APIENDPOINT_HOST}/g" \
  /tmp/kubeadm-config-template.yaml > "/tmp/kubeadm-config-${CLUSTER}.yaml"

# Generate CA certificates
kubeadm init phase certs etcd-ca --config "/tmp/kubeadm-config-${CLUSTER}.yaml"
kubeadm init phase certs ca --config "/tmp/kubeadm-config-${CLUSTER}.yaml"
# Generate etcd peer and server certificates
kubeadm init phase certs etcd-peer --config "/tmp/kubeadm-config-${CLUSTER}.yaml"
kubeadm init phase certs etcd-server --config "/tmp/kubeadm-config-${CLUSTER}.yaml"
```

Next, we create the namespace, the BareMetalHost and secrets from the certificates:

```bash
CLUSTER=test-1
NAMESPACE=test-1
kubectl create namespace "${NAMESPACE}"
kubectl -n "${NAMESPACE}" apply -f /tmp/test-hosts.yaml
kubectl -n "${NAMESPACE}" create secret tls "${CLUSTER}-etcd" --cert /tmp/pki/etcd/ca.crt --key /tmp/pki/etcd/ca.key
kubectl -n "${NAMESPACE}" create secret tls "${CLUSTER}-ca" --cert /tmp/pki/ca.crt --key /tmp/pki/ca.key
```

We are now ready to create the cluster!
We just need a few variables for the template.
The important part here is the `CLUSTER_APIENDPOINT_HOST` and `CLUSTER_APIENDPOINT_PORT`, since this will be used by the controllers to connect to the workload cluster API.
You should set the IP to the private IP of the test machine or similar.
This way we can use port-forwarding to expose the API on this IP, which the controllers can then reach.
The port just have to be one not in use, and preferably something that is easy to remember and associate with the correct cluster.
For example, cluster 1 gets port 10001, cluster 2 gets 10002, etc.

```bash
export IMAGE_CHECKSUM="97830b21ed272a3d854615beb54cf004"
export IMAGE_CHECKSUM_TYPE="md5"
export IMAGE_FORMAT="raw"
export IMAGE_URL="http://172.22.0.1/images/rhcos-ootpa-latest.qcow2"
export KUBERNETES_VERSION="v1.25.3"
export WORKERS_KUBEADM_EXTRA_CONFIG=""
export CLUSTER_APIENDPOINT_HOST="172.17.0.2"
export CLUSTER_APIENDPOINT_PORT="10001"
export CTLPLANE_KUBEADM_EXTRA_CONFIG="
    clusterConfiguration:
      controlPlaneEndpoint: ${CLUSTER_APIENDPOINT_HOST}:${CLUSTER_APIENDPOINT_PORT}
      apiServer:
        certSANs:
        - localhost
        - 127.0.0.1
        - 0.0.0.0
        - ${CLUSTER_APIENDPOINT_HOST}
      etcd:
        external:
          endpoints:
            - https://etcd-server:2379
          caFile: /etc/kubernetes/pki/etcd/ca.crt
          certFile: /etc/kubernetes/pki/apiserver-etcd-client.crt
          keyFile: /etc/kubernetes/pki/apiserver-etcd-client.key"
```

Create the cluster!

```bash
clusterctl generate cluster "${CLUSTER}" \
    --from "${CLUSTER_TEMPLATE}" \
    --target-namespace "${NAMESPACE}" | kubectl apply -f -
```

This will give you a cluster and all the templates and other resources that are needed.
However, we will need to fill in for the non-existent hardware and create the workload cluster API server, like we practiced before.
This time it is slightly different, because some of the steps are handled by the Cluster API.
We just need to take care of what would happen on the node, plus the etcd part since we are using external etcd configuration.

```bash
mkdir -p "/tmp/${CLUSTER}/pki/etcd"

# Generate etcd client certificate
openssl req -newkey rsa:2048 -nodes -subj "/CN=${CLUSTER}" \
 -keyout "/tmp/${CLUSTER}/pki/apiserver-etcd-client.key" -out "/tmp/${CLUSTER}/pki/apiserver-etcd-client.csr"
openssl x509 -req -in "/tmp/${CLUSTER}/pki/apiserver-etcd-client.csr" \
  -CA /tmp/pki/etcd/ca.crt -CAkey /tmp/pki/etcd/ca.key -CAcreateserial \
  -out "/tmp/${CLUSTER}/pki/apiserver-etcd-client.crt" -days 365

# Get the k8s ca certificate and key.
# This is used by kubeadm to generate the api server certificates
kubectl -n "${NAMESPACE}" get secrets "${CLUSTER}-ca" -o jsonpath="{.data.tls\.crt}" | base64 -d > "/tmp/${CLUSTER}/pki/ca.crt"
kubectl -n "${NAMESPACE}" get secrets "${CLUSTER}-ca" -o jsonpath="{.data.tls\.key}" | base64 -d > "/tmp/${CLUSTER}/pki/ca.key"

# Generate certificates
sed -e "s/NAMESPACE/${NAMESPACE}/g" -e "s/CLUSTER/${CLUSTER}/g" -e "s/HOST/${CLUSTER_APIENDPOINT_HOST}/g" \
  /tmp/kubeadm-config-template.yaml > "/tmp/kubeadm-config-${CLUSTER}.yaml"
kubeadm init phase certs apiserver --config "/tmp/kubeadm-config-${CLUSTER}.yaml"

# Create secrets
kubectl -n "${NAMESPACE}" create secret tls "${CLUSTER}-apiserver-etcd-client" --cert "/tmp/${CLUSTER}/pki/apiserver-etcd-client.crt" --key "/tmp/${CLUSTER}/pki/apiserver-etcd-client.key"
kubectl -n "${NAMESPACE}" create secret tls apiserver --cert "/tmp/${CLUSTER}/pki/apiserver.crt" --key "/tmp/${CLUSTER}/pki/apiserver.key"
```

Now we will need to set up the fake cluster resources.
For this we will create a second kind cluster and set up etcd, just like we did before.

```bash
# Note: This will create a kubeconfig context named kind-backing-cluster-1,
# i.e. "kind-" is prefixed to the name.
kind create cluster --name backing-cluster-1

# Setup central etcd
CLUSTER="test"
NAMESPACE=etcd-system
kubectl create namespace "${NAMESPACE}"

# Upload certificates
kubectl -n "${NAMESPACE}" create secret tls "${CLUSTER}-etcd" --cert /tmp/pki/etcd/ca.crt --key /tmp/pki/etcd/ca.key
kubectl -n "${NAMESPACE}" create secret tls etcd-peer --cert /tmp/pki/etcd/peer.crt --key /tmp/pki/etcd/peer.key
kubectl -n "${NAMESPACE}" create secret tls etcd-server --cert /tmp/pki/etcd/server.crt --key /tmp/pki/etcd/server.key

# Deploy ETCD
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/manifests/v2/etcd.yaml \
  | sed "s/CLUSTER/${CLUSTER}/g" | kubectl -n "${NAMESPACE}" apply -f -
kubectl -n etcd-system wait sts/etcd --for=jsonpath="{.status.availableReplicas}"=1

# Create root role
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  role add root
# Create root user
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user add root --new-user-password="rootpw"
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user grant-role root root
# Enable authentication
kubectl -n etcd-system exec etcd-0 -- etcdctl \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  auth enable
```

Switch the context back to the first cluster with `kubectl config use-context kind-kind` so we don't get confused about which is the main cluster.
We will now need to put all the expected certificates for the fake cluster in the `kind-backing-cluster-1` so that they can be used by the API server that we will deploy there.

```bash
CLUSTER=test-1
NAMESPACE=test-1
# Setup fake resources for cluster test-1
kubectl --context=kind-backing-cluster-1 create namespace "${NAMESPACE}"
kubectl --context=kind-backing-cluster-1 -n "${NAMESPACE}" create secret tls "${CLUSTER}-etcd" --cert /tmp/pki/etcd/ca.crt --key /tmp/pki/etcd/ca.key
kubectl --context=kind-backing-cluster-1 -n "${NAMESPACE}" create secret tls "${CLUSTER}-ca" --cert /tmp/pki/ca.crt --key /tmp/pki/ca.key
kubectl --context=kind-backing-cluster-1 -n "${NAMESPACE}" create secret tls "${CLUSTER}-apiserver-etcd-client" --cert "/tmp/${CLUSTER}/pki/apiserver-etcd-client.crt" --key "/tmp/${CLUSTER}/pki/apiserver-etcd-client.key"
kubectl --context=kind-backing-cluster-1 -n "${NAMESPACE}" create secret tls apiserver --cert "/tmp/${CLUSTER}/pki/apiserver.crt" --key "/tmp/${CLUSTER}/pki/apiserver.key"

kubectl -n "${NAMESPACE}" get secrets "${CLUSTER}-sa" -o yaml | kubectl --context=kind-backing-cluster-1 create -f -

## Create etcd tenant
# Create user
kubectl --context=kind-backing-cluster-1 -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user add "${CLUSTER}" --new-user-password="${CLUSTER}"
# Create role
kubectl --context=kind-backing-cluster-1 -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  role add "${CLUSTER}"
# Add read/write permissions for prefix to the role
kubectl --context=kind-backing-cluster-1 -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  role grant-permission "${CLUSTER}" --prefix=true readwrite "/${CLUSTER}/"
# Give the user permissions from the role
kubectl --context=kind-backing-cluster-1 -n etcd-system exec etcd-0 -- etcdctl --user root:rootpw \
  --key=/etc/kubernetes/pki/etcd/tls.key --cert=/etc/kubernetes/pki/etcd/tls.crt --cacert /etc/kubernetes/pki/ca/tls.crt \
  user grant-role "${CLUSTER}" "${CLUSTER}"
```

Check that the Metal3Machine is associated with a BareMetalHost.
Deploy the API server.

```bash
# Deploy API server
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/manifests/v2/kube-apiserver-deployment.yaml |
  sed -e "s/CLUSTER/${CLUSTER}/g" | kubectl --context=kind-backing-cluster-1 -n "${NAMESPACE}" apply -f -
kubectl --context=kind-backing-cluster-1 -n "${NAMESPACE}" wait --for=condition=Available deploy/test-kube-apiserver

# Get kubeconfig
clusterctl -n "${NAMESPACE}" get kubeconfig "${CLUSTER}" > "/tmp/kubeconfig-${CLUSTER}.yaml"
# Edit kubeconfig to point to 127.0.0.1:${CLUSTER_APIENDPOINT_PORT}
sed -i -e "s/${CLUSTER_APIENDPOINT_HOST}/127.0.0.1/" -e "s/:6443/:${CLUSTER_APIENDPOINT_PORT}/" "/tmp/kubeconfig-${CLUSTER}.yaml"
# Port forward for accessing the API
kubectl --context=kind-backing-cluster-1 -n "${NAMESPACE}" port-forward \
      --address "${CLUSTER_APIENDPOINT_HOST},127.0.0.1" svc/test-kube-apiserver "${CLUSTER_APIENDPOINT_PORT}":6443 &
# Check that it is working
kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" cluster-info
```

Now that we have a working API for the workload cluster, the only remaining thing is to put everything that the controllers expect in it.
This includes adding a Node to match the Machine as well as static pods that Cluster API expects to be there.
Let's start with the Node!
The Node must have the correct name and a label with the BareMetalHost UID so that the controllers can put the correct provider ID on it.
We have only created 1 BareMetalHost so it is easy to pick the correct one.
The name of the Node should be the same as the Machine, which is also only a single one.

```bash
machine="$(kubectl -n "${NAMESPACE}" get machine -o jsonpath="{.items[0].metadata.name}")"
bmh_uid="$(kubectl -n "${NAMESPACE}" get bmh -o jsonpath="{.items[0].metadata.uid}")"
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/fake-node.yaml |
  sed -e "s/fake-node/${machine}/g" -e "s/fake-uuid/${bmh_uid}/g" | \
  kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" create -f -
# Label it as control-plane since this is a control-plane node.
kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" label node "${machine}" node-role.kubernetes.io/control-plane=""
# Upload kubeadm config to configmap. This will mark the KCP as initialized.
kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" -n kube-system create cm kubeadm-config \
  --from-file=ClusterConfiguration="/tmp/kubeadm-config-${CLUSTER}.yaml"
```

This should be enough to make the Machines healthy!
You should be able to see something similar to this:

```console
$ clusterctl -n test-1 describe cluster test-1
NAME                                            READY  SEVERITY  REASON  SINCE  MESSAGE
Cluster/test-1                                  True                     46s
├─ClusterInfrastructure - Metal3Cluster/test-1  True                     114m
└─ControlPlane - KubeadmControlPlane/test-1     True                     46s
  └─Machine/test-1-f2nw2                        True                     47s
```

However, if you check the KubeadmControlPlane more carefully, you will notice that it is still complaining about control plane components.
This is because we have not created the static pods yet, and it is also unable to check the certificate expiration date for the Machine.
Let's fix it:

```bash
# Add static pods to make kubeadm control plane manager happy
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-apiserver-pod.yaml |
  sed "s/node-name/${machine}/g" |
  kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" create -f -
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-controller-manager-pod.yaml |
  sed "s/node-name/${machine}/g" |
  kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" create -f -
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-scheduler-pod.yaml |
  sed "s/node-name/${machine}/g" |
  kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" create -f -
# Set status on the pods (it is not added when using create/apply).
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-apiserver-pod-status.yaml |
  kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" -n kube-system patch pod "kube-apiserver-${machine}" \
    --subresource=status --patch-file=/dev/stdin
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-controller-manager-pod-status.yaml |
  kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" -n kube-system patch pod "kube-controller-manager-${machine}" \
    --subresource=status --patch-file=/dev/stdin
curl -L https://github.com/Nordix/metal3-clusterapi-docs/raw/main/metal3-scaling-experiments/kube-scheduler-pod-status.yaml |
  kubectl --kubeconfig="/tmp/kubeconfig-${CLUSTER}.yaml" -n kube-system patch pod "kube-scheduler-${machine}" \
    --subresource=status --patch-file=/dev/stdin

# Add certificate expiry annotations to make kubeadm control plane manager happy
CERT_EXPIRY_ANNOTATION="machine.cluster.x-k8s.io/certificates-expiry"
EXPIRY_TEXT="$(kubectl -n "${NAMESPACE}" get secret apiserver -o jsonpath="{.data.tls\.crt}" | base64 -d | openssl x509 -enddate -noout | cut -d= -f 2)"
EXPIRY="$(date --date="${EXPIRY_TEXT}" --iso-8601=seconds)"
kubectl -n "${NAMESPACE}" annotate machine "${machine}" "${CERT_EXPIRY_ANNOTATION}=${EXPIRY}"
kubectl -n "${NAMESPACE}" annotate kubeadmconfig --all "${CERT_EXPIRY_ANNOTATION}=${EXPIRY}"
```

Now we finally have a completely healthy cluster as far as the controllers are concerned.

## Conclusions and summary

We now have all the tools necessary to start experimenting.

- With the BareMetal Operator running in test mode, we can skip Ironic and still work with BareMetalHosts that act like normal.
- We can set up separate "backing" clusters where we run etcd and multiple API servers to fake the workload cluster API's.
- Fake Nodes and Pods can be easily added to the workload cluster API's, and configured as we want.
- The workload cluster API's can be exposed to the controllers in the test cluster using port-forwarding.

In this post we have not automated all of this, but if you want to see a scripted setup, take a look at [this](https://github.com/Nordix/metal3-clusterapi-docs/tree/main/metal3-scaling-experiments).
It is what we used to scale to 1000 clusters.
Just remember that it may need some tweaking for your specific environment if you want to try it out!

Specifically we used 10 "backing" clusters, i.e. 10 separate cloud VMs with kind clusters where we run etcd and the workload cluster API's.
Each one would hold 100 API servers.
The test cluster was on its own separate VM also running a kind cluster with all the controllers and all the Cluster objects, etc.

In the next and final blog post of this series we will take a look at the results of all this.
What issues did we run into along the way?
How did we fix or work around them?
We will also take a look at what is going on in the community related to this and discuss potential future work in the area.
