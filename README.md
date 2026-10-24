# mica-uboot

The U-Boot sources Mica OS builds from: upstream trees mirrored unchanged, one branch per board carrying Mica OS's
commits on top, and dated snapshots of both that a build pins. The scheme is the same as
[micaoss/mica-linux](https://github.com/micaoss/mica-linux). This branch (`main`) carries only this file, the sync
rows ([sync.tsv](sync.tsv)), the sync script ([scripts/sync.sh](scripts/sync.sh)) and its weekly workflow.

## Branches

| Kind | Branch | What it is |
| --- | --- | --- |
| mirror | `<origin>/<upstream branch or release>` | an upstream tree, its commits unchanged, full history; only fast-forwarded |
| snapshot | `mica/<board>-<YYYYMMDD>`, a second one the same day `mica/<board>-<YYYYMMDD>-<HHMM>` (UTC) | a board's tree as of that date; never moved or deleted |
| moving head | `mica/<board>` | the newest snapshot of the board |

`general` is the board name for the plain mainline tree: `mica/general-<YYYYMMDD>` is the U-Boot mirror head with no
commits on top, the default for a board that needs no change and the source of the FIT host tools.

### Mirrors

| Branch | Origin | Follows | Commit (2026-10-24) |
| --- | --- | --- | --- |
| `u-boot/v2026.07` (and tag `v2026.07`) | https://github.com/u-boot/u-boot.git | point releases `v2026.07.<n>` | `ece349ade2973e220f524ce59e59711cc919263f` (v2026.07) |
| `coreelec/odroidc5-v2023.01` | https://github.com/CoreELEC/u-boot.git | branch `odroidc5-v2023.01` | `5f7ac2b1dc4df2f466ed88c3958a8675873f8a1a` |
| `fifteenhex/mstar_rebase_mainline_20220624_dongshanpi_picow` | https://github.com/fifteenhex/u-boot.git | branch `mstar_rebase_mainline_20220624_dongshanpi_picow` | `6e1a42f610d861acc32331f6c66a0f0b7a5a0264` |

### Boards

| Board | Base mirror | Commits on the base | First snapshot |
| --- | --- | --- | --- |
| `general` | `u-boot/v2026.07` | none | `mica/general-20261024` |
| `cx3576` | `u-boot/v2026.07` | 10, mica-build `boards/cx3576/loader/patches` in `series` order | `mica/cx3576-20261024` |
| `qemu-armhf` | `u-boot/v2026.07` | 1, mica-build `boards/qemu-armhf/loader/patches` | `mica/qemu-armhf-20261024` |
| `s905x5m` | `coreelec/odroidc5-v2023.01` | 12, the mica-build `boards/s905x5m/loader/patches` its loader Dockerfile applies (0001-0007, 0019-0023) | `mica/s905x5m-20261024` |
| `ssd202d` | `fifteenhex/mstar_rebase_mainline_20220624_dongshanpi_picow` | the ssd202d board series | pushed by the ssd202d board work |

Each board commit is one mica-build patch, applied with `git apply` as mica-build applies it, and names its source
in a `Mica-Patch:` trailer (mica-build commit and patch path). A board tree equals the tree mica-build's loader build
patches from the same base (checked when each first snapshot was cut). Files mica-build adds at build time (the boot
policy sources, board configs and blobs) are not part of these branches.

## Sync

[sync.yml](.github/workflows/sync.yml) runs [scripts/sync.sh](scripts/sync.sh) every Monday at 03:17 UTC (and on
demand, with a dry run option). For each `mirror` row of [sync.tsv](sync.tsv) it fetches the upstream and
fast-forwards the mirror branch; a `release:<tag>` row follows only the point releases of that release
(`<tag>.<n>`), and a `branch:<name>` row follows that branch's head. Then every board whose `mica/<board>` is not
based on its mirror's head gets its commits (merge base to `mica/<board>`) cherry-picked onto that head, in order;
the result is pushed as `mica/<board>-<date>` (`mica/<board>-<date>-<HHMM>` when that day already has one) and
`mica/<board>` moves to it. A commit the new upstream already
carries applies as nothing and is dropped.

The rules: a mirror is only ever fast-forwarded; a snapshot is only ever created; `mica/<board>` is the one ref that
moves to a rebased tree, and only with a lease on the value the run read. A build pins a snapshot (`mica-build`
`locks update` picks the newest dated branch of the row: the greatest name as a string, so `-<HHMM>` comes after the
plain date), never a moving head or a mirror.

A new U-Boot release (for mainline, the next `vYYYY.MM`) is a human decision: add its `mirror` row, point the
boards' rows at it, and the next run creates the mirror and rebases those boards onto it.

## Conflicts

A row that cannot go through pushes nothing for that row, is written to the run's report and the run fails with an
issue titled `sync <date>: rows need a human`; the other rows still go through. The cases: an upstream that is not a
fast-forward of the mirror (upstream rewrote history), a board commit that does not apply on the new base, and a
snapshot name that is already taken, the `-<HHMM>` one included. A board left behind is retried on every run until it is resolved, since its
`mica/<board>` stays off its mirror's head.

To resolve a conflict, rebase the board's commits onto the mirror head by hand, and push the result as a new snapshot
and the moving head, as in "Making a change". For a rewritten upstream, decide whether to follow it; a mirror is
never force-pushed, so following it means a new mirror branch and new board rows.

## Making a change

A change to a board is a commit on its tree, made the same way the sync makes one:

1. Start from `mica/<board>`, add the commit(s), and build and test the board in mica-build against the result.
2. Push it as `mica/<board>-<YYYYMMDD>` (today, UTC), or `mica/<board>-<YYYYMMDD>-<HHMM>` when today already has
   one, and fast-forward `mica/<board>` to it. An existing snapshot name is never reused.
3. Pin the snapshot in mica-build (`locks update`).

The commit subject and body say what the change does and why, as in U-Boot's own history. A change meant for every
board belongs upstream first; a board that only needs plain mainline uses `mica/general-<date>`.
