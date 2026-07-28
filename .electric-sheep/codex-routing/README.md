# Governed routing refresh

This directory is fork-maintenance material. It is intentionally separate from the upstream-ready
source branch and must not be included in an OpenAI pull request.

## Branch roles

- `governed-handoff-contract-20260728`: source patch only; candidate for upstream review.
- `governed-routing-maintenance-20260728`: source patch plus this refresh operator surface.
- `openai/codex:main`: upstream base and compatibility authority.

The refresh helper is fail-closed. It verifies source alignment, patch invariants, focused tests, and
an optional debug build. It never rebases, pushes, installs, edits live configuration, restarts
ChatGPT, or replaces an app binary.

## Check the current candidate

Run from any clean worktree containing both branch refs:

```sh
.electric-sheep/codex-routing/refresh.sh check \
  --repo /absolute/path/to/codex-worktree \
  --patch-branch governed-handoff-contract-20260728
```

If upstream moved, the helper exits with status 3 and prints the exact upstream, patch, and merge-base
SHAs. Create a new disposable worktree from the source patch branch, rebase there onto the fetched
`origin/main`, resolve deliberately, and rerun `check`. Do not force-push the last-known-good branch;
publish a new dated candidate branch first.

## Focused validation and build

```sh
.electric-sheep/codex-routing/refresh.sh test \
  --repo /absolute/path/to/codex-worktree \
  --patch-branch governed-handoff-contract-20260728

.electric-sheep/codex-routing/refresh.sh build \
  --repo /absolute/path/to/codex-worktree \
  --patch-branch governed-handoff-contract-20260728
```

The `build` mode prints the exact debug binary path and SHA-256. A successful build is not Desktop,
release, or production proof.

## Promotion gates

1. Preserve the old source branch, binary checksum, live config backup, and launcher rollback.
2. Run `check`, then the focused `test` mode on the rebased candidate.
3. Build the candidate and record its source SHA and binary SHA-256.
4. Run the isolated CLI hierarchy proof.
5. Run the purple-app Desktop canary against an isolated Codex home and Electron profile.
6. Verify exact root/depth-1/depth-2 model and effort from local state, not agent self-report.
7. Verify max depth, leaf tool removal, no project/skill inheritance at the leaf, communication relay,
   and exact-hash destructive escalation.
8. Only after those gates pass, perform a separately approved live-profile cutover.

## Rollback

The production launcher must preserve the signed ChatGPT app bundle. Rollback means stopping only the
governed launcher process, restoring the backed-up live config, clearing its launch-environment
overrides, and reopening the official app normally. Never patch or re-sign the official app bundle.

Once upstream ships equivalent behavior, remove the custom runtime and return to the bundled Codex
after an isolated compatibility canary.
