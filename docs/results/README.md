# Archived CI & Hardware Results

GitHub Actions run logs and workflow artifacts (`results-sheet`, `results-*`, `engine-frames`) expire after the repository's retention window (`TODO(author): verify` your GitHub Actions retention setting). Because links to old workflow runs eventually stop working, paste verified result sheets here so measurements stay readable in git.

## How to archive a CI run

1. Open the **`RESULTS — open this job and copy the block`** job in the completed `.github/workflows/proofs.yml` run (or download the **`results-sheet`** artifact from the run summary page).
2. Copy [TEMPLATE.md](TEMPLATE.md) to a dated/commit-labeled file in this folder (for example, `YYYY-MM-DD-<short-sha>.md`) or update [latest.md](latest.md).
3. Fill in the **Run URL**, **Commit**, and **Date**, and paste the unmodified `RESULTS` block (plus `watchos_ui` Linux CI output if triggered). Never edit, round, or synthesize numbers inside a pasted sheet.

## Files

- [latest.md](latest.md) — placeholder for the latest pasted `RESULTS` sheet.
- [TEMPLATE.md](TEMPLATE.md) — template with required provenance fields (`Run URL`, `Commit`, `Date`).
