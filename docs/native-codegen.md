# Native tools and retention

Use a native or external process when Lute or the host lacks a required capability, such as geometry processing, codecs, audio transforms or rigging.
Record its version, inputs, output digest, rights and security boundary.
If you make a performance claim, measure performance.
Keep brief validation, planning, lineage and recovery records in Luau.

## Roblox instance serialization

Choose the retention route for the actual content and destination:

| Need | Route | Required readback |
| --- | --- | --- |
| Local bytes for authored Instances | Engine serialization | Exact file bytes and, when supported, an engine round trip. |
| Durable generated Model, including Opaque references | [Direct native save](api.md#native-objects) | Returned asset and version, loaded Model and complete dependency closure. |
| Local recoverable generated geometry and textures | Export a source bundle through supported engine operations | Rebuild from the retained geometry and texture bytes and compare the result. |

A serialized Instance can keep its shell, size and properties and still lose Opaque mesh or texture content.
A parseable file or an unchanged size therefore does not prove geometry retention.

A direct native Model save is supported. A native create does not need a local geometry export first.
The consumer must bind the exact approved object. The consumer must perform the required inspection and readback under the [delivery contract](api.md#native-objects).
The adapter does not enforce a byte binding.

Keep the live original until you verify the chosen retention route.
If retention fails, keep the candidate staged and report the missing proof.
A prompt, a regeneration recipe or a metadata digest cannot reproduce or preserve the exact candidate.
Do not regenerate to repair a missing export.

## Retain local authored Instances

Use the engine's [`SerializationService:SerializeInstancesAsync`](https://create.roblox.com/docs/reference/engine/classes/SerializationService#SerializeInstancesAsync) in the context that the consumer grants:

1. Serialize the original Instances.
2. Encode the buffer for transport with [`EncodingService:Base64Encode`](https://create.roblox.com/docs/reference/engine/classes/EncodingService#Base64Encode). Then decode it to disk.
3. Hash the file and read it again. Before you release the originals, verify that its bytes match the decoded output.
4. If the context and the transport limits support it, deserialize the same buffer with [`SerializationService:DeserializeInstancesAsync`](https://create.roblox.com/docs/reference/engine/classes/SerializationService#DeserializeInstancesAsync). Compare the hierarchy, child order, readable properties, attributes, tags and numeric values. Destroy only the temporary readback Instances.

Record the input identity, the engine and host versions, the encoded and disk digests, the byte count, the comparison result, the cleanup and the fields that nobody can observe.
[Native transcripts](api.md#native-transcripts) keep bound Studio calls and captures. They do not preserve geometry, unless those calls export it.

If serialization is unavailable in an authorized context, a local serializer can produce a provisional reconstruction from the observed properties.
Record the omitted fields. Require an engine reimport and readback before you claim equivalence.
A denial or an ambiguous capability stops that attempt. It grants no alternate route around the refusal.

Local retention does not prove animation playback, durable publication, permissions, moderation or consumer acceptance.
For those claims, follow [direct delivery](api.md#direct-delivery).
