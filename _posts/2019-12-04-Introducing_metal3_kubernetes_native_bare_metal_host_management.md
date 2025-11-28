---
title: "Introducing Metal³: Kubernetes Native Bare Metal Host Management - Russell Bryant & Doug Hellmann, Red Hat - KubeCon NA, November 2019"
date: 2019-12-04T12:09:00+02:00
draft: false
categories: ["hybrid", "cloud", "metal3", "baremetal", "kubecon", "edge"]
author: Pedro Ibáñez Requena
---

## Conference talk: Introducing Metal³: Kubernetes Native Bare Metal Host Management - Russell Bryant & Doug Hellmann, Red Hat

Metal³ (`metal cubed/Kube`) is a new open-source bare metal host provisioning tool created to enable Kubernetes-native infrastructure management. Metal³ enables the management of bare metal hosts via custom resources managed through the Kubernetes API as well as the monitoring of bare metal host metrics to Prometheus. This presentation will explain the motivations behind creating the project and what has been accomplished so far. This will be followed by an architectural overview and description of the Custom Resource Definitions (CRDs) for describing bare metal hosts, leading to a demonstration of using Metal³ in a Kubernetes cluster.

In this video, Russell Bryant and Doug Hellmann speak about the what's and how's of Metal³, a new tool that enables the management of bare metal hosts via custom resources managed through the Kubernetes API.

<!-- markdownlint-disable no-inline-html -->

<iframe width="560" height="315" style="height: 315px" src="https://www.youtube.com/embed/KIIkVD7gujY" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

<!-- markdownlint-enable no-inline-html -->

## Speakers

[Russell Bryant](http://russellbryant.net/) Russell Bryant is a Distinguished Engineer at Red Hat, where he works on infrastructure management to support Kubernetes clusters. Prior to working on the Metal³ project, Russell worked on other open infrastructure projects. Russell worked in Software Defined Networking with Open vSwitch (OVS) and Open Virtual Network (OVN) and worked on various parts of OpenStack. Russell also worked in open source telephony via the Asterisk project.

[Doug Hellmann](http://twitter.com/doughellmann) Doug Hellmann is a Senior Principal Software Engineer at Red Hat. He has been a professional developer since the mid-1990s and has worked on a variety of projects in fields such as mapping, medical news publishing, banking, data centre automation, and hardware provisioning. He has been contributing to open-source projects for most of his career and for the past 7 years he has been focusing on open-source cloud computing technologies, including OpenStack and Kubernetes.

## References

- [Presentation: Introducing Metal³ KubeCon NA 2019 PDF](https://static.sched.com/hosted_files/kccncna19/b3/Introducing%20Metal3%20KubeCon%20NA%202019.pdf)
- [Video: Introducing Metal³: Kubernetes Native Bare Metal Host Management video](https://www.youtube.com/watch?v=KIIkVD7gujY&feature=emb_logo)

## Demos

<!-- cSpell:ignore asciicast -->

- [First demo (Inspection)](https://asciinema.org/a/283704)

[![asciicast](https://asciinema.org/a/283704.svg)](https://asciinema.org/a/283704)

- [Second demo (Provisioning)](https://asciinema.org/a/283705)

[![asciicast](https://asciinema.org/a/283705.svg)](https://asciinema.org/a/283705)

- [Third demo (Scale up)](https://asciinema.org/a/283706)

[![asciicast](https://asciinema.org/a/283706.svg)](https://asciinema.org/a/283706)

- [Fourth demo (v1alpha2)](https://asciinema.org/a/283707)

[![asciicast](https://asciinema.org/a/283707.svg)](https://asciinema.org/a/283707)
