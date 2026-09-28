# Aster menu bar manager

The manager is an optional feature in the Features hub. It supports the macOS
14–26 backend. macOS 27 and later fail closed before calling its private
WindowServer entry points. Real interaction validation is still required on
Alejandro's Mac16,5 running macOS 26.6.2 before this feature is accepted.

## Behavior

- Visible, hidden and always-hidden sections, with drag arrangement and undo.
- Hidden items open in a searchable panel below the menu bar on notched displays.
  The ordinary panel excludes always-hidden items. Explicit always-hidden and
  search actions include them. Arrow keys select, Return opens, Escape dismisses.
- Activation reveals the actual source item. If it does not fit, Aster temporarily
  moves it to the visible section, verifies its position, then clicks it. An
  unreachable or ambiguous item remains unavailable. A painted app icon is not
  treated as a copy of another app's menu.
- Five shortcuts use Aster's existing recorder and conflict registry: hidden
  section, always-hidden section, panel, search and next saved layout.
- Named profiles save section membership and order. They can be applied, renamed
  and deleted. Missing apps remain in the saved intent and return when their
  stable identities become available again.
- Rules support active app, battery/power, battery percentage, local time range,
  display count and item presence. Actions reveal the hidden section, reveal one
  item, or temporarily apply a profile. Priority, debounce and expiry are bounded;
  a held condition does not trigger repeatedly. Missing targets stay dormant.
  Focus is not offered because no reliable signal was established.
- App launch/quit, sleep/wake, display and Space changes invalidate cached
  identities. Failed automatic moves stop after three attempts and offer Retry.
- A local original-layout baseline is written before adding controls or moving
  items. Disable and quit restore the baseline before controls are removed.
  Failed restoration or absent original items retain the baseline for recovery.
  After each drag, Aster checks that every other stable icon kept its section
  and order. An unexpected change stops automatic moves and keeps the recovery
  state. A restart with a changed original layout does not resume automatic
  rearrangement before that state is resolved.
  Clearing permissions or fully uninstalling refuses to proceed while recovery
  remains pending. Portable backups contain layout/profile/rule intent, never the
  original recovery baseline, live process/window IDs, coordinates or AX caches.

## Boundaries

Accessibility is required. Screen Recording is not required; the panel uses app
icons and labels. Another known manager causes a stop. Indistinguishable duplicate
items, unresolved Control Center hosts and protected system items cannot be moved.
Missing private enumeration capability does not fall back to guessing from all
status-level windows. Movement checks fresh identity, frame, process lifetime,
idle input and open menus, and always sends a mouse-up after a started gesture.

A failed activation restores section visibility and retains its original layout
for a later safe retry. An open source menu owns deferred restoration until it
closes. No rule drags an item while a menu remains open.

## Diagnostics and validation

The Settings page has a diagnostic copy action. The command
`Aster --menu-bar-inventory` is a read-only probe that runs before preference
registration and app launch. It reports the OS, permission, displays, conflicts,
resolved item identities and live frames. It creates no status item, posts no
input and never requests permissions. Its output contains local app names and
is intended for local diagnosis, not portable settings backup.

Automated verification includes stable/provisional identities, protected layout
anchors, original-layout restoration planning, profile persistence and corruption
preservation, missing apps, rule priority/expiry, overnight time ranges, fuzzy
search, always-hidden exclusion, all 15 locales, and real activation/termination/
removal methods executed against inert endpoints. The fixtures never rearrange
the user's menu bar.

On 2026-09-28 the focused final suite passed 9,845 checks, including 177
menu-bar and activation checks, 527 command-bar/termination checks, 49 removal
checks, and catalog/settings/localization/repository checks. The optimized app
was packaged successfully before the final quit-loop and divider-localization
fixes. The final source then compiled into the optimized executable; packaging
was intentionally interrupted to release the shared build slot. A standalone
executable self-test reported missing bundled icon assets, so packaged self-test
remains part of integration validation.

The read-only inventory on the actual macOS 26.6.2 Mac succeeded with Accessibility
already granted and the private window list available. It reported one display,
no competing manager and 11 items: seven stable, four provisional, six movable.
This proves enumeration on the host, not drag, reveal or layout restoration.
No status items were created and no menu bar input was posted by this probe.

The mandatory real-Mac acceptance pass remains separate: signed Aster Developer,
Accessibility granted, inventory first, two harmless third-party icons, verified
hide/reorder/menu activation, profiles, rule expiry, notch, secondary display,
Spaces/full-screen, menu auto-hide, sleep/wake, app restart, disable restoration,
competing-manager rejection and bounded WindowServer resource use. No such
interaction is claimed by automated checks.

The later isolated-move safety check covers the observed Docker move that also
swapped Siri and Control Center. It accepts a Docker-only move, rejects the
collateral swap or a missing unrelated icon, and recognizes a changed original
order after restart. The focused menu suite passes 409 checks. This is model
and source verification; a real icon move, Undo and restart still need hands-on
acceptance on the owner's Mac.

## Source attribution

The WindowServer/Accessibility/divider/drag substrate and original Settings/string
catalog were adapted from ruvelro's [Vorssaint PR #360](https://github.com/vorssaint/vorssaint-utils/pull/360),
head `8d0888a5e36c6d3b3e138c9eba0bc7791ec0be16`, retaining its GPL-3.0-or-later
headers. Aster adds profile/rule persistence, search, shortcuts and lifecycle
restoration. Public Ice/Thaw behavior informed the research. No private Thaw
macOS 27 code or binary dependency is included.
