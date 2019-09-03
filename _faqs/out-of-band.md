---
question: What is out-of-band management controller?
---
Enterprise hardware usually have an integrated or optional controller that allows to reach the server even if it's powered down, either via dedicated or shared nic. This controller allows some checks on the server hardware and also perform some settings like changing power status, changing Boot Order, etc. The Baremetal Operator uses it to power on, reboot and provision the physical servers to be used for running workloads on top. Commercial names include `iDrac`, `iLO`, `iRMC`, etc and most of them should support `IPMI`.
