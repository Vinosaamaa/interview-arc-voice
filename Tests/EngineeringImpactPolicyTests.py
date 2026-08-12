#!/usr/bin/env python3
import importlib.util
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "validate-engineering-impact.py"
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
SCHEMA = ROOT / "docs" / "contracts" / "engineering-pull-request-receipt.schema.json"
PROTOCOL = ROOT / "docs" / "engineering" / "pull-request-history.md"
SPEC = importlib.util.spec_from_file_location("engineering_impact", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

NONE_BODY = """## Engineering impact

- [x] None — reason: This change only corrects non-engineering copy.
"""
DOSSIER_BODY = """## Engineering impact

- [x] Capability Dossier
"""
DOSSIER_REF = "capability-dossier-voice-capture-reliability@1"


def git(cwd: Path, *args: str):
    return subprocess.check_output(
        ["git", *args], cwd=cwd, text=True, stderr=subprocess.PIPE
    ).strip()


def write(cwd: Path, relative: str, content: str):
    destination = cwd / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(content, encoding="utf-8")


def initialize_repository(cwd: Path, include_record: bool = False):
    git(cwd, "init", "--quiet", "--initial-branch=main")
    git(cwd, "config", "user.name", "Engineering Impact Test")
    git(cwd, "config", "user.email", "engineering-impact@example.com")
    write(cwd, "README.md", "# Fixture\n")
    if include_record:
        write(
            cwd,
            "docs/engineering/records/capability-dossier-voice-capture-reliability.md",
            """---
schemaVersion: 1
id: capability-dossier-voice-capture-reliability
revision: 1
type: capability-dossier
---
# Voice Capture Reliability

Records the stable Voice capability boundary.
""",
        )
    git(cwd, "add", ".")
    git(cwd, "commit", "--quiet", "-m", "base")
    return git(cwd, "rev-parse", "HEAD")


def receipt_markdown(
    pr: int = 192,
    classification: str = "none",
    refs=None,
    unknowns=None,
    sources=None,
    evidence_refs=None,
    title: str = "Adopt complete pull request receipts",
    summary: str = "Adds the versioned compact receipt contract and enforces one numbered receipt in the required Voice pull-request workflow.",
):
    refs = [] if refs is None else refs
    unknowns = [] if unknowns is None else unknowns
    sources = sources or [{
        "label": f"Pull request #{pr}",
        "url": f"https://github.com/Vinosaamaa/interview-arc-voice/pull/{pr}",
        "kind": "pull-request",
    }]
    evidence_refs = [f"pull-request:{pr}"] if evidence_refs is None else evidence_refs
    return f"""---
schemaVersion: 1
repository: interview-arc-voice
pr: {pr}
title: {title}
classification: {classification}
richRecordRefs: {json.dumps(refs, separators=(',', ':'))}
reconstructed: false
confidence: verified
unknowns: {json.dumps(unknowns, separators=(',', ':'))}
headCommit: null
mergeCommit: null
mergedAt: null
sources: {json.dumps(sources, separators=(',', ':'))}
verification: {json.dumps({"state": "verified", "evidenceRefs": evidence_refs}, separators=(',', ':'))}
visibility: public-safe
publicationEligibility: eligible
---
# {title}

{summary}
"""


def run_validator(cwd: Path, base: str, head: str, number: int, body: str):
    event_path = cwd / "event.json"
    event_path.write_text(
        json.dumps(
            {
                "pull_request": {
                    "number": number,
                    "body": body,
                    "base": {"sha": base},
                    "head": {"sha": head},
                }
            }
        ),
        encoding="utf-8",
    )
    return subprocess.run(
        ["python3", str(SCRIPT), str(event_path)],
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
    )


def yaml_mapping_block(lines: list[str], key: str, indent: int):
    marker = f'{" " * indent}{key}:'
    try:
        start = lines.index(marker) + 1
    except ValueError as error:
        raise AssertionError(f"Missing workflow mapping: {key}") from error
    end = len(lines)
    for index in range(start, len(lines)):
        stripped = lines[index].strip()
        if stripped and not stripped.startswith("#") and len(lines[index]) - len(lines[index].lstrip()) <= indent:
            end = index
            break
    return lines[start:end]


def workflow_steps(workflow: str, job_name: str):
    lines = workflow.splitlines()
    jobs = yaml_mapping_block(lines, "jobs", 0)
    job = yaml_mapping_block(jobs, job_name, 2)
    step_lines = yaml_mapping_block(job, "steps", 4)
    steps = []
    current = None
    for line in step_lines:
        name = re.fullmatch(r" {6}- name: (.+)", line)
        if name:
            current = {"name": name.group(1)}
            steps.append(current)
            continue
        run = re.fullmatch(r" {8}run: (.+)", line)
        if current is not None and run:
            current["run"] = run.group(1)
    return steps


class EngineeringImpactPolicyTests(unittest.TestCase):
    def test_contract_schema_and_protocol_are_versioned(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        self.assertEqual(schema["$id"], "urn:interview-arc:contracts:engineering-pull-request-receipt:1")
        self.assertEqual(schema["properties"]["schemaVersion"]["const"], 1)
        self.assertIn("richRecordRefs", schema["required"])
        self.assertEqual(schema["properties"]["sources"]["maxItems"], 32)
        self.assertEqual(schema["properties"]["sources"]["items"]["properties"]["label"]["maxLength"], 160)
        self.assertEqual(schema["properties"]["sources"]["items"]["properties"]["url"]["maxLength"], 2048)
        self.assertEqual(schema["$defs"]["stringList"]["maxItems"], 32)
        self.assertEqual(schema["$defs"]["stringList"]["items"]["maxLength"], 512)
        self.assertEqual(schema["$defs"]["recordRefs"]["maxItems"], 16)
        self.assertEqual(schema["$defs"]["recordRefs"]["items"]["maxLength"], 180)
        protocol = PROTOCOL.read_text(encoding="utf-8")
        self.assertIn("one compact receipt for every merged pull request", protocol.lower())
        self.assertIn("does not need to request a separate Journal operation", protocol)

    def test_validator_runs_inside_existing_required_package_job(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        pull_request_trigger = yaml_mapping_block(workflow.splitlines(), "pull_request", 2)
        self.assertIn("    types: [opened, synchronize, reopened, edited]", pull_request_trigger)
        validation_steps = [
            step
            for step in workflow_steps(workflow, "test-and-package")
            if step.get("name") == "Validate Engineering impact classification"
        ]
        self.assertEqual(
            validation_steps,
            [{
                "name": "Validate Engineering impact classification",
                "run": 'python3 scripts/validate-engineering-impact.py "$GITHUB_EVENT_PATH"',
            }],
        )

    def test_only_engineering_impact_section_counts(self):
        body = """## Summary

- [x] None — reason: This checkbox is prose, not policy input.

```markdown
## Engineering impact
- [x] ADR
```

## Engineering impact

- [x] Capability Dossier
"""
        self.assertEqual(MODULE.selected_classifications(body), [("capability-dossier", "")])

    def test_shorter_nested_fence_does_not_escape_outer_fence(self):
        body = """````markdown
## Engineering impact
- [x] ADR
```
- [x] Postmortem
````

## Engineering impact

- [x] Capability Dossier
"""
        self.assertEqual(MODULE.selected_classifications(body), [("capability-dossier", "")])

    def test_requires_exactly_one_numbered_receipt(self):
        receipt = {
            "path": "docs/engineering/changes/pr-192.md",
            "pr": 192,
            "classification": "none",
            "richRecordRefs": [],
        }
        self.assertEqual(
            MODULE.validate(NONE_BODY, [receipt["path"]], 192, receipt, {}),
            "none",
        )
        with self.assertRaisesRegex(ValueError, "exactly one canonical"):
            MODULE.validate(NONE_BODY, ["README.md"], 192, None, {})
        with self.assertRaisesRegex(ValueError, "exactly one canonical"):
            MODULE.validate(
                NONE_BODY,
                [receipt["path"], "docs/engineering/changes/pr-191.md"],
                192,
                receipt,
                {},
            )
        with self.assertRaisesRegex(ValueError, "must match the pull request number"):
            MODULE.validate(NONE_BODY, [receipt["path"]], 192, {**receipt, "pr": 191}, {})
        with self.assertRaisesRegex(ValueError, "classification must match"):
            MODULE.validate(
                NONE_BODY,
                [receipt["path"]],
                192,
                {**receipt, "classification": "capability-dossier", "richRecordRefs": [DOSSIER_REF]},
                {},
            )

    def test_none_requires_reason_and_cannot_hide_rich_records(self):
        receipt = {
            "path": "docs/engineering/changes/pr-192.md",
            "pr": 192,
            "classification": "none",
            "richRecordRefs": [],
        }
        with self.assertRaisesRegex(ValueError, "concrete reason"):
            MODULE.validate(
                "## Engineering impact\n\n- [x] None — reason: TODO",
                [receipt["path"]],
                192,
                receipt,
                {},
            )
        with self.assertRaisesRegex(ValueError, "cannot be `None`"):
            MODULE.validate(
                NONE_BODY,
                [receipt["path"], "docs/engineering/records/review.md"],
                192,
                receipt,
                {"review@1": {"ref": "review@1", "type": "architecture-review", "path": "docs/engineering/records/review.md"}},
            )

    def test_material_receipt_must_link_exact_matching_head_record(self):
        path = "docs/engineering/changes/pr-192.md"
        head_records = {
            DOSSIER_REF: {
                "ref": DOSSIER_REF,
                "type": "capability-dossier",
                "path": "docs/engineering/records/capability-dossier-voice-capture-reliability.md",
            }
        }
        receipt = {
            "path": path,
            "pr": 192,
            "classification": "capability-dossier",
            "richRecordRefs": [DOSSIER_REF],
        }
        self.assertEqual(MODULE.validate(DOSSIER_BODY, [path], 192, receipt, head_records), "capability-dossier")
        with self.assertRaisesRegex(ValueError, "exact rich Engineering record revisions"):
            MODULE.validate(
                DOSSIER_BODY,
                [path],
                192,
                {**receipt, "richRecordRefs": ["capability-dossier-voice-capture-reliability@2"]},
                head_records,
            )
        with self.assertRaisesRegex(ValueError, "does not match"):
            MODULE.validate(
                "## Engineering impact\n\n- [x] Architecture Review",
                [path],
                192,
                {**receipt, "classification": "architecture-review"},
                head_records,
            )

    def test_cli_accepts_existing_rich_record_reference(self):
        with tempfile.TemporaryDirectory(prefix="voice-impact-") as directory:
            cwd = Path(directory)
            base = initialize_repository(cwd, include_record=True)
            write(
                cwd,
                "docs/engineering/changes/pr-192.md",
                receipt_markdown(classification="capability-dossier", refs=[DOSSIER_REF]),
            )
            git(cwd, "add", ".")
            git(cwd, "commit", "--quiet", "-m", "add receipt")
            head = git(cwd, "rev-parse", "HEAD")
            result = run_validator(cwd, base, head, 192, DOSSIER_BODY)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Engineering impact: capability-dossier", result.stdout)

    def test_cli_rejects_receipt_deletion_and_rich_record_deletion(self):
        with tempfile.TemporaryDirectory(prefix="voice-impact-") as directory:
            cwd = Path(directory)
            initialize_repository(cwd, include_record=True)
            receipt_path = "docs/engineering/changes/pr-192.md"
            write(cwd, receipt_path, receipt_markdown(classification="capability-dossier", refs=[DOSSIER_REF]))
            git(cwd, "add", ".")
            git(cwd, "commit", "--quiet", "-m", "accepted receipt")
            base = git(cwd, "rev-parse", "HEAD")

            (cwd / receipt_path).unlink()
            git(cwd, "add", "--all")
            git(cwd, "commit", "--quiet", "-m", "delete receipt")
            head = git(cwd, "rev-parse", "HEAD")
            deleted_receipt = run_validator(cwd, base, head, 192, DOSSIER_BODY)
            self.assertNotEqual(deleted_receipt.returncode, 0)
            self.assertIn("canonical Pull Request Receipt", deleted_receipt.stderr)

            git(cwd, "reset", "--hard", base)
            record_path = "docs/engineering/records/capability-dossier-voice-capture-reliability.md"
            (cwd / record_path).unlink()
            write(cwd, receipt_path, receipt_markdown(classification="capability-dossier", refs=[DOSSIER_REF], summary="Attempts to link a rich record deleted at the pull-request head."))
            git(cwd, "add", "--all")
            git(cwd, "commit", "--quiet", "-m", "delete record")
            head = git(cwd, "rev-parse", "HEAD")
            deleted_record = run_validator(cwd, base, head, 192, DOSSIER_BODY)
            self.assertNotEqual(deleted_record.returncode, 0)
            self.assertIn("must exist at the pull request head", deleted_record.stderr)

    def test_cli_never_uses_stale_base_metadata(self):
        with tempfile.TemporaryDirectory(prefix="voice-impact-") as directory:
            cwd = Path(directory)
            base = initialize_repository(cwd, include_record=True)
            record_path = "docs/engineering/records/capability-dossier-voice-capture-reliability.md"
            write(
                cwd,
                record_path,
                """---
schemaVersion: 1
id: capability-dossier-voice-capture-reliability
id: private-value
revision: 1
---
# Invalid record

type: capability-dossier
""",
            )
            write(cwd, "docs/engineering/changes/pr-192.md", receipt_markdown(classification="capability-dossier", refs=[DOSSIER_REF]))
            git(cwd, "add", ".")
            git(cwd, "commit", "--quiet", "-m", "invalidate record")
            head = git(cwd, "rev-parse", "HEAD")
            result = run_validator(cwd, base, head, 192, DOSSIER_BODY)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("frontmatter is invalid", result.stderr)
            self.assertNotIn("private-value", result.stderr)

    def test_receipt_parser_enforces_schema_shape_and_summary_limit(self):
        markdown = receipt_markdown()
        parsed = MODULE.parse_receipt(markdown, "docs/engineering/changes/pr-192.md")
        self.assertEqual(parsed["pr"], 192)
        with self.assertRaisesRegex(ValueError, "schema version 1"):
            MODULE.parse_receipt(
                markdown.replace("visibility: public-safe\n", "visibility: public-safe\nextraField: rejected\n"),
                "docs/engineering/changes/pr-192.md",
            )
        with self.assertRaisesRegex(ValueError, "1 to 280"):
            MODULE.parse_receipt(
                receipt_markdown(summary="x" * 281),
                "docs/engineering/changes/pr-192.md",
            )

    def test_receipt_parser_enforces_exact_v1_collection_and_string_bounds(self):
        max_refs = [f"record-{index}@1" for index in range(15)] + [("a" * 178) + "@1"]
        max_unknowns = [f"{index:02d}" + ("u" * 510) for index in range(32)]
        max_sources = [
            {
                "label": ("l" * 160) if index == 0 else f"Source {index}",
                "url": ("https://" + ("a" * 2040)) if index == 0 else f"https://example.com/{index}",
                "kind": "documentation",
            }
            for index in range(32)
        ]
        max_evidence = [f"{index:02d}" + ("e" * 510) for index in range(32)]
        parsed = MODULE.parse_receipt(
            receipt_markdown(
                classification="capability-dossier",
                refs=max_refs,
                unknowns=max_unknowns,
                sources=max_sources,
                evidence_refs=max_evidence,
            ),
            "docs/engineering/changes/pr-192.md",
        )
        self.assertEqual(len(parsed["richRecordRefs"]), 16)

        cases = {
            "richRecordRefs count": receipt_markdown(
                classification="capability-dossier",
                refs=[f"record-{index}@1" for index in range(17)],
            ),
            "richRecordRefs length": receipt_markdown(
                classification="capability-dossier",
                refs=[("a" * 179) + "@1"],
            ),
            "unknowns count": receipt_markdown(unknowns=[f"unknown-{index}" for index in range(33)]),
            "unknowns length": receipt_markdown(unknowns=["u" * 513]),
            "sources count": receipt_markdown(sources=[
                {"label": f"Source {index}", "url": f"https://example.com/{index}", "kind": "documentation"}
                for index in range(33)
            ]),
            "source label length": receipt_markdown(sources=[
                {"label": "l" * 161, "url": "https://example.com", "kind": "documentation"}
            ]),
            "source URL length": receipt_markdown(sources=[
                {"label": "Source", "url": "https://" + ("a" * 2041), "kind": "documentation"}
            ]),
            "evidence count": receipt_markdown(evidence_refs=[f"evidence-{index}" for index in range(33)]),
            "evidence length": receipt_markdown(evidence_refs=["e" * 513]),
        }
        for label, markdown in cases.items():
            with self.subTest(label=label), self.assertRaises(ValueError):
                MODULE.parse_receipt(markdown, "docs/engineering/changes/pr-192.md")


if __name__ == "__main__":
    unittest.main()
