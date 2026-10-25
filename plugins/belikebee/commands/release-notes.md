---
description: Draft BeLikeBee release notes for the commits since the last tag into docs/CHANGELOG.md (suggest mode, no commit).
argument-hint: "[from-ref]"
allowed-tools: Bash(scripts/release-notes.sh:*), Bash(git diff:*)
---

Draft the release notes and leave them in the working tree for the user to review.

1. From the repo root, run exactly `scripts/release-notes.sh $ARGUMENTS` as one Bash call with a 600000 ms timeout: no redirects, pipes, temp files or wrappers, since only that command is pre-approved. Its stdout is the notes JSON, its stderr the progress and errors. With no argument it starts at the last tag (else the first commit). It runs a nested `claude -p` capped at 10 turns, so it takes a minute or two. If the script is missing, say this repo has no release-notes pipeline and stop.
2. If it exits non-zero, show its stderr and stop. Do not edit `docs/CHANGELOG.md` by hand to get past a failed check:
   - 1: unknown ref, or `docs/CHANGELOG.md` missing or already modified;
   - 2: the Claude run failed or ran out of turns without a schema-valid result;
   - 3: the notes do not cover the commits exactly (a commit missing, an unknown hash, or a noted hash absent from the changelog).
3. On success, show `git diff --stat docs/CHANGELOG.md`, the notes summary, and the entries as a table (category, module, text, commits), plus any skipped commits with their reasons.
4. Do not commit or push. Tell the user the next step: review with `git diff docs/CHANGELOG.md`, then commit it (for example with `/belikebee:feature-ship`) or share it as a patch with `git diff > release.patch`.
