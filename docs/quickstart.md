# Quickstart

Add Generate to your `pkg.luau` at one exact commit of `https://github.com/voidmeld/generate`, run `lute pkg install --vendor` and alias `generate = "./.lpm/generate@<commit>"` in `.config.luau`. Import `@generate/src/core`, `@generate/src/image` or `@generate/src/roblox`.

In a clone of this repository, after `rokit install`, `lute setup` and `lute pkg install --vendor`, run `lute run examples/quickstart.generate.luau` to print a brief-bound plan fingerprint. The [modular wall](../examples/modular-wall.generate.luau) also describes ordered stages. Both are records; consumers supply execution and authority.

Run `lute run examples/image-tools.luau` to measure an artifact and stage a byte-bound review packet, including an unblinding refusal. [Candidate revisions](../examples/candidate-revision.luau) demonstrate review-bound revision history.

The [API](api.md) owns public calls and record contracts. Run `lute run tools/gate.luau --file tests/core.verify.luau` for focused record checks. Keep originals and delivery recovery records under the [retention rules](native-codegen.md).
