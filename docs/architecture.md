# Architecture

Generate owns deterministic asset records, image preparation and Roblox delivery. Consumers own execution, providers, authored-brief policy, credentials, rights policy and final acceptance.

| Boundary | Responsibility |
| --- | --- |
| `src/core` | Briefs, plans, review and provenance bindings, receipts, manifests, destinations and revision records. |
| `src/image` | The PNG codec, the pixel codec interface, measurement, deterministic resizing, metrics and blind review staging. |
| `src/roblox` | Reviewed file/native delivery, destinations, readback, permissions, auditing and binary model reading. |

Core imports no provider, filesystem, engine or scene framework. `tools/check-boundary.luau` enforces this rule.
Canonical `gen-fp2` fingerprints bind records; SHA-256 digests bind artifact bytes. Neither establishes truth, rights or authority.

Receipts retain execution, compensation and checkpoint data without an executor implementation. A manifest is data selected from an unchanged accepted receipt. Consumers retain originals and verify their own runtime acceptance. [The API](api.md) owns public contracts.
