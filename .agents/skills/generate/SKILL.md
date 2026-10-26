---
name: generate
description: Use this skill to execute or review a declared Generate brief for images, 3D, audio, voice, animation, or structured content. Do not use it for ordinary source changes or publication without a bound external-change grant.
---

# Generate production

The [terms](../../../docs/index.md#terms) define the words of this skill, including `REFUSE` and `HOLD`.

This skill executes or reviews a declared Generate production brief, from the validation of the brief and grant through the review packet.

1. Read the `*.generate.luau` brief and its job or plan envelope. If the brief, capability, destination or authority is missing, stop with `REFUSE`.
2. Use only the declared adapter and route. Preserve the inputs. Return artifacts with content digests, invocation facts, rights facts and transformation history.
3. Measure prepared spatial candidates in world-space bounds. Run the declared technical checks and Verify checks. Submit the review packet for the exact candidate.
4. Run `lute run tools/generate-check.luau <path.generate.luau>` and the assigned technical checks. Run the gate of the consumer once on the final bytes. Do not repeat it for each asset stage. Record HEAD, commands, exit codes, artifact digests and the receipt path.
5. A bound review packet completes preparation. For a review assignment, collect the decision under the [review contract](references/review.md) of the brief. Use `Generate.continueReview` for the unchanged candidate. A pending review is not acceptance. Report its missing decision. Do not repeat production.
6. Enter delivery only if all of these conditions hold:
   - The assigned scope includes delivery.
   - The exact candidate has an accepted receipt for this brief workflow.
   - The consumer supplied the creator, the destination and the authorization.

   Standalone reviewed files and native objects use direct delivery without a core receipt. Follow the [delivery route](references/delivery.md).
   For public visibility, destination selection, scope expansion or an ambiguous retry, stop with `REFUSE`.

Report completion for the assigned stage:

- Preparation returns the bound candidate, the review packet and the provenance.
- Review returns the revision-bound decision and the updated receipt.
- Authorized publication returns its outcome, its readback and the quarantine state.
- A missing prerequisite ends the affected stage at a stated REFUSE or HOLD.

A prepared packet does not establish acceptance. A publication receipt does not establish the runtime acceptance of the consumer.

Read one reference for the route that you use:

- [Adapters and Studio transport](references/adapters.md)
- [Review and provenance](references/review.md)
- [Delivery](references/delivery.md)
