# R2 five-root Desktop layout repair — 2026-08-15

## User-visible defect and cause

The intended visible Desktop routing roots are exactly:

1. `Archive`
2. `Docs`
3. `Inbox`
4. `Media`
5. `Projects`

The native category table incorrectly used flat `Documents` and `Screenshots`
destinations. Live receipts and `desktidy.log` proved that DeskTidy—not Finder
or the inactive legacy sorter—created and used them. Receipt IDs
`76A4212D-938A-40A9-B020-EF59C5E25C41`,
`2605F213-9B4F-400E-B308-241A17C81FBD`, and
`38BDFE4D-F46C-45BE-9EF1-4079D57F5AB2` routed three screenshots to the
unauthorized root.

## Live recovery

`com.desktidy.sort` was booted out before recovery. The notifier remained
loaded; both legacy `com.sicarii.desktop-autosort*` services remained absent.

The three files were moved collision-free into `Media/Screenshots`. Each kept
its inode and SHA-256:

| File | Inode | SHA-256 |
|---|---:|---|
| `Screenshot 2026-08-15 at 6.22.02 AM.png` | `456327364` | `2b3762bb5bbb4ecef038f6bddc0af863a507f896c7eee51257f002a12b2cfadd` |
| `Screenshot 2026-08-15 at 6.43.00 AM.png` | `456464592` | `d4440e2c0abf9057e4f84c582b633853411ef2a25585cb10e7cf60dfc29fed52` |
| `Screenshot 2026-08-15 at 6.43.08 AM.png` | `456465042` | `273003364cb47d3e7bce48cc7a1227e56f70b066f8d74745169c091e9b70e470` |

The now-empty `Documents` and `Screenshots` directories were not deleted.
They were moved into the recoverable support location:

`~/Library/Application Support/DeskTidy Layout Recovery/20260815T105500Z-five-root-repair`

Read-only enumeration then showed exactly the five intended visible roots.

## Permanent correction

Routing policy version 2 maps every category beneath the five established
roots. Examples include `Media/Screenshots`, `Media/Images`,
`Docs/Notes-and-Misc`, and `Archive/Misc`. `Category.reservedRootNames` is now
derived from the first component and equals the exact five-root set.

Nested configuration, receipt reconciliation, Undo, history, notifications,
and Where Did It Go now accept bounded relative paths while rejecting absolute,
empty, traversal, and symlinked components. Hostile controls cover destination
symlinks, crash reconciliation, exact Undo, schema traversal, and the fixed
five-root reservation.
