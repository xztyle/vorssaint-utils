#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint and Aster contributors

# Remove this fork only. Never remove upstream Vorssaint or its saved state.
# Hardware restoration must finish before deleting the app or its preferences.
set -uo pipefail

BUNDLE="io.github.xztyle.Aster"
APP="/Applications/Aster.app"
EXECUTABLE="Aster"
if [[ "${1:-}" == "--dev" ]]; then
    BUNDLE="io.github.xztyle.Aster.dev"
    APP="/Applications/Aster (Developer).app"
    EXECUTABLE="AsterDeveloper"
elif (( $# )); then
    print -u2 "Usage: $0 [--dev]"
    exit 2
fi

refuse_removal() {
    print -u2 "Aster remains installed: $1"
    print -u2 "Open Aster, return battery and fan control to macOS, then try removal again."
    exit 1
}

service_absent() {
    /bin/launchctl print "system/$1" >/dev/null 2>&1
    # Only the explicit 'no such service' result proves absence.
    [[ $? == 113 ]]
}

print "▸ Restoring hardware and detaching Aster services…"
if /usr/bin/pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
    /usr/bin/osascript -e "tell application id \"$BUNDLE\" to quit" \
        || refuse_removal "Aster could not finish its recovery before quitting."
    for attempt in {1..15}; do
        /usr/bin/pgrep -x "$EXECUTABLE" >/dev/null 2>&1 || break
        /bin/sleep 1
    done
    /usr/bin/pgrep -x "$EXECUTABLE" >/dev/null 2>&1 \
        && refuse_removal "Aster is still restoring its state."
fi
candidate="$APP/Contents/MacOS/$EXECUTABLE"
if [[ -x "$candidate" ]]; then
    "$candidate" --uninstall || refuse_removal "hardware or service restoration failed."
else
    if /usr/bin/defaults read "$BUNDLE" menuBarOrganizerBaseline >/dev/null 2>&1; then
        refuse_removal "menu layout recovery cannot be verified without Aster. Reinstall and restore the original layout first."
    fi
    [[ ! -d "/Library/Application Support/$BUNDLE.battery-care" ]] \
        || refuse_removal "the signed app is missing and battery recovery cannot be verified. Reinstall Aster first."
fi

for suffix in battery-care fan-control; do
    for attempt in {1..15}; do
        service_absent "$BUNDLE.$suffix" && break
        /bin/sleep 1
    done
    service_absent "$BUNDLE.$suffix" || refuse_removal "$suffix is still registered or its state is unknown."
done

# Aster's sleep preference is separate from the upstream app's preference.
if [[ "$(/usr/bin/defaults read "$BUNDLE" vorssDisabledSleep 2>/dev/null)" == "1" ]]; then
    sleep_state="$(/usr/bin/pmset -g 2>/dev/null | /usr/bin/awk '/SleepDisabled/ {print $2}')"
    [[ "$sleep_state" == "0" ]] || refuse_removal "normal sleep has not been verified."
fi

print "▸ Resetting Aster permissions…"
/usr/bin/tccutil reset All "$BUNDLE" >/dev/null 2>&1 \
    || refuse_removal "macOS refused permission cleanup."

# Keep the bundle recoverable if an unrelated later cleanup step fails.
if [[ -d "$APP" ]]; then
    /bin/mkdir -p "$HOME/.Trash"
    trash_target="$HOME/.Trash/$EXECUTABLE-$(/bin/date +%Y%m%d-%H%M%S).app"
    /bin/mv "$APP" "$trash_target" || refuse_removal "the app could not move to Trash."
fi

print "▸ Removing only Aster preferences and stored data…"
/usr/bin/defaults delete "$BUNDLE" >/dev/null 2>&1 || true
/bin/rm -f "$HOME/Library/Preferences/$BUNDLE.plist"
/bin/rm -rf "$HOME/Library/Saved Application State/$BUNDLE.savedState" \
    "$HOME/Library/Application Support/$BUNDLE" "$HOME/Library/Caches/$BUNDLE" \
    "$HOME/Library/HTTPStorages/$BUNDLE" "$HOME/Library/HTTPStorages/$BUNDLE.binarycookies"
/bin/rm -f "$HOME/Library/Preferences/ByHost/$BUNDLE".*.plist(N)
# Shared upstream sudoers rules and root recovery journals are deliberately kept.
# Their ownership cannot be inferred from a filename; the disabled journal also
# preserves diagnostic evidence for any later recovery.
print "✓ Aster removed. The app is in Trash; upstream apps and settings were preserved."
