#!/usr/bin/env bash
# The manual U-Boot update (README.md, "Updating U-Boot"): fast-forward every mirror branch to its upstream, then
# merge the new mirror head into every board that is not on it yet. Run only when an update is wanted; nothing
# schedules it.
#
#   scripts/sync.sh [--dry-run]
#
# Runs in a clone of this repository whose `origin` it pushes to. Environment:
#   SYNC_CONFIG the rows (default: sync.tsv at the repository root)
#   SYNC_REPORT where the rows that need a human are written, one per line (default: sync-report.txt)
#
# Nothing is ever force-pushed: a mirror and a mica/<board>-<function> branch only move forward, so every commit a build has
# pinned stays on its branch. A mirror whose upstream is not a fast-forward or a merge that conflicts stops that
# row and is written to the report; the other rows go on. The exit status is 1 when the report is not empty.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" != "--dry-run" ] || DRY_RUN=1
REPORT="${SYNC_REPORT:-sync-report.txt}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${SYNC_CONFIG:-${ROOT}/sync.tsv}"
: > "$REPORT"

need_human() { echo "$*" | tee -a "$REPORT" >&2; }
push() { if [ "$DRY_RUN" -eq 1 ]; then echo "dry-run: git push origin $*"; else git push --quiet origin "$@"; fi; }
remote_ref() { git ls-remote origin "refs/heads/$1" | cut -f1; }

rows() { sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CONFIG" | awk -F'\t' -v k="$1" '$1 == k'; }

# The head of every mirror after this run: where each board must be based.
declare -A MIRROR
while IFS=$'\t' read -r _ branch url follow; do
    # A new row (a new U-Boot release line) has no branch yet: this run creates it.
    old=""
    if [ -n "$(remote_ref "$branch")" ]; then
        git fetch --quiet --no-tags origin "+refs/heads/${branch}:refs/sync/old/${branch}"
        old="$(git rev-parse "refs/sync/old/${branch}")"
        MIRROR[$branch]="$old"
    fi
    case "$follow" in
    branch:*)
        ref="refs/heads/${follow#branch:}"
        ;;
    release:*)
        line="${follow#release:}"
        tag="$(git ls-remote --tags --refs "$url" "refs/tags/${line}*" | cut -f2 | sed 's|^refs/tags/||' \
            | grep -E "^${line//./\\.}(\\.[0-9]+)?$" | sort -V | tail -1)"
        [ -n "$tag" ] || { need_human "mirror ${branch}: no tag ${line} at ${url}"; continue; }
        ref="refs/tags/${tag}"
        ;;
    *)
        need_human "mirror ${branch}: unknown follow ${follow}"; continue
        ;;
    esac
    git fetch --quiet --no-tags "$url" "+${ref}:refs/sync/new/${branch}"
    new="$(git rev-parse "refs/sync/new/${branch}^{commit}")"
    if [ "$new" = "$old" ]; then
        echo "mirror ${branch}: unchanged at ${old}"
        continue
    fi
    if [ -n "$old" ] && ! git merge-base --is-ancestor "$old" "$new"; then
        need_human "mirror ${branch}: upstream ${ref} (${new}) is not a fast-forward of ${old}; nothing pushed"
        continue
    fi
    echo "mirror ${branch}: ${old:-new} -> ${new} (${ref})"
    push "${new}:refs/heads/${branch}"
    [ "${ref#refs/tags/}" = "$ref" ] || push "refs/sync/new/${branch}:${ref}"
    MIRROR[$branch]="$new"
done < <(rows mirror)

while IFS=$'\t' read -r _ board mirror; do
    head="mica/${board}"
    target="${MIRROR[$mirror]:-}"
    [ -n "$target" ] || { need_human "board ${board}: no mirror row ${mirror}"; continue; }
    current="$(remote_ref "$head")"
    [ -n "$current" ] || { echo "board ${board}: no ${head} yet, skipped"; continue; }
    git fetch --quiet --no-tags origin "+refs/heads/${head}:refs/sync/head/${board}"
    if git merge-base --is-ancestor "$target" "refs/sync/head/${board}"; then
        echo "board ${board}: ${head} is on ${mirror} ${target}"
        continue
    fi
    # The update is one merge commit on top of the board's history, so the branch only fast-forwards and the
    # board's own commits stay one per change below it.
    wt="$(mktemp -d)/${board}"
    git worktree add --quiet --detach "$wt" "refs/sync/head/${board}"
    if ! git -C "$wt" merge --quiet --no-ff --no-edit \
        -m "Merge ${mirror} $(git describe --tags --always "$target") into ${head}" "$target" >/dev/null 2>&1; then
        conflicts="$(git -C "$wt" diff --name-only --diff-filter=U | paste -sd' ')"
        git -C "$wt" merge --abort || true
        git worktree remove --force "$wt"
        need_human "board ${board}: merging ${mirror} ${target} into ${head} conflicts in ${conflicts:-?}; nothing pushed"
        continue
    fi
    tip="$(git -C "$wt" rev-parse HEAD)"
    git worktree remove --force "$wt"
    echo "board ${board}: ${head} ${current} -> ${tip} (merged ${mirror} ${target})"
    push "${tip}:refs/heads/${head}"
done < <(rows board)

[ ! -s "$REPORT" ] || exit 1
