#!/usr/bin/env python3
"""Write and validate immutable Git/tree provenance for packaged Voice artifacts."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def write_manifest(args: argparse.Namespace) -> int:
    payload = {
        "schemaVersion": 1,
        "sourceCommit": args.commit,
        "sourceTree": args.tree,
        "workflowRunId": int(args.run_id),
        "workflowEvent": args.event,
        "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return 0


def load_object(path: str) -> dict[str, object]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("expected a JSON object")
    return payload


def verify_manifest(args: argparse.Namespace) -> int:
    try:
        payload = load_object(args.manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"invalid artifact provenance: {error}", file=sys.stderr)
        return 1
    if payload.get("schemaVersion") != 1:
        print("unsupported artifact provenance schema", file=sys.stderr)
        return 1
    if payload.get("sourceTree") != args.expected_tree:
        print("artifact Git tree does not match merged main", file=sys.stderr)
        return 1
    if not isinstance(payload.get("sourceCommit"), str) or not payload["sourceCommit"]:
        print("artifact source commit is missing", file=sys.stderr)
        return 1
    if not isinstance(payload.get("workflowRunId"), int):
        print("artifact workflow run ID is missing", file=sys.stderr)
        return 1
    return 0


def list_candidates(args: argparse.Namespace) -> int:
    try:
        payload = load_object(args.input)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"invalid artifact response: {error}", file=sys.stderr)
        return 1
    expected_name = f"Interview-Arc-Voice-tree-{args.tree}"
    candidates: list[tuple[int, int]] = []
    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, list):
        return 1
    for candidate in artifacts:
        if not isinstance(candidate, dict):
            continue
        workflow_run = candidate.get("workflow_run")
        if (
            candidate.get("name") == expected_name
            and candidate.get("expired") is False
            and isinstance(candidate.get("id"), int)
            and isinstance(workflow_run, dict)
            and isinstance(workflow_run.get("id"), int)
        ):
            candidates.append((candidate["id"], workflow_run["id"]))
    if not candidates:
        return 1
    for artifact_id, run_id in sorted(candidates, reverse=True):
        print(f"{artifact_id}\t{run_id}")
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)

    write = commands.add_parser("write")
    write.add_argument("--output", required=True)
    write.add_argument("--commit", required=True)
    write.add_argument("--tree", required=True)
    write.add_argument("--run-id", required=True, type=int)
    write.add_argument("--event", required=True)
    write.set_defaults(handler=write_manifest)

    verify = commands.add_parser("verify")
    verify.add_argument("--manifest", required=True)
    verify.add_argument("--expected-tree", required=True)
    verify.set_defaults(handler=verify_manifest)

    candidates = commands.add_parser("candidates")
    candidates.add_argument("--input", required=True)
    candidates.add_argument("--tree", required=True)
    candidates.set_defaults(handler=list_candidates)
    return root


def main() -> int:
    args = parser().parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
