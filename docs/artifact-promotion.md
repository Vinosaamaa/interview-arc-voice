# Voice Artifact Promotion

The Voice workflow preserves required pull-request validation while avoiding a
second compilation when merged `main` is byte-for-byte the same Git tree that
the PR workflow tested and packaged.

## Pull request

Agents iterate locally and push the ready branch once. The PR workflow runs the
public-safety audit, promotion-policy regression, Swift tests, signing-policy
test, and package build. It writes `dist/artifact-provenance.json` with:

- schema version;
- immutable source commit;
- immutable source Git tree;
- source GitHub Actions run ID; and
- workflow event.

Before upload, the workflow places the signed application in
`Interview-Arc-Voice.app.tar.gz`, verifies that both packaged executables are
still executable after a clean extraction, and removes the unpacked `.app`
from `dist`. GitHub Actions normalizes permissions on unpacked files; the
archive is therefore the canonical install payload. The uploaded artifact name
includes the Git tree and is retained for 14 days.

## Merged main

The `main` workflow computes its own Git tree and queries repository artifacts
for the exact tree-derived name. Candidates are checked newest-first, but a
failed or cancelled newer run cannot hide an older successful artifact for the
same tree. It promotes an artifact only when all of these
conditions hold:

1. the artifact is not expired;
2. its source workflow was a successful `pull_request` run;
3. the downloaded provenance schema is supported; and
4. the embedded source tree exactly equals merged `main`.

Both the PR and fallback build invoke one canonical composite action for the
public-safety audit, policy regression, Swift tests, signing check, and package
build, preventing the two release paths from drifting. The PR number, branch,
source commit, and merge strategy are never sufficient
evidence. If no artifact passes every check, the workflow runs the complete
test and packaging path on merged `main`.

Promotion reuses the exact tested app archive bytes. The main workflow uploads
that archive under a main/tree-derived name and records the decision, tree,
source commit, and source run in the GitHub step summary. Installation extracts
the archive and verifies executable modes before the repository's local
certificate-backed re-signing and lifecycle smoke test; artifact promotion
does not weaken installed-app verification.
