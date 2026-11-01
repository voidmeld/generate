# Adapters

An adapter connects Generate to a tool or host. The consumer supplies effects, credentials,
destinations, policy and final acceptance. The [API](api.md) defines the contracts.

| Task | Connection |
| --- | --- |
| Save a reviewed file or native object | [Direct delivery](api.md#direct-delivery) owns one attempt, durable recovery and moderation readback. |
| Declare a destination | [Destinations](api.md#delivery-destinations) bind an intended target; delivery journals retain actual outcomes. |
| Measure or convert audio | [Media](api.md#media) connects process tools. |
| Produce an image | [Image lane](api.md#image-lane) binds recipes, transforms, measurements and one provider attempt. |
| Run a content compiler or DCC tool | [Process tools](api.md#process-tools) bind tool identity and output bytes. |

Native and DCC work uses the consumer's `Host.runStage`. Return artifacts, invocations and
derivations. The consumer selects the tool, task, session and reviewer; Generate binds the resulting
review to exact candidate bytes. Keep native originals under the [retention rules](native-codegen.md).
Technical checks and retained records do not grant content acceptance.
