---
title: "Introducing Baremetal Operator end-to-end test suite"
date: 2024-12-13
draft: false
categories: ["metal3", "cluster API", "provider", "edge"]
author: Lennart Jern
---

In the beginning, there was
[metal3-dev-env](https://github.com/metal3-io/metal3-dev-env). It could set up a
virtualized "baremetal" lab and test all the components together. As Metal3
matured, it grew in complexity and capabilities, with release branches, API
versions, etc. Metal3-dev-env did everything from cloning the repositories and
building the container images, to deploying the controllers and running tests,
on top of setting up the virtual machines and the networks, of course. Needless
to say, it became hard to understand and easy to misuse.

We tried reducing the scope a bit by introducing end to end tests [directly in
the Cluster API provider
Metal3](https://github.com/metal3-io/cluster-api-provider-metal3/tree/main/test)
(CAPM3). However, metal3-dev-env was still very much entangled with CAPM3. It
was at this point that I got tired of trying to gradually fix it and took the
initiative to start from scratch with end to end tests in [Baremetal Operator
(BMO)](https://github.com/metal3-io/baremetal-operator) instead.

Up until that point, we had been testing BMO through CAPM3 and the cluster API
flow. It worked, but it was very inefficient. From the perspective on the
Baremetal Operator, a test could look something like this:

1. Register 5 BareMetalHosts
1. Inspect the 5 BareMetalHosts
1. Provision the 5 BareMetalHosts all with the same image
1. Deprovision 1 BareMetalHost
1. Provision it again with another image
1. Deprovision another BareMetalHost
1. Provision it again with the other image
1. Continue in the same way with the rest of the BareMetalHosts...
1. Deprovision all BareMetalHosts

As you can see, it is very repetitive, constantly doing the same thing again and
again. As a consequence of this and the complexity of metal3-dev-env, it was
quite an effort to thoroughly test something related to BMO code. I was
constantly questioning myself and the test environment. "Is it testing the code
I wrote?" "Is it doing the relevant scenario?" "Is the configuration correct?"

## Baremetal Operator end to end tests are born

Sometimes it is easier to start from scratch, so [this is what we
did](https://github.com/metal3-io/baremetal-operator/pull/1303). The Baremetal
Operator end to end tests started out as a small script that only set up
minikube, some VMs and a baseboard management controller (BMC) emulator. The
goal was simple: do the minimum required to simulate a baremetal lab. From this,
it was quite easy to build a test module that was responsible for deploying the
necessary controllers and running some tests.

Notice the separation of concerns here! The test module expects a baremetal lab
environment to be already existing and the script that sets up the environment
is not involved in anyway with the tests or deployment of the controllers. This
design is deliberate, with a clear goal that the test module should be useful
across multiple environments. It should be possible to run the test suite
against real baremetal labs with multiple different configurations. I am hoping
that we will get a chance next year to try it for real in a baremetal lab.

## How does it work?

The flexibility of the end to end module is possible through a configuration
file. It can be used to configure everything from the image URL and checksum to
the timeout limits. Since Ironic can be deployed in many different ways, it was
also necessary to make this flexible. The user can optionally set up Ironic
before the test, or provide a kustomization that will be applied automatically.
A separate configuration file declares the BMCs that should be used in the
tests.

The [configuration that we use in
CI](https://github.com/metal3-io/baremetal-operator/tree/main/test/e2e/config)
shows how these files look like. As a proof of concept for the flexibility of
the tests, it can be noted that we already have two different configurations.
One for running the tests with Ironic and one for running them with BMO in
fixture mode. The first is the "normal" mode, the latter means that BMO does not
communicate with Ironic at all, it just pretends. While that obviously isn't
useful for any thorough tests, it still provides a quick and light weight test
suite, and ensures that we do not get too attached to one particular
configuration.

The test suite itself is made with Ginkgo and Gomega. Instead of building a long
chain of checks and scenarios we have attempted to do small, isolated tests.
This makes it possible to run multiple in parallel and shorten the test suite
duration, as well as easily identify where exactly errors occur. In order to
accomplish this, we make heavy use of the [status
annotation](https://book.metal3.io/bmo/status_annotation) so that we can skip
inspection when possible.

## Where are we today?

It is already several months since we switched over to the BMO e2e test suite as
the primary, and only required tests for pull requests in the BMO repository. We
run the [end to end test suite as GitHub
workflows](https://github.com/metal3-io/baremetal-operator/blob/main/.github/workflows/e2e-test.yml)
and it covers more than the metal3-dev-env and CAPM3 based tests from BMO
perspective. That does not mean that we are done though. At the time of writing,
there are [several GitHub
issues](https://github.com/orgs/metal3-io/projects/5/views/2) for improving and
extending the tests. The progress has significantly slowed though, as can
perhaps be expected, since the most essentials parts were implemented.

## The future

In the future we hope to make the BMO end to end module and tooling more useful
for local development and testing. It should be easy to spin up a minimal
environment and test specific scenarios, also using Tilt. Additionally, we want
to "rebase" the CAPM3 end to end tests on this work. It should be possible to
reuse the code and tooling for simulating a baremetal lab so that we can get rid
of the entanglement with metal3-dev-env.
