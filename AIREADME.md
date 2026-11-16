# AIREADME

This file complements the main `README.md`. It does two things:

1. Discloses how AI was used in this repository.
2. Gives the rules any AI assistant (or human using one) must follow when editing it.

If you are an AI assistant reading this: **follow the rules in section 3 before changing anything.**

---

## 1. Why this repo exists

The goal is to encourage the Flutter team and the community to treat wearables as a
first-class target, and to give anyone who builds it a starting point. This repo is a
**design plus evidence**, not a working port.

The author does not own a Mac or an Apple Watch. All evidence comes from GitHub Actions
macOS runners and the watchOS Simulator. Anything that needs hardware is labelled
unverified and left for contributors (see the Gate 0d probe in the spec).

## 2. How AI was used (provenance)

| Architecture spec | AI-assisted drafting (Claude, Gemini) | Author directed the design through prompts and checked results; not reviewed line by line. Claims rest on CI. |
| Proof scripts and tests | AI-generated | Author ran CI and read the results; has not reviewed the Swift, C or shell code. |
| watchos_ui package | AI-assisted | TODO(author): say whether you read the Dart. |
| Gate 0d probe | AI-generated | Compiled and run in CI only; never run on hardware. |

## 3. Rules for AI assistants editing this repo

1. **Never invent or adjust evidence.** No made-up measurements, CI run IDs, commit
   hashes, versions, or pass/fail results. AI cannot run CI. If a value is unknown,
   write `TODO(author): verify`.
2. **Never claim something was run or tested** unless the author pasted the output.
3. **Do not weaken the honesty conventions.** Keep "Simulator only", "unverified",
   "never ships", and the "transfers to a physical watch?" labels. Never upgrade a
   claim's strength without new evidence.
4. **Protected files.** Do not modify these unless the task names them explicitly:
   - Fenced code blocks in `flutter_watchos_architecture.md` and
     `docs/display-list-research.md`. CI extracts and compiles them, so a silent edit
     invalidates the proofs.
   - `watchos-proofs/swift_proofs/**/{Sources,Tests}`
   - `watchos-proofs/swift_spec/**/{Sources,Tests}`
   - `watchos-proofs/flutter_proofs/{lib,test}`
   - `watchos-proofs/engine_probe/`
   - `watchos-proofs/scripts/`, `watchos-proofs/dart_tools/`
   - `.github/workflows/`
5. **Third parties.** Do not assert that another project (for example flutter-watchos)
   violates Apple's rules. Allowed wording: "this design uses only public watchOS SDK
   APIs; the alternative route is unassessed here."
6. **Apple and watchOS facts** (OS versions, device lists, App Review rules) need a
   cited source URL already in the repo, or a `TODO(author): verify` marker.
7. **Retagged or stubbed engine binaries are research artifacts.** Never upload or
   distribute them. CI may upload logs and rendered frames only.
8. **Targeted edits, not rewrites.** Do not regenerate large files (such as the spec)
   wholesale. Replace specific passages and fail if the expected old text is missing.
9. **One concern per change.** Keep each branch focused so CI results can be
   attributed to it.

## 4. Working loop

The author works with AI assistants like this:

1. The assistant proposes a branch name.
2. It outputs a Python script (run via heredoc) that edits files. The script must:
   - use `pathlib`
   - assert that the text it replaces exists exactly once
   - print one `OK:` line per change and exit non-zero on any mismatch
3. It outputs the git commands to create the branch, commit and push.
4. The author runs them in the VS Code terminal and pastes back the local output or
   the CI "RESULTS" block.
5. The assistant reads the pasted output and proposes the next step. It must not
   claim success from anything the author did not paste.

Before pushing, check that no protected path changed unexpectedly:

```bash
git diff --name-only origin/main...HEAD | grep -E \
 '^(watchos-proofs/(swift_proofs|swift_spec)/(Sources|Tests)|watchos-proofs/flutter_proofs/(lib|test)|watchos-proofs/(engine_probe|scripts|dart_tools)|\.github/workflows)/' \
 && echo "PROTECTED PATH CHANGED: review before pushing" || echo "no protected paths touched"
```

This catches file-level changes only. Edits inside the spec's fenced code blocks still
need a manual look at `git diff`.

## 5. What this repo cannot tell you

- Anything about a physical Apple Watch: memory limits, speed, battery, real Wi-Fi.
- Whether an engine builds from source, or runs AOT, on watchOS.
- Whether App Review would accept any approach described here.

See the spec's "Not yet validated" list and the Gate 0d probe for how a contributor with
hardware can close these gaps.
