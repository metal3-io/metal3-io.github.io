---
question: Can I use my own operating system installer with Metal3?
---

You can use the [live ISO workflow](https://book.metal3.io/bmo/live-iso) to attach a bootable ISO to the machine using virtual media. Note that Baremetal Operator will not track the installation process in this case and will consider the host active once the ISO is booted.
