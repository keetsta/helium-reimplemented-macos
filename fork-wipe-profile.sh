#!/usr/bin/env bash
#
# fork-wipe-profile — wipe ONLY the fork's local data for a clean onboarding test.
#
# The fork ("Helium Reimplemented") stores everything under the macOS product
# dir / bundle id `net.imput.helium.reimplemented`. Stock Helium lives under
# `net.imput.helium` and is NEVER touched by this script.
#
# Removes the fork's user data (profile), caches, saved window state, web
# storages and the preferences plist — i.e. a true first-run state so the
# onboarding flow shows again.
#
# Refuses to run while the fork browser is open (it would just recreate the
# files and/or corrupt them).
#
# Usage:
#   ./fork-wipe-profile.sh           # ask for confirmation, then wipe
#   ./fork-wipe-profile.sh -y        # wipe without confirmation
#   ./fork-wipe-profile.sh -n        # dry run: show what would be removed
#
set -euo pipefail

# macOS product dir / bundle id of the FORK. Keep in sync with
# patches/helium/macos/change-product-dir-name.patch and MAC_BUNDLE_ID.
PRODUCT="net.imput.helium.reimplemented"
APP_NAME="Helium Reimplemented"   # used to detect a running instance

# Hard safety net: this script must only ever target the fork. If PRODUCT does
# not clearly name the reimplemented fork, bail out before deleting anything.
case "$PRODUCT" in
  *reimplemented*) ;;
  *) echo "refusing: PRODUCT ('$PRODUCT') is not the fork — aborting" >&2; exit 1 ;;
esac

ASSUME_YES=false
DRY_RUN=false
while getopts 'yn' opt; do
  case "$opt" in
    y) ASSUME_YES=true ;;
    n) DRY_RUN=true ;;
    ?) echo "usage: $0 [-y] [-n]" >&2; exit 1 ;;
  esac
done

_lib="$HOME/Library"
TARGETS=(
  "$_lib/Application Support/$PRODUCT"
  "$_lib/Caches/$PRODUCT"
  "$_lib/Saved Application State/$PRODUCT.savedState"
  "$_lib/HTTPStorages/$PRODUCT"
  "$_lib/WebKit/$PRODUCT"
  "$_lib/Preferences/$PRODUCT.plist"
)

# Bail out if the fork is running (it would recreate/corrupt the files). Match
# the fork's app bundle specifically so a running stock Helium ("Helium.app")
# does not trip this. Skipped for dry runs, which only read.
if ! $DRY_RUN && pgrep -f "${APP_NAME}.app/Contents/MacOS/" >/dev/null 2>&1; then
  echo "error: '$APP_NAME' is running — quit it first, then re-run." >&2
  exit 1
fi

# Collect the targets that actually exist.
EXISTING=()
for t in "${TARGETS[@]}"; do
  [ -e "$t" ] && EXISTING+=("$t")
done

if [ "${#EXISTING[@]}" -eq 0 ]; then
  echo "Nothing to wipe — no fork data found for '$PRODUCT'."
  exit 0
fi

echo "Fork data to remove (product: $PRODUCT):"
for t in "${EXISTING[@]}"; do
  echo "  - $t"
done

if $DRY_RUN; then
  echo "(dry run — nothing removed)"
  exit 0
fi

if ! $ASSUME_YES; then
  printf "Remove the above? [y/N] "
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "aborted."; exit 0 ;;
  esac
fi

for t in "${EXISTING[@]}"; do
  rm -rf "$t"
  echo "removed: $t"
done

echo "Done. Next launch of '$APP_NAME' starts fresh (onboarding will show)."
