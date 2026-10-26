# Adapters

An adapter connects Generate to a tool or host.
It declares capabilities, tool versions, artifact digests, calls, rights and recovery.
The consumer supplies effects and destinations.
The [API](api.md) defines the calls and their contracts.

| Task | Connection |
| --- | --- |
| Record a delivery outcome | [Publication records](api.md#delivery-destination-and-publication-records) validate destination facts. Each adapter owns its descriptor. |
| Publish a planned asset | [Asset publication](api.md#asset-publication) uses a grant, readback and rollback data. |
| Deliver a reviewed file or native object | [Direct delivery](api.md#direct-delivery) uses consumer review, authority and a durable store. |
| Measure or convert audio | [Media](api.md#media) connects process tools. |
| Produce an image | [Image lane](api.md#image-lane) binds recipes, transforms, measurements and one provider attempt. |

Keep native originals under the [retention rules](native-codegen.md).
A transcript alone does not preserve geometry.
Compilation and technical checks do not grant acceptance.
The consumer supplies image thresholds, transform parameters, prompts, codecs and commands.

## Host tools

Use `Host.runStage` for native and DCC work.
Return artifacts, calls and derivations. The host selects the route and task.
`src/agent` connects configured reviewers and independent streams. The consumer schedules jobs.

## Roblox Studio transcripts

Use [native transcripts](api.md#native-transcripts) to retain Studio calls and captures.
The consumer supplies the session and transport.

## Structured content

Use [Content.compile](api.md#content-process-and-reviewer-adapters) to bind a consumer compiler.
Supply the source, schema and tool version.
