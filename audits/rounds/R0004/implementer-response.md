# R0004 — Implementer Response

Captured at: 2026-09-24T22:02:39-03:00
Phase: implementer_response
Role: implementer

Allowed dispositions:
- ACCEPTED
- REJECTED
- DEFERRED
- NEEDS_PO
- NEEDS_TEST

Rule:
Every material finding must receive an explicit disposition.
No finding may disappear silently.

---

# Implementer Response — R0004

## Claude findings

FINDING C-001
Disposition: ACCEPTED

The current Set-AadoPODecision guard searches for a two-space
"status: pending" line globally instead of structurally inside po_decision.

The current schema happens not to contain another matching status field,
but this is fragile under schema evolution.

Action:
Scope reads and writes explicitly to the po_decision section.
Prefer a reusable structured section helper rather than another ad-hoc regex.


FINDING C-002
Disposition: REJECTED

The specific failure mode described is not consistent with the current
implementation.

Set-AadoPublicationMetadata performs all regex replacements against the
in-memory $Yaml string and executes Set-Content only once, after all fields
have been modified.

Therefore an interruption between the branch replacement and commit
replacement cannot persist a branch-only intermediate state.

However, interruption or failure during the final Set-Content itself is a
different integrity risk and should be treated separately as an atomic-write
hardening requirement.


FINDING C-003
Disposition: ACCEPTED

Get-AadoPhaseMemberStatus depends on physical YAML layout and section order.

The current generated layout makes it work, but the parser is fragile if the
schema is reordered or expanded.

Action:
Treat section boundaries structurally.
Longer term, evaluate a real YAML parser instead of increasing regex
complexity indefinitely.


FINDING C-004
Disposition: ACCEPTED

Build-AadoPODigest can silently lose a finding if a new FINDING line is
encountered before the previous finding receives a Disposition.

Action:
Reject:
- a second FINDING while another finding is unresolved;
- a trailing FINDING with no Disposition;
- a Disposition without an active FINDING.


FINDING C-005
Disposition: ACCEPTED

Only APPROVED_FOR_MERGE requires mergeability=clean by design.

CHANGES_REQUESTED and REJECTED must remain possible even when mergeability
is conflicts or unknown.

Action:
Document this explicitly in code and tests so a future state addition does
not accidentally inherit the wrong rule.


FINDING C-006
Disposition: ACCEPTED

"Published commit" in po-decision.md is traceability information and is not
necessarily an approved commit.

Action:
Use unambiguous terminology:
- "Approved commit" for APPROVED_FOR_MERGE;
- "Commit at decision time" for CHANGES_REQUESTED / REJECTED.


FINDING C-007
Disposition: ACCEPTED

Set-AadoPODecision currently validates format and equality against round.yaml,
but does not independently prove that the commit exists in Git or belongs to
the declared publication branch.

Our current manual workflow performed this verification externally.

Action:
Before autonomous use, commit existence and branch membership must become an
objective verification step rather than an undocumented caller assumption.


FINDING C-008
Disposition: ACCEPTED

ExpectedCommit only provides independent protection if it comes from a source
independent of the value stored in round.yaml.

Automatically reading round.yaml and feeding the same value back into
Set-AadoPODecision would make the comparison circular.

Action:
The future caller must obtain the candidate commit from independently
verified Git/GitHub state and compare it with publication metadata before
recording PO approval.


FINDING C-009
Disposition: ACCEPTED

The root round status currently remains "draft" and therefore cannot be
treated as authoritative round state.

Action:
Either define and maintain a real round-level state machine or explicitly
remove/reserve the root status field. Do not allow callers to infer lifecycle
state from it in the current schema.


## Gemini blind-review findings

FINDING G-001
Disposition: ACCEPTED

Persisted blind-review files do not currently have cryptographic integrity
evidence.

Read-only file attributes would not be sufficient because a process running
as the same user can remove them.

Action:
Record SHA256 for immutable review artifacts and verify hashes before later
phases consume them. Git history remains additional evidence, not a
replacement for runtime integrity checks.


FINDING G-002
Disposition: REJECTED

ExecutionPolicy is an environment/deployment concern, not a defect in the
RoundManagerCore module itself.

The module is already successfully imported and executed in the current VPS.

Any launcher-specific ExecutionPolicy requirement belongs in installation or
entry-point logic rather than this Core change.


FINDING G-003
Disposition: DEFERRED

Branch collision handling is relevant when automated branch/PR publication
is implemented.

The current Core does not yet implement Publish-Round or automatic branch
creation, so there is no present defect in this module to fix.

Track it as a requirement for the publication automation stage.


FINDING G-004
Disposition: NEEDS_TEST

The current PowerShell environment and Set-Content UTF8 behavior should be
measured rather than assumed.

A BOM is not automatically a correctness failure for Markdown/YAML/Git.

Action:
Create encoding tests using actual files produced on this VPS and verify they
round-trip through Git and the external-auditor workflow without corruption.


## Process findings from the real audit

FINDING P-001
Disposition: ACCEPTED

Gemini's blind response did not follow the mandatory
FINDING / Severity / Type / Evidence / Impact / Recommendation schema.

Save-AadoBlindResponse currently accepts arbitrary text, so the protocol
accepted a response that did not satisfy its declared contract.

Action:
Add deterministic response-format validation before marking an auditor phase
completed. Invalid responses must be rejected rather than normalized or
silently accepted.


FINDING P-002
Disposition: ACCEPTED

Gemini generated a replacement implementation even though the task was an
audit.

The generated code also diverged from the current public interface and was
not authoritative.

Action:
Auditor output remains advisory evidence only.
Generated replacement code must never be treated as an applied change merely
because an auditor supplied it.


FINDING P-003
Disposition: ACCEPTED

The real R0004 audit demonstrated that cross-review is useful:
Claude identified format and scope failures in Gemini's blind response, while
Gemini's later cross-review converged on several concrete Claude findings.

Action:
Preserve blind originals unchanged and retain cross-review as a distinct
phase. Agreement is evidence, not a vote.


## Merge disposition

PR #2 should NOT be merged in its current state.

At minimum, C-001, C-004 and P-001 should be corrected and objectively tested
before a new PO approval is requested.

C-003, G-001, C-007 and C-008 should be incorporated into the immediate
hardening design because they directly affect the reliability of the future
autonomous workflow.

The rejected C-002 scenario should not be implemented as proposed; instead,
atomic file-write integrity should be specified and tested separately.
