---
schemaVersion: 1
repository: interview-arc-voice
pr: 9
title: "Fix long dictation transcript integrity and recovery"
classification: postmortem
richRecordRefs: ["postmortem-long-dictation-transcript-integrity@1"]
reconstructed: true
confidence: high
unknowns: ["An explicit linked issue was not exposed.","Attachment bodies and workflow logs were not quoted.","Sensitive source values and nonessential risky evidence links were omitted from this staged record."]
headCommit: "37d2fbc78c3d78f03f53acd6a6fdeb28f69ba8bd"
mergeCommit: "0310ff1e675d2b01b47aa3309f8f4fa76ca82417"
mergedAt: "2026-07-24T06:46:51Z"
sources: [{"label":"Pull request #9","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/9","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:9","head-commit:37d2fbc78c3d78f03f53acd6a6fdeb28f69ba8bd","merge-commit:0310ff1e675d2b01b47aa3309f8f4fa76ca82417"]}
visibility: public-safe
publicationEligibility: eligible
---
# Fix long dictation transcript integrity and recovery

Historical first-parent diff changes 8 files (+626/-66), primarily Sources (5), docs (1), README.md (1), Tests (1).
