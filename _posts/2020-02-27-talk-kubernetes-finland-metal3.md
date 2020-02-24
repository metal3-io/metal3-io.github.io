---
title: "Metal³: Kubernetes Native Bare Metal Cluster Management - Maël Kimmerlin - Kubernetes and CNCF Finland Meetup"
date: 2020-02-27
draft: false
categories: ["metal3", "baremetal", "talk", "conference", "kubernetes", "meetup"]
author: Alberto Losada
---

## Conference talk: Metal³: Kubernetes Native Bare Metal Cluster Management - Maël Kimmerlin

On the 20th of January at the [Kubernetes and CNCF Finland Meetup](https://www.meetup.com/Kubernetes-Finland/), Maël Kimmerlin gave a brilliant presentation about the status of the Metal³ project. 

In this presentation, Maël starts giving a short introduction of the [Cluster API project](https://github.com/kubernetes-sigs/cluster-api) which provides a solid foundation to develop the Metal³ Bare Metal Operator (BMO). The talk basically focuses on the **v1alpha2** infrastructure provider features from the Cluster API. 


> info "Information"
> The video recording from the “Kubernetes and CNFC Finland Meetup” is composed by three talks. The video embedded starts with Maël’s talk.

> warning "Warning"
> Playback of the video has been disabled by the author. Click on play button and then on "Watch this video on Youtube" link once it appears.

<iframe width="1110" height="720" style="height: 500px" src="https://www.youtube.com/embed/3k5EfIQpw-E?t=4167" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

<br>

During the first part of the presentation, a detailed explanation of the different Kubernetes Custom Resource Definitions (CRDs) inside Metal³ is shown and also how they are linked with the Cluster API project. As an example, the image below shows the interaction between objects and controllers from both projects:

![crd v1alpha2](/assets/2020-02-27-talk-kubernetes-finland-metal3/metal3-crds-controllers.resized.png)

Once finished the introductory part, Maël focuses on the main components of the Metal³ BMO and the provisioning process. This process starts with **introspection**, where the bare metal server is registered by the operator. Then, the [Ironic Python Agent](https://docs.openstack.org/ironic-python-agent/latest/) (IPA) image is executed to collect all hardware information from the server.

![metal3 introspection](/assets/2020-02-27-talk-kubernetes-finland-metal3/metal3-instrospection.resized.png)

<br>
The second part of the process is the **provisioning**. In this step, Maël explains how the Bare Metal Operator (BMO) is in charge along with Ironic to present the Operating System image to the physical server and complete its installation.

![metal3 provisioning](/assets/2020-02-27-talk-kubernetes-finland-metal3/metal3-provisioning.resized.png)

<br>
Next, Maël deeply explains each Custom Resource (CR) used during the provisioning of target Kubernetes clusters in bare metal servers. He refers to objects such as `Cluster`, `BareMetalCluster`, `Machine`, `BareMetalMachine`, `BareMetalHost` and so on. Each one is clarified with a YAML file definition of a real case and a workflow diagram that shows the reconciliation procedure.

Last part of the talk is dedicated to execute a demo where Maël creates a *target Kubernetes cluster* from a running minikube VM (also called *bootstrap cluster*) where Metal³ is deployed. As it is pointed out in the video, the demo is running in *emulated hardware*. Actually, something similar to the [metal3-dev-env](https://github.com/metal3-io/metal3-dev-env) project which can be used to reproduce the demo. More information of the Metal³ development environment (metal3-dev-env) can be found in the [Metal³ try-it section](https://metal3.io/try-it.html). In case you want to go deeper, take a look at the blog post [A detailed walkthrough of the Metal³ development environment]({%post_url 2020-02-18-metal3-dev-env-install-deep-dive %}).

At the end, the result is a new Kubernetes cluster up and running. The cluster is deployed on two emulated physical servers: one runs as the control-plane node and the other as a worker node.

> info "Information"
> The slides of the talk can be downloaded from [here](https://drive.google.com/open?id=1mdofzqIpH7XpFYkjB0ZC7EWU_RGW6aOl)

## Speakers

[Maël Kimmerlin](https://www.linkedin.com/in/maelkimmerlin/) Maël Kimmerlin is a Senior Software Engineer at Ericsson. In his own words:

*I am an open-source enthusiast, focusing in Ericsson on Life Cycle Management of Kubernetes clusters on Bare Metal. I am very interested in the Cluster API project from the Kubernetes Lifecycle SIG, and active in its Bare Metal provider, that is Metal³, developing and encouraging the adoption of this project.*

## References

* [Video: Metal³: Kubernetes Native Bare Metal Cluster Management](https://youtu.be/3k5EfIQpw-E?t=4167)
* [Slides](https://drive.google.com/open?id=1mdofzqIpH7XpFYkjB0ZC7EWU_RGW6aOl)
