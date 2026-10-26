# Native tools and retention

Use an external process when Lute or the host lacks a required capability.
Examples include geometry processing, codecs, audio transforms and rigging.
Record the tool version, inputs, output digest, rights and security boundary.
Measure performance before you make a performance claim.
Keep brief validation, planning, lineage and recovery records in Luau.

## Roblox instance serialization

Select the retention route for the content and destination:

| Need | Route | Required readback |
| --- | --- | --- |
| Local bytes for authored Instances | Engine serialization | Exact file bytes. Use an engine round trip when supported. |
| Durable generated Model with Opaque references | [Direct native save](api.md#native-objects) | Returned asset and version, loaded Model and complete dependency closure. |
| Local recovery of generated geometry and textures | Export a source bundle through supported engine operations | Rebuild from retained geometry and texture bytes. Compare the result. |

A serialized Instance can keep its shell, size and properties but lose Opaque mesh or texture content.
A file that parses or has unchanged size does not prove geometry retention.

Direct native Model saves are supported. A native create does not need a local geometry export first.
Bind the exact approved object. Complete inspection and readback under the [delivery contract](api.md#native-objects).
The adapter does not enforce a byte binding.

Keep the live original until you verify retention.
If retention fails, keep the candidate staged. Report the missing proof.
A prompt, recipe or metadata digest cannot preserve the exact candidate.
Do not generate again to repair a missing export.

## Retain local authored Instances

Use the engine operations in a context that the consumer authorizes:

1. Serialize original Instances with [SerializeInstancesAsync](https://create.roblox.com/docs/reference/engine/classes/SerializationService#SerializeInstancesAsync).
2. Encode the buffer for transport with [Base64Encode](https://create.roblox.com/docs/reference/engine/classes/EncodingService#Base64Encode).
3. Decode the buffer to disk.
4. Hash the file.
5. Read the file again.
6. Verify that the file bytes match the decoded output before you release originals.
7. If context and transport limits permit, deserialize the buffer with [DeserializeInstancesAsync](https://create.roblox.com/docs/reference/engine/classes/SerializationService#DeserializeInstancesAsync).
8. Compare hierarchy, child order, readable properties, attributes, tags and numeric values.
9. Destroy only the temporary readback Instances.

Record the input identity and engine and host versions.
Record the encoded and disk digests, byte count, comparison result and cleanup.
List fields that you cannot observe.
[Native transcripts](api.md#native-transcripts) keep bound Studio calls and captures.
They preserve geometry only if their calls export it.

If authorized serialization is unavailable, a local serializer can reconstruct observed properties for later verification.
Record omitted fields. Require an engine reimport and readback before you claim an equivalent result.
A denial or an ambiguous capability stops the attempt. It grants no alternate route around the refusal.

Local retention does not prove animation playback, publication, permissions, moderation or acceptance.
For those claims, use [direct delivery](api.md#direct-delivery).
