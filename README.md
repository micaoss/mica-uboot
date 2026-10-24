# mica-uboot

The U-Boot sources Mica OS builds from: upstream trees mirrored unchanged, and one branch per board U-Boot variant
carrying Mica OS's commits on top. mica-build pins each variant by commit (`git <board>-uboot
https://github.com/micaoss/mica-uboot.git mica/<board>-<function> <commit>` in `locks/upstream.lock`); U-Boot is
**not** synced automatically. This branch (`main`) carries only this file, the update rows ([sync.tsv](sync.tsv)), the
update script ([scripts/sync.sh](scripts/sync.sh)) and its manual workflow.

## Branches

| Kind | Branch | What it is |
| --- | --- | --- |
| mirror | `<origin>/<upstream branch or release>` | an upstream tree, its commits unchanged, full history; only fast-forwarded |
| board | `mica/<board>-<function>` | one U-Boot variant of a board: its mirror plus Mica OS's commits; only fast-forwarded |

`<function>` is the medium the boot ROM reads that loader from (`emmc`, `sd`, `nor`, `spinand`, ...) or, when two
variants share a medium, the loader's role (for example `-recovery`). A board may have several. One tree that the
build turns into several binaries (a debug and a production configuration) is one branch.

A mirror or board branch is never force-pushed or deleted, so every commit mica-build has pinned stays on its
branch.

### Mirrors

| Branch | Origin | Follows | Commit (2026-10-24) |
| --- | --- | --- | --- |
| `u-boot/v2026.07` (and tag `v2026.07`) | https://github.com/u-boot/u-boot.git | point releases `v2026.07.<n>` | `ece349ade2973e220f524ce59e59711cc919263f` (v2026.07) |
| `coreelec/odroidc5-v2023.01` | https://github.com/CoreELEC/u-boot.git | branch `odroidc5-v2023.01` | `5f7ac2b1dc4df2f466ed88c3958a8675873f8a1a` |
| `fifteenhex/mstar_rebase_mainline_20220624_dongshanpi_picow` | https://github.com/fifteenhex/u-boot.git | branch `mstar_rebase_mainline_20220624_dongshanpi_picow` | `6e1a42f610d861acc32331f6c66a0f0b7a5a0264` |

### Boards

| Branch | Loader, and where it boots from | Base mirror | Commits on the base |
| --- | --- | --- | --- |
| `mica/cx3576-emmc` | `u-boot-rockchip.bin` (idbloader + `u-boot.itb`) at sector 64 of the eMMC; the same image boots from microSD | `u-boot/v2026.07` | 10, mica-build `boards/cx3576/loader/patches` in `series` order |
| `mica/qemu-armhf-nor` | `u-boot.bin` at offset 0 of the first pflash (NOR) bank | `u-boot/v2026.07` | 1, mica-build `boards/qemu-armhf/loader/patches` |
| `mica/s905x5m-emmc` | the FIP (BL2, BL30, BL31, BL33) in eMMC boot0 | `coreelec/odroidc5-v2023.01` | 12, the mica-build `boards/s905x5m/loader/patches` its loader Dockerfile applied (0001-0007, 0019-0023) |
| `mica/ssd202d-spinand` | SPL and U-Boot proper in raw SPI NAND | `fifteenhex/mstar_rebase_mainline_20220624_dongshanpi_picow` | the ssd202d board series |

Each board commit is one former mica-build patch, applied with `git apply` as mica-build applied it, and names its
source in a `Mica-Patch:` trailer (mica-build commit and patch path). A board tree equals the tree mica-build's
loader build patched from the same base (checked when the branch was cut). Files mica-build adds at build time (the
boot policy sources, board configs and blobs) are not part of these branches. A board that needs plain mainline
pins the `u-boot/v2026.07` mirror.

## Making a change

A change to a variant is a commit on `mica/<board>-<function>`:

1. Start from the branch, add the commit(s), and build and test the board in mica-build against the result.
2. Push the branch as a fast-forward.
3. Move the board's row in mica-build to the new commit.

A new variant is a new branch from the variant it derives from (or from the mirror), a `board` row in
[sync.tsv](sync.tsv) and its own row in mica-build.

The commit subject and body say what the change does and why, as in U-Boot's own history.

## Updating U-Boot

Moving a board to a newer U-Boot is a deliberate round, never a schedule: run the [sync](.github/workflows/sync.yml)
workflow by hand (a dry run first), or `scripts/sync.sh` in a clone. For each `mirror` row of
[sync.tsv](sync.tsv) it fetches the upstream and fast-forwards the mirror branch; a `release:<tag>` row follows only
the point releases of that release (`<tag>.<n>`), a `branch:<name>` row that branch's head. Then every board whose
`mica/<board>-<function>` does not contain its mirror's head gets one merge commit of that head, and the branch is
pushed as a fast-forward. Moving to the next release (for mainline, the next `vYYYY.MM`) is a new `mirror` row and the
boards' rows pointed at it, then a run.

A row that cannot go through pushes nothing for that row, is written to the run's report and the run fails with an
issue titled `sync <date>: rows need a human`; the other rows still go through. The cases: an upstream that is not
a fast-forward of the mirror (upstream rewrote history; following it means a new mirror branch, never a force-push)
and a merge that conflicts (resolve it by hand on the branch, as in "Making a change").

After a run, build and test each moved board, then move its row in mica-build.
