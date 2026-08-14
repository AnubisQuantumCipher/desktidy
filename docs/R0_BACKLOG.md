# R0 backlog — adjacent work deliberately NOT done in the R0 mission

Recorded per the R0 mission's scope rule: tempting, in-reach work that was
left untouched because it belongs to later releases. Pointers are exact.

1. **Notifier reads the ledger instead of the text log** — point
   `src/desktidy-notify.sh` at `receipts/ledger.jsonl` (outcome=`moved` lines)
   instead of tailing `desktidy.log`; gains failure banners for `failed`
   receipts. R1.
2. **`desktidy undo <receipt-id>`** — consume `undoEligible` +
   `finalDestRel`→`sourceRel` inverse metadata from `ReceiptLedger.readAll()`;
   must itself be receipted (`ruleID: "undo"`). R1 (`UndoLastMoveIntent`).
3. **`WhereDidItGo(filename)`** — trivial filter over the single reader;
   deferred to R1 where it becomes an App Intent.
4. **Migration/takeover flow for a conflicting authority** — the guard's
   diagnosis output is designed to feed a future `--authorize-takeover`
   dry-run/plan; requires separate architect sign-off per the R0 mission.
5. **Ledger rotation/compaction** — `ledger.jsonl` grows unbounded; add
   size-gated rotation that re-anchors the hash chain with a checkpoint
   record. Revisit before R2's history UI.
6. **Receipt-aware `--smart-now` summary** — `sort-now` could print the
   receipts it just produced (currently prints counts only).
7. **`launchctl` state caching** — the guard shells out per label; a single
   `launchctl print gui/<uid>` parse would cut setup latency. Micro-perf only.
