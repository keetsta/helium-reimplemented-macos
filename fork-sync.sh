#!/usr/bin/env bash
#
# fork-sync — pull new core/platform commits and apply ONLY the patch delta to
# the already-unpacked build/src tree, so a quick `fork-rebuild` picks them up
# without a full (hours-long) `fork-build` re-clone+re-patch.
#
# It is deliberately conservative: it backs up every file a changed patch
# touches, reverses the OLD version of each changed patch and forward-applies
# the NEW one, and if ANYTHING fails to apply cleanly it restores the backups
# and tells you to run a full `fork-build`. The tree is never left half-patched.
#
# A marker file (build/.fork-sync-marker) records the core + platform commits
# that build/src currently reflects. `fork-build` writes it automatically right
# after applying patches, and every successful sync updates it. There is no
# manual "stamp the marker" option on purpose: an honest marker can only come
# from a clean build, so the only way to (re)create one is to run ./fork-build.
#
# Cases it intentionally refuses (→ run a full ./fork-build):
#   - build-affecting non-patch changes (deps.ini, *.list, resources/, *.gn,
#     version files): those need re-download/unpack or grit/gn work.
#   - any changed patch that does not reverse/apply cleanly (context drift).
#   - no marker yet, or build/src hand-edited off the recorded baseline.
#
# Usage:
#   ./fork-sync.sh               # pull, apply the delta, report
#   ./fork-sync.sh --rebuild     # ...and run ./fork-rebuild on success (-r)
#   ./fork-sync.sh --dry-run     # preview the incoming delta (read-only fetch) (-n)
#   ./fork-sync.sh --no-pull     # skip git pull / submodule update
#
set -euo pipefail

_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_src="$_root/build/src"
_core="$_root/helium-chromium"
_marker="$_root/build/.fork-sync-marker"

DRY_RUN=false DO_REBUILD=false DO_PULL=true
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=true ;;
    --rebuild|-r) DO_REBUILD=true ;;
    --no-pull) DO_PULL=false ;;
    *) echo "usage: $0 [--dry-run|-n] [--rebuild|-r] [--no-pull]" >&2; exit 1 ;;
  esac
done

die() { echo "fork-sync: $*" >&2; exit 1; }
note() { echo "==> $*"; }

[ -d "$_src" ] || die "no build/src — run ./fork-build first."

[ -f "$_marker" ] || die "no marker ($_marker). Run a clean ./fork-build (it writes the marker)."
CORE_SHA=""; PLATFORM_SHA=""
# shellcheck disable=SC1090
source "$_marker"
OLD_CORE="$CORE_SHA"; OLD_PLATFORM="$PLATFORM_SHA"
[ -n "$OLD_CORE" ] && [ -n "$OLD_PLATFORM" ] || die "marker is malformed; re-run a clean ./fork-build."

# 1) Pull new commits.
if $DRY_RUN; then
  # Preview must reflect what a real sync WOULD bring, without mutating anything.
  # Fetch is read-only (updates remote-tracking refs only). The target core is
  # the submodule pointer recorded in the incoming platform origin/main — exactly
  # what `submodule update` would check out after a real pull.
  if $DO_PULL; then
    note "fetching (read-only) for preview"
    git -C "$_root" fetch --quiet
    git -C "$_core" fetch --quiet
    NEW_PLATFORM="$(git -C "$_root" rev-parse origin/main)"
    NEW_CORE="$(git -C "$_root" rev-parse origin/main:helium-chromium)"
  else
    NEW_PLATFORM="$(git -C "$_root" rev-parse HEAD)"
    NEW_CORE="$(git -C "$_core" rev-parse HEAD)"
  fi
else
  if $DO_PULL; then
    note "pulling platform repo + submodule"
    git -C "$_root" pull --ff-only
    git -C "$_root" submodule update --init --recursive
  fi
  NEW_PLATFORM="$(git -C "$_root" rev-parse HEAD)"
  NEW_CORE="$(git -C "$_core" rev-parse HEAD)"
fi

if [ "$OLD_CORE" = "$NEW_CORE" ] && [ "$OLD_PLATFORM" = "$NEW_PLATFORM" ]; then
  note "already in sync (core $OLD_CORE, platform $OLD_PLATFORM). Nothing to do."
  exit 0
fi

# 2) Gather changed files in each repo's patches/ between baseline and HEAD.
#    Format per line: "<repo_dir>\t<status>\t<repo-rel-path>"
changes="$(mktemp)"; affected="$(mktemp)"; trap 'rm -f "$changes" "$affected"' EXIT
collect() { # $1=repo_dir  $2=old  $3=new
  [ "$2" = "$3" ] && return 0
  git -C "$1" diff --name-status "$2" "$3" | while IFS=$'\t' read -r st path rest; do
    # rename shows as R100 old new — treat as delete old + add new
    case "$st" in
      R*) printf '%s\t%s\t%s\n' "$1" "D" "$path"; printf '%s\t%s\t%s\n' "$1" "A" "$rest" ;;
      *)  printf '%s\t%s\t%s\n' "$1" "$st" "$path" ;;
    esac
  done >> "$changes"
}
collect "$_core" "$OLD_CORE" "$NEW_CORE"
collect "$_root" "$OLD_PLATFORM" "$NEW_PLATFORM"

# 3) Partition into patch changes vs risky/ignorable non-patch changes.
risky=()
patch_lines=()
while IFS=$'\t' read -r repo st path; do
  [ -n "${path:-}" ] || continue
  case "$path" in
    patches/*.patch) patch_lines+=("$repo	$st	$path") ;;
    patches/series)  risky+=("$path (series changed — order/add/remove)") ;;
    # The submodule gitlink flips on every core bump; the actual core changes
    # are diffed separately (OLD_CORE..NEW_CORE), so it is not itself risky.
    helium-chromium) : ;;
    # Things that never affect the patched build/src tree: docs, CI, the helper
    # scripts themselves (run by fork-build, not applied to the tree), tests.
    *.md|*/CLAUDE.md|docs/*|.github/*|.vscode/*|*.sh|fork-build|fork-rebuild|.gitignore|.gitmodules|.gitattributes|LICENSE*|*.bat|*.ps1|tests/*|*/tests/*)
        : ;;
    *)  risky+=("$path") ;;
  esac
done < "$changes"

if [ "${#risky[@]}" -gt 0 ]; then
  echo "fork-sync: build-affecting non-patch changes detected — a delta is not safe:" >&2
  printf '   - %s\n' "${risky[@]}" >&2
  die "run a full ./fork-build instead."
fi

if [ "${#patch_lines[@]}" -eq 0 ]; then
  note "only harmless (docs/ci/scripts) changes; no patch delta to apply."
  $DRY_RUN || printf 'CORE_SHA=%s\nPLATFORM_SHA=%s\n' "$NEW_CORE" "$NEW_PLATFORM" > "$_marker"
  $DO_REBUILD && ! $DRY_RUN && { note "running fork-rebuild"; "$_root/fork-rebuild"; }
  exit 0
fi

# Helper: series index of a repo-rel patch path (for apply ordering).
sidx() { # $1=repo_dir $2=repo-rel-path(patches/..)
  local rel="${2#patches/}" n
  n="$(grep -nxF "$rel" "$1/patches/series" 2>/dev/null | head -1 | cut -d: -f1)" || true
  echo "${n:-999999}"
}
# Helper: files a patch touches (strip "+++ b/").
patch_targets() { grep '^+++ b/' | sed 's#^+++ b/##'; }

# 4) Build the work list with series order, and the set of affected files.
note "patch delta:"
REV=(); FWD=()                # "idx<TAB>repo<TAB>path" (indexed arrays: bash 3.2 ok)
for line in "${patch_lines[@]}"; do
  IFS=$'\t' read -r repo st path <<< "$line"
  i="$(sidx "$repo" "$path")"
  echo "   [$st] ${path}"
  # collect affected files (relative to build/src) from old and/or new versions
  if [ "$st" != "A" ]; then
    obase="$( [ "$repo" = "$_core" ] && echo "$OLD_CORE" || echo "$OLD_PLATFORM" )"
    git -C "$repo" show "$obase:$path" | patch_targets >> "$affected"
    REV+=("$i	$repo	$path")
  fi
  if [ "$st" != "D" ]; then
    nbase="$( [ "$repo" = "$_core" ] && echo "$NEW_CORE" || echo "$NEW_PLATFORM" )"
    git -C "$repo" show "$nbase:$path" | patch_targets >> "$affected"
    FWD+=("$i	$repo	$path")
  fi
done
sort -u "$affected" -o "$affected"

if $DRY_RUN; then
  echo "   affected files: $(wc -l < "$affected" | tr -d ' ')"
  sed 's/^/     /' "$affected"
  note "(dry run — nothing changed)"
  exit 0
fi

# 5) Back up affected files; remember which were absent (new-file patches).
backup="$(mktemp -d)"
created="$(mktemp)"; trap 'rm -f "$changes" "$affected" "$created"' EXIT
while read -r f; do
  [ -n "$f" ] || continue
  if [ -e "$_src/$f" ]; then
    mkdir -p "$backup/$(dirname "$f")"
    cp -p "$_src/$f" "$backup/$f"
  else
    echo "$f" >> "$created"
  fi
done < "$affected"

restore() {
  echo "fork-sync: apply failed — restoring tree." >&2
  while read -r f; do
    [ -n "$f" ] || continue
    [ -e "$backup/$f" ] && cp -p "$backup/$f" "$_src/$f"
    rm -f "$_src/$f.rej" "$_src/$f.orig"
  done < "$affected"
  while read -r f; do [ -n "$f" ] && rm -f "$_src/$f"; done < "$created"
  rm -rf "$backup"
  die "delta did not apply cleanly — run a full ./fork-build."
}

apply_one() { # $1=mode(-R|--forward) $2=patchfile
  if ! patch -p1 --ignore-whitespace --no-backup-if-mismatch "$1" -d "$_src" -i "$2" >/dev/null 2>&1; then
    return 1
  fi
}

note "applying delta to build/src"
# reverse OLD versions (highest series index first)
while IFS=$'\t' read -r i repo path; do
  [ -n "${path:-}" ] || continue
  old="$( [ "$repo" = "$_core" ] && echo "$OLD_CORE" || echo "$OLD_PLATFORM" )"
  tmp="$(mktemp)"; git -C "$repo" show "$old:$path" > "$tmp"
  apply_one -R "$tmp" || { rm -f "$tmp"; restore; }
  rm -f "$tmp"
done < <(printf '%s\n' "${REV[@]:-}" | sort -t$'\t' -k1,1nr)

# forward NEW versions (lowest series index first)
while IFS=$'\t' read -r i repo path; do
  [ -n "${path:-}" ] || continue
  apply_one --forward "$repo/$path" || restore
done < <(printf '%s\n' "${FWD[@]:-}" | sort -t$'\t' -k1,1n)

# success
rm -rf "$backup"
printf 'CORE_SHA=%s\nPLATFORM_SHA=%s\n' "$NEW_CORE" "$NEW_PLATFORM" > "$_marker"
note "delta applied. marker updated (core $NEW_CORE)."

if $DO_REBUILD; then
  note "running fork-rebuild"
  "$_root/fork-rebuild"
else
  note "now run ./fork-rebuild to compile the change."
fi
