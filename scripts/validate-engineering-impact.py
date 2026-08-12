#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path

CLASSIFICATIONS = {
    "none": "none",
    "change note": "change-note",
    "adr": "adr",
    "architecture review": "architecture-review",
    "feature retrospective": "feature-retrospective",
    "postmortem": "postmortem",
    "capability dossier": "capability-dossier",
}
CLASSIFICATION_VALUES = set(CLASSIFICATIONS.values())
PLACEHOLDER_REASONS = {
    "todo",
    "n/a",
    "na",
    "none",
    "replace with a concrete reason",
}
RECORD_REF = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*@[1-9]\d*$")
RECORD_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
MERGED_AT = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
RECORD_PATH = re.compile(r"^docs/engineering/records/[a-z0-9]+(?:-[a-z0-9]+)*\.md$")
SOURCE_KINDS = {"issue", "pull-request", "commit", "release", "run", "documentation"}
CONFIDENCE_VALUES = {"verified", "high", "medium", "low", "unknown"}
MAX_STRING_LIST_ITEMS = 32
MAX_STRING_ITEM_LENGTH = 512
MAX_RECORD_REFS = 16
MAX_RECORD_REF_LENGTH = 180
MAX_SOURCES = 32
MAX_SOURCE_LABEL_LENGTH = 160
MAX_SOURCE_URL_LENGTH = 2048
RECEIPT_FIELDS = {
    "schemaVersion",
    "repository",
    "pr",
    "title",
    "classification",
    "richRecordRefs",
    "reconstructed",
    "confidence",
    "unknowns",
    "headCommit",
    "mergeCommit",
    "mergedAt",
    "sources",
    "verification",
    "visibility",
    "publicationEligibility",
}


def selected_classifications(body: str):
    pattern = re.compile(
        r"^\s*-\s*\[[xX]\]\s*(None|Change Note|ADR|Architecture Review|Feature Retrospective|Postmortem|Capability Dossier)(?:\s*[—-]\s*reason:\s*(.*))?\s*$",
        re.IGNORECASE,
    )
    selected = []
    in_engineering_impact = False
    fence = None
    for line in body.splitlines():
        fence_match = re.match(r"^\s*(`{3,}|~{3,})(.*)$", line)
        if fence_match:
            delimiter = fence_match.group(1)
            if fence is None:
                fence = (delimiter[0], len(delimiter))
            elif delimiter[0] == fence[0] and len(delimiter) >= fence[1] and not fence_match.group(2).strip():
                fence = None
            continue
        if fence is not None:
            continue
        heading = re.match(r"^##\s+(.+?)\s*$", line)
        if heading:
            in_engineering_impact = heading.group(1).strip().lower() == "engineering impact"
            continue
        if not in_engineering_impact:
            continue
        match = pattern.match(line)
        if match:
            selected.append((CLASSIFICATIONS[match.group(1).lower()], (match.group(2) or "").strip()))
    return selected


def leading_frontmatter(markdown: str, document_kind: str):
    lines = markdown.replace("\r\n", "\n").split("\n")
    if not lines or lines[0] != "---":
        raise ValueError(f"The canonical {document_kind} must begin with frontmatter.")
    try:
        end = lines.index("---", 1)
    except ValueError as error:
        raise ValueError(f"The canonical {document_kind} frontmatter is not closed.") from error
    fields = {}
    for line in lines[1:end]:
        match = re.match(r"^([A-Za-z][A-Za-z0-9]*):(?:[ \t]*(.*))?$", line)
        if not match or match.group(1) in fields:
            raise ValueError(f"The canonical {document_kind} frontmatter is invalid.")
        fields[match.group(1)] = match.group(2) or ""
    return fields, "\n".join(lines[end + 1 :]).strip()


def json_value(raw: str, field: str):
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError(f"The canonical Pull Request Receipt has an invalid `{field}` field.") from error


def string_list(
    value,
    field: str,
    *,
    max_items: int = MAX_STRING_LIST_ITEMS,
    max_length: int = MAX_STRING_ITEM_LENGTH,
):
    if (
        not isinstance(value, list)
        or len(value) > max_items
        or any(not isinstance(item, str) or not item or len(item) > max_length for item in value)
        or len(value) != len(set(value))
    ):
        raise ValueError(f"The canonical Pull Request Receipt has an invalid `{field}` field.")
    return value


def parse_receipt_identity(fields: dict[str, str]):
    if set(fields) != RECEIPT_FIELDS:
        raise ValueError("The canonical Pull Request Receipt frontmatter does not match schema version 1.")
    if fields["schemaVersion"] != "1" or fields["repository"] != "interview-arc-voice":
        raise ValueError("The canonical Pull Request Receipt has invalid schema or repository identity.")
    if not re.fullmatch(r"[1-9]\d*", fields["pr"]):
        raise ValueError("The canonical Pull Request Receipt has an invalid `pr` field.")
    title = fields["title"].strip()
    if not title or len(title) > 160:
        raise ValueError("The canonical Pull Request Receipt has an invalid `title` field.")
    classification = fields["classification"]
    if classification not in CLASSIFICATION_VALUES:
        raise ValueError("The canonical Pull Request Receipt has an invalid classification.")
    rich_record_refs = string_list(
        json_value(fields["richRecordRefs"], "richRecordRefs"),
        "richRecordRefs",
        max_items=MAX_RECORD_REFS,
        max_length=MAX_RECORD_REF_LENGTH,
    )
    if any(not RECORD_REF.fullmatch(ref) for ref in rich_record_refs):
        raise ValueError("The canonical Pull Request Receipt has invalid rich Engineering record references.")
    if fields["visibility"] != "public-safe" or fields["publicationEligibility"] != "eligible":
        raise ValueError("The canonical Pull Request Receipt is not publication eligible and public-safe.")
    if classification == "none" and rich_record_refs:
        raise ValueError("Engineering impact `None` must not link rich Engineering records.")
    if classification != "none" and not rich_record_refs:
        raise ValueError("A material Pull Request Receipt must link a rich Engineering record.")
    return int(fields["pr"]), title, classification, rich_record_refs


def validate_receipt_history(fields: dict[str, str]):
    reconstructed = json_value(fields["reconstructed"], "reconstructed")
    if not isinstance(reconstructed, bool):
        raise ValueError("The canonical Pull Request Receipt has an invalid `reconstructed` field.")
    if fields["confidence"] not in CONFIDENCE_VALUES:
        raise ValueError("The canonical Pull Request Receipt has an invalid `confidence` field.")
    string_list(json_value(fields["unknowns"], "unknowns"), "unknowns")
    factual_values = []
    for field in ("headCommit", "mergeCommit"):
        value = json_value(fields[field], field)
        if value is not None and (not isinstance(value, str) or not COMMIT.fullmatch(value)):
            raise ValueError(f"The canonical Pull Request Receipt has an invalid `{field}` field.")
        factual_values.append(value)
    merged_at = json_value(fields["mergedAt"], "mergedAt")
    if merged_at is not None and (not isinstance(merged_at, str) or not MERGED_AT.fullmatch(merged_at)):
        raise ValueError("The canonical Pull Request Receipt has an invalid `mergedAt` field.")
    factual_values.append(merged_at)
    sources = json_value(fields["sources"], "sources")
    if not isinstance(sources, list) or not sources or len(sources) > MAX_SOURCES:
        raise ValueError("The canonical Pull Request Receipt has an invalid `sources` field.")
    for source in sources:
        if (
            not isinstance(source, dict)
            or set(source) != {"label", "url", "kind"}
            or not isinstance(source["label"], str)
            or not source["label"]
            or len(source["label"]) > MAX_SOURCE_LABEL_LENGTH
            or not isinstance(source["url"], str)
            or not source["url"].startswith("https://")
            or len(source["url"]) > MAX_SOURCE_URL_LENGTH
            or source["kind"] not in SOURCE_KINDS
        ):
            raise ValueError("The canonical Pull Request Receipt has an invalid `sources` field.")
    return factual_values


def validate_receipt_verification(fields: dict[str, str], factual_values: list):
    verification = json_value(fields["verification"], "verification")
    if not isinstance(verification, dict) or set(verification) != {"state", "evidenceRefs"}:
        raise ValueError("The canonical Pull Request Receipt has an invalid `verification` field.")
    if verification["state"] not in {"verified", "not-recorded"}:
        raise ValueError("The canonical Pull Request Receipt has an invalid `verification` field.")
    evidence_refs = string_list(verification["evidenceRefs"], "verification")
    if any(value is not None for value in factual_values) and (
        verification["state"] != "verified" or not evidence_refs
    ):
        raise ValueError("Verified evidence is required for supplied historical Pull Request facts.")


def validate_receipt_body(body: str, title: str):
    blocks = [block.strip() for block in re.split(r"\n\s*\n", body) if block.strip()]
    if len(blocks) != 2 or blocks[0] != f"# {title}":
        raise ValueError("The canonical Pull Request Receipt must contain its title and one summary paragraph.")
    summary = " ".join(line.strip() for line in blocks[1].splitlines()).strip()
    if not summary or len(summary) > 280 or summary.startswith("#"):
        raise ValueError("The canonical Pull Request Receipt summary must contain 1 to 280 characters.")


def parse_receipt(markdown: str, path: str):
    fields, body = leading_frontmatter(markdown, "Pull Request Receipt")
    pull_request_number, title, classification, rich_record_refs = parse_receipt_identity(fields)
    factual_values = validate_receipt_history(fields)
    validate_receipt_verification(fields, factual_values)
    validate_receipt_body(body, title)
    return {
        "path": path,
        "pr": pull_request_number,
        "classification": classification,
        "richRecordRefs": rich_record_refs,
    }


def parse_record(markdown: str):
    fields, _ = leading_frontmatter(markdown, "Engineering record")
    record_id = fields.get("id", "")
    revision = fields.get("revision", "")
    record_type = fields.get("type", "")
    if (
        not RECORD_ID.fullmatch(record_id)
        or not re.fullmatch(r"[1-9]\d*", revision)
        or record_type not in CLASSIFICATION_VALUES - {"none"}
    ):
        raise ValueError("A canonical Engineering record has invalid identity frontmatter.")
    return {"id": record_id, "type": record_type, "ref": f"{record_id}@{revision}"}


def run_git(args, *, text=True, input_data=None):
    return subprocess.run(
        ["git", *args],
        input=input_data,
        text=text,
        capture_output=True,
        check=False,
    )


def has_commit(revision: str):
    return run_git(["cat-file", "-e", f"{revision}^{{commit}}"]).returncode == 0


def ensure_commit(revision: str):
    if not COMMIT.fullmatch(revision):
        raise ValueError("Pull request revisions must be full commit identifiers.")
    if has_commit(revision):
        return
    fetched = run_git(["fetch", "--no-tags", "--depth=1", "origin", revision])
    if fetched.returncode != 0 or not has_commit(revision):
        raise ValueError("Unable to load a required pull request revision from the trusted Git remote.")


def changed_files_between(base: str, head: str):
    result = run_git(["diff", "--name-only", "--no-renames", "-z", base, head])
    if result.returncode != 0:
        raise ValueError("Unable to inspect the pull request file set.")
    return [path for path in result.stdout.split("\0") if path]


def blobs_at(revision: str, paths: list[str]):
    if not paths:
        return []
    requests = [f"{revision}:{path}" for path in paths]
    result = run_git(
        ["cat-file", "--batch"],
        text=False,
        input_data=("\n".join(requests) + "\n").encode("utf-8"),
    )
    if result.returncode != 0:
        raise ValueError("Unable to inspect canonical Engineering documents.")
    output = result.stdout
    documents = []
    offset = 0
    for request in requests:
        header_end = output.find(b"\n", offset)
        if header_end < 0:
            raise ValueError("Git returned an invalid canonical Engineering document response.")
        header = output[offset:header_end].decode("utf-8")
        offset = header_end + 1
        if header == f"{request} missing":
            documents.append(None)
            continue
        match = re.fullmatch(r"[0-9a-f]{40} blob (0|[1-9]\d*)", header)
        if not match:
            raise ValueError("Git returned an invalid canonical Engineering document response.")
        size = int(match.group(1))
        end = offset + size
        if end >= len(output) or output[end] != 0x0A:
            raise ValueError("Git returned an invalid canonical Engineering document response.")
        try:
            documents.append(output[offset:end].decode("utf-8"))
        except UnicodeDecodeError as error:
            raise ValueError("A canonical Engineering document is not valid UTF-8.") from error
        offset = end + 1
    if offset != len(output):
        raise ValueError("Git returned an invalid canonical Engineering document response.")
    return documents


def record_path_for_ref(record_ref: str):
    record_id, _ = record_ref.rsplit("@", 1)
    return f"docs/engineering/records/{record_id}.md"


def records_for_validation(head: str, changed_paths: list[str], linked_refs: list[str]):
    for path in changed_paths:
        if not RECORD_PATH.fullmatch(path):
            raise ValueError("Changed canonical Engineering records must use a lowercase repository-root filename.")
    linked_paths = [record_path_for_ref(record_ref) for record_ref in linked_refs]
    paths = list(dict.fromkeys([*changed_paths, *linked_paths]))
    documents = blobs_at(head, paths)
    records = {}
    for path, markdown in zip(paths, documents):
        if markdown is None:
            if path in changed_paths:
                raise ValueError("Every changed canonical Engineering record must exist at the pull request head.")
            raise ValueError("A material Pull Request Receipt must link exact rich Engineering record revisions at the pull request head.")
        record = parse_record(markdown)
        if path != f'docs/engineering/records/{record["id"]}.md':
            raise ValueError("A canonical Engineering record path must match its exact record identity.")
        if record["ref"] in records:
            raise ValueError("Canonical Engineering record references must be unique.")
        records[record["ref"]] = {**record, "path": path}
    if any(record_ref not in records for record_ref in linked_refs):
        raise ValueError("A material Pull Request Receipt must link exact rich Engineering record revisions at the pull request head.")
    return records


def validate(body: str, changed_files: list[str], pull_request_number: int, receipt, head_records: dict):
    selected = selected_classifications(body or "")
    if len(selected) != 1:
        raise ValueError("Select exactly one Engineering impact classification in the pull request body.")
    classification, reason = selected[0]
    if not isinstance(pull_request_number, int) or isinstance(pull_request_number, bool) or pull_request_number < 1:
        raise ValueError("A positive pull request number is required for the canonical Pull Request Receipt.")
    expected_receipt_path = f"docs/engineering/changes/pr-{pull_request_number}.md"
    changed_receipt_paths = [path for path in changed_files if path.startswith("docs/engineering/changes/")]
    if changed_receipt_paths != [expected_receipt_path] or receipt is None:
        raise ValueError("Every pull request must change exactly one canonical Pull Request Receipt at its numbered path.")
    if receipt["path"] != expected_receipt_path or receipt["pr"] != pull_request_number:
        raise ValueError("The canonical Pull Request Receipt path and `pr` field must match the pull request number.")
    if receipt["classification"] != classification:
        raise ValueError("The canonical Pull Request Receipt classification must match the pull request body.")

    changed_record_paths = [path for path in changed_files if path.startswith("docs/engineering/records/")]
    for path in changed_record_paths:
        if not RECORD_PATH.fullmatch(path):
            raise ValueError("Changed canonical Engineering records must use a lowercase repository-root filename.")
        if not any(record["path"] == path for record in head_records.values()):
            raise ValueError("Every changed canonical Engineering record must exist at the pull request head.")
    changed_records = [record for record in head_records.values() if record["path"] in changed_record_paths]

    if classification == "none":
        normalized_reason = re.sub(r"[.!]+$", "", reason.strip()).lower()
        if len(reason) < 12 or normalized_reason in PLACEHOLDER_REASONS:
            raise ValueError("Engineering impact `None` requires a concrete reason.")
        if changed_records:
            raise ValueError("A canonical Engineering record changed, so Engineering impact cannot be `None`.")
        if receipt["richRecordRefs"]:
            raise ValueError("Engineering impact `None` must not link rich Engineering records.")
        return classification

    linked_records = []
    for record_ref in receipt["richRecordRefs"]:
        record = head_records.get(record_ref)
        if record is None:
            raise ValueError("A material Pull Request Receipt must link exact rich Engineering record revisions at the pull request head.")
        linked_records.append(record)
    if not linked_records:
        raise ValueError(f"Engineering impact `{classification}` requires a matching canonical record.")
    if any(record["type"] != classification for record in linked_records):
        raise ValueError("The pull request Engineering impact classification does not match its linked canonical records.")
    changed_refs = {record["ref"] for record in changed_records}
    if not changed_refs.issubset(set(receipt["richRecordRefs"])):
        raise ValueError("A material Pull Request Receipt must link every exact rich Engineering record revision changed by the pull request.")
    if any(record["type"] != classification for record in changed_records):
        raise ValueError("The pull request Engineering impact classification does not match its changed canonical records.")
    return classification


def main():
    event_path = Path(sys.argv[1] if len(sys.argv) > 1 else "")
    if not event_path.is_file():
        raise ValueError("A pull-request event path is required.")
    event = json.loads(event_path.read_text(encoding="utf-8"))
    pull_request = event.get("pull_request", {})
    base = pull_request.get("base", {}).get("sha")
    head = pull_request.get("head", {}).get("sha")
    number = pull_request.get("number")
    if not base or not head or not isinstance(number, int) or isinstance(number, bool) or number < 1:
        raise ValueError("Pull request base, head, and number are required.")
    ensure_commit(base)
    ensure_commit(head)
    changed = changed_files_between(base, head)
    expected_receipt_path = f"docs/engineering/changes/pr-{number}.md"
    receipt_paths = [path for path in changed if path.startswith("docs/engineering/changes/")]
    receipt = None
    if receipt_paths == [expected_receipt_path]:
        [markdown] = blobs_at(head, [expected_receipt_path])
        if markdown is not None:
            receipt = parse_receipt(markdown, expected_receipt_path)
    changed_record_paths = [path for path in changed if path.startswith("docs/engineering/records/")]
    linked_refs = receipt["richRecordRefs"] if receipt else []
    classification = validate(
        pull_request.get("body") or "",
        changed,
        number,
        receipt,
        records_for_validation(head, changed_record_paths, linked_refs),
    )
    print(f"Engineering impact: {classification}; {len(changed)} changed file(s).")


if __name__ == "__main__":
    try:
        main()
    except (json.JSONDecodeError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
