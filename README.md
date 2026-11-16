# Flutter for watchOS Architecture
### A Proposal Design Document 

## What This Is
A design proposal for watchOS as a Flutter platform target, not a working implementation. You can read my dev.to article [here](https://dev.to/emmanuel_code/stress-testing-an-ai-designed-architecture-for-flutter-on-watchos-experiment-47pb) to learn more. The document is mostly made by AI with my own idea thrown in but mistake or error could still be in there. Also there might be some tidy up todo in some places but it should be robust enough for any flutter engineers or flutter community member to review it and pick it up to continue the research. 

## Goal
To encourage the community and the Flutter team to treat wearables as a first-class target, and to give anyone who does build it a starting point.

## Proof of Concept 
A implementation exist ([flutter-watchos](https://flutterwatch.dev/)) while making this doc but it's takes a different approach (the engine runs on the watch), the two approach are complementary, not competing. The ones I’d highlight are the `watchos_ui` widget catalog, the constraint validator, and hot reload on a physical watch, since those don’t depend on the rendering approach. Keep in mind, that flutter-watchos engine is closed source and more private.

## Tests
I've written automated CI tests to prove the concepts from the design document on GitHub Actions macOS runners with the watchOS Simulator. As of now, 34 tests prove both the development mode loop (headless capture, streaming, tap injection) and the engine path (official engine running in a watchOS process, executing Dart, text shaping, interactive touch input via `FlutterEngineSendPointerEvent`, and Mach memory measurement) along with 14 test passing for the `watchos_ui` proof of concept sample. You can view the full test catalog — [watchOS proofs](watchos-proofs/README.md).

## Reuse
Anyone may fork or adapt it, The MVP and the phases sections are examples of how one could implement it and not a commitment. If you do make use of this specification, it would be insteresting to mention this repo as a original source.
