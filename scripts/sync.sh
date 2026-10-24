#!/usr/bin/env bash
# The weekly sync (README.md, "Sync"): fast-forward every mirror branch to its upstream, then cut a dated snapshot
# of every board whose mirror moved, its commits cherry-picked onto the new mirror head.
#
#   scripts/sync.sh [--dry-run]
#
# Runs in a clone of this repository whose `origin` it pushes to. Environment:
#   SYNC_DATE   the snapshot date, YYYYMMDD (default: today, UTC)
#   SYNC_TIME   HHMM, the suffix of a second snapshot the same day, mica/<board>-YYYYMMDD-HHMM (default: now, UTC)
#   SYNC_CONFIG the rows (default: sync.tsv at the repository root)
#   SYNC_REPORT where the rows that need a human are written, one per line (default: sync-report.txt)
#
# Nothing is ever force-pushed except a moving head mica/<board>, and that only with a lease on the value it had
# when this run fetched it. A mirror whose upstream is not a fast-forward, a cherry-pick that conflicts or a
# snapshot name already taken (the -HHMM one too) stops that row and is written to the report; the other rows go on. The exit
# status is 1 when the report is not empty.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" != "--dry-run" ] || DRY_RUN=1
DATE="${SYNC_DATE:-$(date -u +%Y%m%d)}"
TIME="${SYNC_TIME:-$(date -u +%H%M)}"
REPORT="${SYNC_REPORT:-sync-report.txt}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${SYNC_CONFIG:-${ROOT}/sync.tsv}"
[[ "$DATE" =~ ^[0-9]{8}$ ]] || { echo "error: SYNC_DATE=${DATE} is not YYYYMMDD" >&2; exit 2; }
[[ "$TIME" =~ ^[0-9]{4}$ ]] || { echo "error: SYNC_TIME=${TIME} is not HHMM" >&2; exit 2; }
: > "$REPORT"

need_human() { echo "$*" | tee -a "$REPORT" >&2; }
push() { if [ "$DRY_RUN" -eq 1 ]; then echo "dry-run: git push origin $*"; else git push --quiet origin "$@"; fi; }
remote_ref() { git ls-remote origin "refs/heads/$1" | cut -f1; }

rows() { sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CONFIG" | awk -F'\t' -v k="$1" '$1 == k'; }

# The head of every mirror after this run: where each board must be based.
declare -A MIRROR
while IFS=$'\t' read -r _ branch url follow; do
    # A new row (a new release line is a human decision) has no branch yet: this run creates it.
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
    snapshot="mica/${board}-${DATE}"
    target="${MIRROR[$mirror]:-}"
    [ -n "$target" ] || { need_human "board ${board}: no mirror row ${mirror}"; continue; }
    current="$(remote_ref "$head")"
    [ -n "$current" ] || { echo "board ${board}: no ${head} yet, skipped"; continue; }
    git fetch --quiet --no-tags origin "+refs/heads/${head}:refs/sync/head/${board}"
    # Based on the mirror head already: nothing to do. Otherwise this also catches up a board a previous run left
    # behind on a conflict, since the mirror it follows has moved on without it.
    if git merge-base --is-ancestor "$target" "refs/sync/head/${board}"; then
        echo "board ${board}: ${head} is on ${mirror} ${target}"
        continue
    fi
    base="$(git merge-base "$target" "refs/sync/head/${board}" || true)"
    [ -n "$base" ] || { need_human "board ${board}: ${head} (${current}) shares no history with ${mirror}"; continue; }
    # A second cut the same day is mica/<board>-YYYYMMDD-HHMM, which sorts after the plain date as a string.
    [ -z "$(remote_ref "$snapshot")" ] || snapshot="${snapshot}-${TIME}"
    if [ -n "$(remote_ref "$snapshot")" ]; then
        need_human "board ${board}: ${snapshot} already exists; snapshots are never rewritten"
        continue
    fi
    wt="$(mktemp -d)/${board}"
    git worktree add --quiet --detach "$wt" "$target"
    picks="$(git rev-list --reverse --no-merges "${base}..refs/sync/head/${board}")"
    failed=""
    for c in $picks; do
        git -C "$wt" cherry-pick "$c" >/dev/null 2>&1 && continue
        # A commit the new upstream already carries applies as nothing: drop it. Anything else is a conflict.
        if [ -z "$(git -C "$wt" ls-files -u)" ] && git -C "$wt" diff --cached --quiet; then
            echo "board ${board}: $(git log -1 --format='%h %s' "$c") is already upstream, dropped"
            git -C "$wt" cherry-pick --skip
            continue
        fi
        failed="$c"
        git -C "$wt" cherry-pick --abort || true
        break
    done
    tip="$(git -C "$wt" rev-parse HEAD)"
    git worktree remove --force "$wt"
    if [ -n "$failed" ]; then
        need_human "board ${board}: $(git log -1 --format='%h %s' "$failed") does not apply on ${mirror} ${target}; nothing pushed"
        continue
    fi
    echo "board ${board}: ${snapshot} = ${tip} ($(git rev-list --count "${target}..${tip}") commits on ${mirror} ${target})"
    push "${tip}:refs/heads/${snapshot}"
    push --force-with-lease="refs/heads/${head}:${current}" "${tip}:refs/heads/${head}"
done < <(rows board)

[ ! -s "$REPORT" ] || exit 1
