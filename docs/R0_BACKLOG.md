# Current maintenance backlog (historical R0 items reconciled)

The original R0 list is reconciled here so completed work is not mistaken for
an open gap. Remaining items are intentionally outside the current local seal.

1. **Notifier reads the ledger instead of the text log** — point
   `src/desktidy-notify.sh` at `receipts/ledger.jsonl` (outcome=`moved` lines)
   instead of tailing `desktidy.log`; gains failure banners for `failed`
   receipts. R1.
2. **Public CLI Undo remains intentionally absent.** Exact receipt-bound Undo
   is implemented in `CanonicalApplicationCore`, the native menu, and its
   bounded intent bridge. Do not add a second movement path.
3. **WhereDidItGo is complete in the canonical history query and bounded App
   Intent.** Keep future presentation changes ledger-derived.
4. **General automatic takeover remains absent.** The local deployment used a
   separately authorized, plan-first, rollback-backed migration transaction.
5. **Ledger rotation/compaction** — `ledger.jsonl` grows unbounded; add
   size-gated rotation that re-anchors the hash chain with a checkpoint
   record. The current bounded history reader fails closed above 4 MiB/10,000
   records; complete rotation before a distributed release can plausibly reach
   that limit.
6. **Receipt-aware `--smart-now` summary** — `sort-now` could print the
   receipts it just produced (currently prints counts only).
7. **`launchctl` state caching** — the guard shells out per label; a single
   `launchctl print gui/<uid>` parse would cut setup latency. Micro-perf only.
