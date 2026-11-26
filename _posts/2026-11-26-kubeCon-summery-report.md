---
title: "KubeCon + CloudNativeCon North America 2026: Summary and Key Takeaways"
date: 2026-11-26
draft: false
categories: ["metal3", "kubecon", "conference", "cloud-native"]
author: Moshiur Rahman
---

KubeCon + CloudNativeCon North America 2026 took place in Salt Lake City from
November 9 to 12, following the Cloud Native Computing Foundation (CNCF)
Maintainer Summit on November 8. This post summarizes session highlights and
key takeaways. Sessions highlighted four themes: AI infrastructure, platform
engineering, security, and bare-metal servers.

We would like to acknowledge Jan Melen, Kashif Khan, Tuomo Tanskanen, Faseela
K, and Sunnat Samadov for sharing their session highlights, which contributed
to this report.

## AI is changing infrastructure and software development

Many sessions focused on running AI applications on Kubernetes. These
applications often need GPUs (graphics processing units) and other specialized
hardware. Teams need a reliable way to assign that hardware to the right
applications.

Dynamic Resource Allocation (DRA) was a common topic. DRA is a Kubernetes
feature for requesting and assigning devices such as GPUs. The talks covered
how DRA drivers work, how applications request devices, and how schedulers
(Kubernetes components that select a server for each application) make
placement decisions.

Having enough GPU quota does not guarantee that an application can run: there
must also be a suitable GPU available on a server. The physical connection
between a GPU and a network card can affect data-transfer speed too. KubeVirt,
a project for running virtual machines on Kubernetes, discussed ways to assign
CPUs (central processing units) exclusively or share them between
applications. Other sessions showed how a physical GPU can be divided into
smaller slices and shared by different users.

AI is also changing how software is written and maintained. AI tools can
generate code and identify possible security problems. They also create more
code changes and reports for project maintainers to review. A key message was
that people who submit changes must understand and take responsibility for
them. Human review remains important, especially for security-related changes.

## Metal3 and physical servers

Bare-metal servers are physical machines, rather than virtual machines
running on another server. Metal3 helps Kubernetes provision and manage these
physical servers. Metal3 presentations highlighted several improvements:

- **Multi-tenancy:** HostClaim work is intended to let different teams use a
  shared server pool while keeping server-management passwords private.
- **Rack-aware placement:** Metal3 can spread servers across racks, helping
  reduce disruption if one rack fails.
- **Network automation:** Metal3 can configure top-of-rack (ToR) switch ports
  as servers are added or removed, reducing manual network setup.
- **Server management:** The update covered the Bare Metal Operator (BMO) and
  its API (application programming interface), which lets other software
  interact with it.
- **Boot image delivery:** The Ironic Python Agent (IPA), a small boot
  environment used to prepare a server, can be delivered in the Open Container
  Initiative (OCI) image format.
- **Fuzz testing:** Metal3 presented its adoption of fuzz testing in IPAM
  (IP Address Manager), BMO (Bare Metal Operator), CAPM3 (Cluster API Provider
  Metal3), and IrSo (Ironic Standalone Operator). Fuzz testing automatically
  checks software with generated, unexpected inputs to uncover bugs and edge
  cases. Fuzz tests currently run in a weekly workflow and as part of
  pull-request tests.

The Mistral AI team described building a GPU cloud with open-source projects,
including Metal3, Cluster API (a project for managing Kubernetes clusters),
and Kamaji (a project for hosting Kubernetes control planes). Their
deployment grew to a fleet of about 5,000 GPU nodes. The team shared lessons
from building and operating this infrastructure. This showed how Metal3 can
support a large, real-world cloud. After the conference, vCluster joined the
Metal3 adopter list.

The event also included discussion of fixing security problems in upstream
projects first. “Upstream” means the original open-source project where the
software is developed. The examples included Metal3, Ironic (a bare-metal
provisioning project), and Cluster API. Fixing an issue upstream helps all
users of that project. Maintainers also discussed project governance and
release practices, which help open-source projects grow and build trust.

## Building platforms that help users

Platform engineering is the work of providing shared tools and services that
help development teams build and run applications. Sessions stressed that an
internal platform should be treated like a product. It needs to be easy to
start using, have clear support, and solve real user problems. A dashboard
alone is not enough.

Good onboarding and ongoing support help build trust. Platform teams should
also explain which services they support. An application may be allowed to run
without being officially supported by the platform team, so users need to
understand that difference.

The sessions also covered multi-cluster platforms. These platforms run
applications across several Kubernetes clusters. This can improve resilience,
but it adds complexity for developers. Shared tools and central management
can hide some of that complexity, as long as users are told when a cluster is
unavailable or an operation has only partly completed.

## Improving software and cluster security

Several sessions looked at ways to check software before it is deployed. A
software supply chain includes the code, tools, and steps used to build and
deliver software. Organizations can sign software packages and provide
records of where and how they were built. A software bill of materials (SBOM)
is a list of the components included in a package. Teams can check this
information before allowing an application to run in a cluster.

Some organizations require different evidence in development and production.
They may also use separate signing systems for internal software and public
software. Keeping a record of each decision helps teams understand why a
package was approved or rejected.

The reports highlighted several useful practices:

- Fix security problems in the original upstream project and share relevant
  security advisories.
- Ask contributors to explain their changes and take responsibility for them.
- Check security reports against the project's threat model: the description
  of what the project is designed to protect against.
- Use signed evidence and deployment policies to check software before it
  runs and record why it was allowed.
- Give controllers (Kubernetes components that automate tasks) and AI agents
  only the permissions they need.

Sessions also covered Vulnerability Exploitability eXchange (VEX) documents.
These documents explain whether a known vulnerability affects a particular
product. As AI tools find more potential vulnerabilities, clear reports and
reliable ways to review them are becoming increasingly important.

## Storage, performance, and sustainability

Sessions also covered how Kubernetes stores application data. A storage
volume is a place where an application keeps data, backed by local or remote
storage. New features can show whether a volume is healthy and take snapshots
of several volumes at the same time, which can help with troubleshooting and
backups.

Rook and Ceph are open-source projects for managing storage. Talks covered
erasure coding, a way to protect data while using less disk space than keeping
multiple full copies. They also covered easier disk replacement and automatic
security-key rotation, which regularly replaces keys to reduce risk. A design
for smaller, two-server edge locations was discussed, but it is still
experimental.

Performance sessions shared ways to speed up application startup, including
improving how container images (packages containing an application and its
dependencies) are downloaded and unpacked. Other talks returned to the need
for schedulers to consider the physical layout of hardware.

Sustainability was another topic. OpenTelemetry, a set of tools and standards
for collecting information about software systems, may also help teams record
energy use and carbon estimates. This work is still developing, but it could
make it easier to understand the environmental impact of applications.

## Suggested follow-up

The sessions suggest several areas for further discussion and evaluation:

1. Identify practical ways to use DRA for GPUs, CPUs, and other devices.
1. Continue developing and demonstrating Metal3's multi-tenancy, rack
   awareness, and network automation features.
1. Strengthen security practices, including upstream fixes, clear ownership
   of contributions, and checks for software before deployment.
1. Evaluate storage, performance, multi-cluster, and sustainability
   improvements based on real user needs.

## Conclusion

KubeCon week began with maintainer discussions and continued with sessions on
AI, Kubernetes, platform engineering, security, and storage. Metal3
updates covered ways to support multi-tenant server use, improve rack
resilience, automate network configuration, and find bugs through fuzz testing.
The event was also a chance to meet maintainers and connect with organizations
using Metal3.

A fun fact: the Delta Center, home to the Utah Jazz and Utah Mammoth, was
across the street from our accommodation.

The main takeaway is simple: cloud platforms need reliable hardware, strong
security, and good support for their users. Continued work with the upstream
community can help turn the ideas from KubeCon into practical improvements.
