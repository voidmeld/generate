# Adapters

Adapters declare capabilities, tool versions, artifact digests, invocation facts, rights and compensation.
The consumer supplies every effect and destination. See [API](api.md) for the entry points.

## Host tools

Use `Host.runStage` for native and DCC work. Return the exact artifacts, invocations and derivations.
The host owns route selection and task binding.
`src/agent` handles reviewer configuration and independent streams. It does not schedule jobs and does not select a mutable native session.

## Roblox Studio transcripts

`Roblox.nativeTranscript` binds declared `execute_luau` and `screen_capture` calls to one artifact digest and one Studio.
The consumer owns the session and the transport.
The [transcript API](api.md#native-transcripts) defines one-attempt execution, retained bytes and verification.
A transcript records calls. It does not preserve geometry by itself.
To choose retention, use [the native retention guide](native-codegen.md#roblox-instance-serialization).

## Publication records

An adapter owns the meaning of a destination descriptor and of the `facts` of a publication record.
`Roblox.publicationRecord` is the Roblox adapter. It validates the Roblox descriptor and facts, maps Roblox identities onto the generic host verification request, and runs the Roblox transition checks before each core call.
See [publication records](api.md#delivery-destination-and-publication-records).

## Asset publication

`Roblox.assetPublication` publishes one planned asset through the Assets API under a grant, with readback and rollback data.
See [asset publication](api.md#asset-publication).

## Direct delivery and media

To deliver a reviewed file or a native object, use [direct delivery](api.md#direct-delivery). It needs no brief and no receipt.
The consumer supplies the creator, destination, transport, authentication, review and durable record store.
The [delivery contract](api.md#direct-delivery) owns attempt recovery and the consumer obligations for authorization and native identity.
[Media adapters](api.md#media) measure, convert and render review images through the process facility.

## Structured content

`Content.compile` invokes a compiler that the consumer supplies, with an explicit source, schema and tool version.
Core verifies its declared artifact and review lineage. Compilation alone grants no acceptance.

## Images

`src/image` binds recipe stages, deterministic transforms, measured gates and one provider attempt.
It keeps reference bytes read-only, refuses path and script drift, and assembles blind packets.
The consumer supplies every threshold, every look, every transform parameter, prompts, codecs and commands. Generate supplies measurements and generic checks. A technical pass does not approve taste.
