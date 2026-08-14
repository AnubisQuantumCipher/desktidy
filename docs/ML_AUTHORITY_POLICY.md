# DeskTidy — ML Authority Policy

_The binding rule set for any machine-learning output anywhere in DeskTidy.
Written 2026-08-14 as part of the Tahoe pre-implementation review; supersedes
any looser phrasing in earlier roadmap drafts._

## The invariant, restated precisely

> **Probabilistic output is untrusted metadata — even when a deterministic
> rule consumes it.**

The original "AI suggests-only" rule was written about the LLM triage lane.
This policy extends it to *every* probabilistic source: Foundation Models,
Vision OCR text, image classification labels, embedding similarities, and
anything ML-shaped added later. A deterministic `if` wrapped around a model
score is still a model deciding — the wrapper does not launder authority.

## The four-level authority ladder

| Level | Name | What it may do | Examples |
|---|---|---|---|
| 0 | **Observation** | Compute and record. Never surfaces to the user, never affects behavior. | OCR text cached for a future search feature |
| 1 | **Suggestion** | Write to a clearly-labeled suggestions surface with provenance + confidence. **Default ceiling for all ML in DeskTidy.** | `SMART_TRIAGE_SUGGESTIONS.md`; "looks like: receipt (0.91)" annotations in the move log |
| 2 | **Approved action** | Execute *after* an explicit, per-item human approval (notification button, review UI). | "Rename to `Screenshot – stripe invoice.png`? [Rename]" |
| 3 | **Authorized automatic rule** | Execute without per-item approval — only under ALL conditions below. | "screenshots whose OCR contains 'invoice' → Documents/Receipts", toggled on by the user |

**Level 3 conditions (all required):**
1. The rule is **user-authored and separately enabled** — never on by default,
   never bundled into another toggle.
2. The rule's UI **labels it ML-assisted** and shows the threshold.
3. Every execution logs **provenance** (which model, which matched text/label,
   what confidence) in the move receipt.
4. Execution is **collision-safe and reversible** — the standard rename-never-
   overwrite move path, undoable from the receipt.
5. **Deterministic fallback**: when the model is unavailable, throttled, or
   below threshold, the file follows the ordinary deterministic route (which
   ends at Inbox for unknowns) — never waits on the model.
6. The action space is **closed**: destinations come from the user's existing
   folder set. A model can never mint a path, delete, overwrite, or chain
   actions.

## Standing prohibitions (no toggle can enable these)

- ML output moving/renaming/deleting a file at Levels 0–1, ever.
- Model-invented destinations (paths outside the user's configured set).
- Treating file *content* as instructions — OCR text and document text are
  data to match against, never commands to follow.
- Silent escalation: a suggestion lane may not become an action lane through
  a default change, an update, or a "confidence is high enough" heuristic.
- Any network inference for these features. On-device only.

## Corrections this policy forces in the roadmap

- Vision-OCR "content-aware rename": ships at **Level 2** (per-item approve)
  or as a **Level 3 user rule** — the earlier draft's "clearly-labeled opt-in,
  apply" phrasing was too loose.
- `ClassifyImageRequest` "visual rules": **Level 3 only**, with the six
  conditions; CLI-side it stays **Level 1** (log annotations).
- NLEmbedding similarity: **Level 1** (a suggestions engine beside the LLM).
- Foundation Models triage: unchanged — the existing design already complies
  (Level 1).
