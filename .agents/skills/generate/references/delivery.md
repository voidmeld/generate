# Delivery

For a reviewed file or a native object, follow [direct delivery](../../../../docs/api.md#direct-delivery).
It provides write-ahead recovery, moderation readback and a stop on the first refusal.
The consumer supplies the creator, destination, transport and authorization.

- A `hold` or `stop` result ends the action.
- An `ambiguous` result needs a reconciled operation or asset identity, and then attach.
- Status alone does not update the stored record.
- For a native attach, resume with save. It reads back the recorded ID without a create.

The consuming product promotes the delivered asset after its own runtime check.
