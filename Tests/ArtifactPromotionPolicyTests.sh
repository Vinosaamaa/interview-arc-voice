#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

python3 "$ROOT/scripts/artifact-provenance.py" write \
  --output "$TEMP_ROOT/provenance.json" \
  --commit commit-pr \
  --tree tree-match \
  --run-id 3003 \
  --event pull_request

python3 "$ROOT/scripts/artifact-provenance.py" verify \
  --manifest "$TEMP_ROOT/provenance.json" \
  --expected-tree tree-match

if python3 "$ROOT/scripts/artifact-provenance.py" verify \
  --manifest "$TEMP_ROOT/provenance.json" \
  --expected-tree tree-different >/dev/null 2>&1; then
  echo "non-equivalent tree was incorrectly accepted" >&2
  exit 1
fi

selection="$(python3 "$ROOT/scripts/artifact-provenance.py" select \
  --input "$ROOT/Tests/Fixtures/action-artifacts.json" \
  --tree tree-match)"
test "$selection" = $'303\t3003'

if python3 "$ROOT/scripts/artifact-provenance.py" select \
  --input "$ROOT/Tests/Fixtures/action-artifacts.json" \
  --tree tree-missing >/dev/null 2>&1; then
  echo "missing artifact was incorrectly selected" >&2
  exit 1
fi

grep -q 'pull_request:' "$ROOT/.github/workflows/ci.yml"
grep -q 'push:' "$ROOT/.github/workflows/ci.yml"
grep -q 'artifact-provenance.py verify' "$ROOT/.github/workflows/ci.yml"
grep -q 'retention-days: 14' "$ROOT/.github/workflows/ci.yml"
grep -q 'Interview-Arc-Voice-tree-' "$ROOT/.github/workflows/ci.yml"
grep -q "steps.promotion.outputs.available != 'true'" "$ROOT/.github/workflows/ci.yml"
grep -q 'Package merged main' "$ROOT/.github/workflows/ci.yml"
grep -q 'Interview-Arc-Voice-main-' "$ROOT/.github/workflows/ci.yml"

echo "Artifact promotion policy tests passed."
