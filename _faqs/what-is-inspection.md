---
question: What is inspection? Can I disable it?
---

Inspection is used to populate hardware information in the BareMetalHost
objects. You can [disable it](https://book.metal3.io/bmo/external_inspection),
but you may need to populate this information yourself. Do not blindly
disable inspection if it fails - chances are high the subsequent
operations fail the same way.
