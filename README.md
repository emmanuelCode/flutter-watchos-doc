# Flutter for watchOS Architecture
### A Proposal Design Document 

## What This Is
A design proposal for watchOS as a Flutter platform target, not a working implementation. You can read my dev.to article [here](https://dev.to/emmanuel_code/analysis-flutter-on-watchos-4kc9-temp-slug-341273?preview=f525320a5c61f7ae9ba6ea84fa2e10a1faa8f7fd0805dea4120a16bad9c4c9917a90ba9d009c4212d23dca06b814f023d6dd5c2caa8d784cf437dd54) to learn more. The document is mostly made by AI with my own idea thrown in but mistake or error could still be in there. 

## Goal
To encourage the community and the Flutter team to treat wearables as a first-class target, and to give anyone who does build it a starting point.

## Proof of Concept 
A implementation exist ([flutter-watchos](https://flutterwatch.dev/)) while making this doc but it's takes a different approach (the engine runs on the watch), the two approach are complementary, not competing. The ones I’d highlight are the watchos_ui widget catalog, the constraint validator, and hot reload on a physical watch, since those don’t depend on the rendering approach. Keep in mind, that flutter-watchos engine is closed source and more private.

## Tests (work in progress)
I've written tests (watchos-proofs folder) to prove the concepts from the design document by using Github Action CI runner, as time of writting only dev mode with hot reload parts have proof that this works. 

## Reuse
Anyone may fork or adapt it, The MVP and the phases sections are examples of how one could implement it and not a commitment. If you do make use of this specification, it would be insteresting to mention this repo as a original source.
