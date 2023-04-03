---
title: "Raw image streaming available in Metal3"
date: 2020-07-05
draft: false
categories: ["metal3", "baremetal", "raw image", "image streaming"]
author: Maël Kimmerlin
---

Metal3 supports multiple types of images for deployment, the most
popular being QCOW2. We have recently added support for a feature of Ironic
that improves deployments on constrained environments, raw image streaming.
We'll first dive into how Ironic deploys the images on the target hosts, and
how raw image streaming improves this process. Afterwards, we will point out
the changes to take this into use in Metal3.

## Image deployments with Ironic

In Metal3, the image deployment is performed by the Ironic Python Agent (IPA)
image running on the target host. In order to deploy an image, Ironic will
first boot the target node with an IPA image over iPXE. IPA will run in memory.

Once IPA runs on the target node, Ironic will instruct it to download the
target image. In Metal3, we use HTTP(S) for the download of the image. IPA will
download the image and, depending on the format of the image, prepare it to
write on the disk. This means that the image is downloaded in memory and
decompressed, two steps that can be both time and memory consuming.

In order to improve this process, Ironic implemented a feature called raw image
streaming.

## What is raw image streaming?

The target image format when writing to disk is raw. That's why the images in
formats like QCOW2 must be processed before being written to disk. However, if
the image that is downloaded is already in raw format, then no processing is
needed.

Ironic leverages this, and instead of first downloading the image and then
processing it before writing it to disk, it will directly write the
downloaded image to the disk. This feature is known as image streaming.
Image streaming can only be performed with images in raw format.

Since the downloaded image when streamed is directly written to disk, the
memory size requirements change. For any other format than raw, the target
host needs to have sufficient memory to both run IPA (4GB) and
download the image in memory. However, with raw images, the only constraint
on memory is to run IPA (so 4GB). For example, in order to deploy an Ubuntu
image (around 700MB, QCOW2), the requirement is 8GB when in QCOW2 format, while
it is only 4GB (as for any other image) when streamed as raw. This allows
the deployment of images that are bigger than the available memory on constrained nodes.

However, this shifts the load on the network, since the raw images are usually
much bigger than other formats. Using this feature in network constrained
environment is not recommended.

## Raw image streaming in Metal3

In order to use raw image streaming in Metal3, a couple of steps are needed.
The first one is to convert the image to raw and make it available in an
HTTP server. This can be achieved by running :

```bash
qemu-img convert -O raw "${IMAGE_NAME}" "${IMAGE_RAW_NAME}"
```

Once converted the image format needs to be provided to Ironic through the
BareMetalHost (BMH) image spec field. If not provided, Ironic will assume that
the format is unspecified and download it in memory first.

The following is an example of the BMH image spec field in Metal3 Dev Env.

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
spec:
  image:
    format: raw
    url: http://172.22.0.1/images/bionic-server-cloudimg-amd64-raw.img
    checksum: http://172.22.0.1/images/bionic-server-cloudimg-amd64-raw.img.md5sum
    checksumType: md5
```

If deploying with Cluster API provider Metal3 (CAPM3), CAPM3 takes care of
setting the image field of BMH properly, based on the image field values in
the Metal3Machine (M3M), which might be based on a Metal3MachineTemplate (M3MT).
So in order to use raw image streaming, the format of the image must be
provided in the image spec field of the Metal3Machine or Metal3MachineTemplate.

The following is an example of the M3M image spec field in metal3-dev-env :

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
kind: Metal3Machine
spec:
  image:
    format: raw
    url: http://172.22.0.1/images/bionic-server-cloudimg-amd64-raw.img
    checksum: http://172.22.0.1/images/bionic-server-cloudimg-amd64-raw.img.md5sum
    checksumType: md5
```

The following is for a M3MT in metal3-dev-env :

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha3
kind: Metal3MachineTemplate
spec:
  template:
    spec:
      image:
        format: raw
        url: http://172.22.0.1/images/bionic-server-cloudimg-amd64-raw.img
        checksum: http://172.22.0.1/images/bionic-server-cloudimg-amd64-raw.img.md5sum
        checksumType: md5
```

This will enable raw image streaming. By default, metal3-dev-env uses the raw image
streaming, in order to minimize the resource requirements of the environment.

## In a nutshell

With the addition of raw image streaming, Metal3 now supports a wider range of
hardware, specifically, the memory-constrained nodes and speeds up deployments.
Metal3 still supports all the other formats it supported until now. This new
feature changes the way raw images are deployed for better efficiency.
