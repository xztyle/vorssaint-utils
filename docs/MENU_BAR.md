# Aster menu bar manager

The manager is an optional feature in the Features hub. macOS 14–26 uses the
WindowServer backend. macOS 27 uses a separate native Accessibility, position
file and visibility backend; it never calls the legacy WindowServer move APIs.
macOS 28 and later remain unsupported. Live ordering, hiding and restoration
on the owner's Mac16,5 running macOS 27.0.1 are not yet accepted.

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
  rearrangement before that state is resolved. Retry cannot clear this recovery
  state; rules, reconciliation, manual moves and profile application cannot
  rearrange icons while it remains. Restoring the original layout remains
  available.
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

The recovery guard also passes the 409-check focused suite and an optimized
build. It closes the Retry path that could resume automatic moves after a
collateral change. The original layout still differs from the physical order,
so this change has not been exercised by moving real icons.

A later read-only inventory found eleven current icons against ten original
baseline entries. Battery, Docker, Wi-Fi, Text Input, Siri and Control Center
are not in their original relative order; Aster's newer icon is additional.
The exact observed order is now a restoration-planner regression. Its model
plan restores the baseline's relative order without dragging protected Control
Center or Clock, and the focused suite passes 412 checks. No actual icon was
moved by this check, so physical restoration remains unverified.

The 2026-09-30 live restoration retry retained all visible icons and the saved
baseline. Its session event named foreground Setapp (20921) while all three Siri
window fields still named 5139; the expected host was Control Center (625).
The candidate now distinguishes session-address rewriting from final host
delivery. It still rejects a changed explicit window or event type, verifies
the press's hit-test windows, and keeps strict process checks at the host tap.
The focused menu suite passes 428 checks, including this recorded failure and
the strict activation guards. The correction is installed. Native restoration
remains unproven until a physical retry; management remains off and its baseline
is retained. Bartender's native General, Layout and Advanced settings were
inspected on 2026-09-30, then the original manager was quit without moving icons.

The subsequent host-delivery matcher accepts rewritten press hit-test fields
only after verified session delivery, with unchanged explicit window, host,
type and Command modifier. An unverified session or host press still fails.
The next physical retry reached event acknowledgements but did not move icons.
Press and destination now use the row's interior height; the focused suite
passes 441 checks. The installed interior-coordinate candidate also failed
physical restoration. All thirteen icons remain present, management is off and
the ten-entry original baseline is saved. These checks establish narrower
routing/geometry correctness, not working icon movement on this Mac.


The following native retries also retained the thirteen-icon order and the
ten-entry baseline. Refreshing the destination after pressing did not repair
movement. Keeping the cursor associated with mouse events exposed a more
specific failure: macOS delivered the release with destination hit-test
windows 24/24 and the previously acknowledged Siri window 5139 as its event
window. The relay rejected that host delivery and recovered the release.
Management remains off. Recorded evidence is in
`work/acceptance/menu-cursor-restoration-runtime.log` outside this checkout.

The current correction recognizes that release only after session verification
and a completed press in the same relay. It still verifies both destination
hit-test fields, event location, host, release type and cleared modifiers.
Unknown origins and unrelated windows remain rejected. The focused suite
passes 469 checks; a native restoration pass is still required.

## Source attribution

The WindowServer/Accessibility/divider/drag substrate and original Settings/string
catalog were adapted from ruvelro's [Vorssaint PR #360](https://github.com/vorssaint/vorssaint-utils/pull/360),
head `8d0888a5e36c6d3b3e138c9eba0bc7791ec0be16`, retaining its GPL-3.0-or-later
headers. Aster adds profile/rule persistence, search, shortcuts and lifecycle
restoration. Public Ice/Thaw behavior informed the research. No private Thaw
macOS 27 code or binary dependency is included.

The captured-origin release correction passed 469 focused and 81,783 full
Swift checks, preference cleanup, eleven installer checks, optimized build,
strict signature verification and installed self-test. Its physical retry
reached both delivery acknowledgements without rejecting the recorded host
release, but the thirteen-item menu order still did not change. Management
is off and the ten-item baseline remains saved. This fixes the observed
delivery rejection but does not establish working native restoration.
Evidence: `menu-drag-origin-native-report.json`, the corresponding before/after
inventories and `menu-drag-origin-restoration-runtime.log`.

The next candidate added a full horizontal Command-drag gesture for source and
destination within one display's notch-safe segment. It warps to the source,
posts four drag steps, refreshes the destination before release, and retains the
release guard and physical-order checks. Its 489 focused checks and optimized
build passed. The installed native restoration still failed: acknowledged press
and release left all thirteen physical icons and their frames unchanged. The
ten-entry baseline remains saved and management is off. Delivery is not proof
of movement. Evidence: `menu-visible-drag-native-report.json`, before/after
inventories and `menu-visible-drag-restoration-runtime.log`.

The top-row correction and cursor-warp settling wait passed 490 focused checks,
81,805 full checks and the optimized build. The final installed retry also failed:
both endpoints acknowledged delivery, but all thirteen icons retained their order
and frames. Management is off and the original baseline is still retained. See
`menu-top-row-native-report.json`, before/after inventories and runtime log.

Aster is left running on Battery Care. The unchanged service remains PID
49955 with one execution; fresh authenticated status after this update still
shows 80%, charging false, 0 W, the exact enabled 75–80% policy with automatic
discharge, owned hardware and no pending recovery. The app update did not
require approval or policy re-entry. Further menu transport work remains.


The 2026-09-30 open-source comparison is recorded in
[MENU_BAR_SOURCES.md](MENU_BAR_SOURCES.md). Aster now uses SaneBar-informed HID
gestures for visible icons within one notch-safe region and Thaw-informed passive
observers/private barriers for window-routed events. The native Siri restoration
still fails physical verification; it is not a completed Bartender replacement.
All ten recovery-baseline entries remain and management is off. The final full
suite passes 81,816 Swift checks, preference cleanup and eleven installer checks.

## Continuation — 2026-10-01

The newer native evidence supersedes the older no-movement result. Five icons
physically moved and passed verification with the SaneBar-informed transport:
Wi-Fi, Now Playing, Battery, ABC and Claude. Siri still returns to the left of
Control Center. The owner confirmed that its original position on the right is
possible by hand, so this remains an Aster defect. See
[MENU_BAR_SOURCES.md](MENU_BAR_SOURCES.md) for current evidence and source notices.

A confirmed separate defect is fixed: the visible gesture now sends a complete
Command modifier press/release, including fallback release on cancellation.
The corrected native gesture leaves neither Command nor a mouse button held.
The final drag reaches the freshly resolved destination before releasing.
The editor now uses each system item's own title instead of labeling multiple
different icons "Control Center"; that UI change is currently tested in source.

Current source passes 523 focused and 81,839 full Swift checks, preference cleanup
and eleven installer checks. Original-layout restoration, external displays,
notch overflow and lifecycle acceptance remain open. All ten baseline entries
remain saved. The battery helper has stayed running through the app-only updates
with its original PID and inode; latest authenticated status holds at 80% with
charging off and the exact saved policy enabled.

### macOS 27 bookmark recovery

Apple replaces its protected layout plist during ordinary menu-bar changes. A
bookmark for the old file then becomes stale. Aster now resolves the existing
scope without UI, validates the exact previously granted path, uses that scope
successfully, and refreshes the stale bookmark. A different resolved path is
refused. Native tests replace a real temporary file atomically, read its new
contents, verify bookmark renewal and a later read, and reject a different path.
The app exposes failed access and keeps the off switch available even when
permission is unavailable. The installed recovery passed the actual protected
file read and the Settings view shows Access granted. This accepts file access,
not icon ordering. Evidence: `macos27-bookmark-native-inventory.json`.

### macOS 27 layout refresh

The first installed native move failed its physical-order check and restored
the previous file. The status-item refresh had used a negative square-length
sentinel as a concrete width and restored it in the same run-loop pass.
The new refresh waits for the preference change, temporarily uses the rendered
width, then restores the original length after a separate layout pass. Cancel
and replacement requests restore the temporary width immediately; restoration
does not overwrite a newer external width. This adapts Thaw's public
`ControlItem` refresh, preview.5 revision
`528b9503b051cc1ccccae766014e64404670088b`.

The production refresh with inert width endpoints passes 22 new checks; the
focused menu suite passes 604 checks. Native move verification remains pending.

The timing correction alone did not pass live ordering. The next candidate
publishes only the position dictionary through CFPreferences using the exact
already-granted file domain, so cfprefsd can deliver the cross-process change.
The coordinated write still checks the original file and the preference cache
before publishing and checks the actual file afterward. Unrelated fields and
the scalar types of accepted weights survive. Recovery compares complete
property-list contents rather than byte ordering, since cfprefsd controls the
serialization. Real temporary-file tests verify publication, cache agreement,
unknown-field preservation and rejection of stale or unrelated changes.

Section-only choices no longer require a physical reorder. Explicit drop
targets still require real order verification before section membership saves.
Hiding verifies every stable identity and each visible publisher's item count;
temporary coordinate identities can change during ordinary reflow without
being mistaken for lost icons. Missing items still fail closed and reveal all.
These changes pass 82,065 full checks, preference cleanup and eleven installer
checks. Their native ordering, hiding and recovery acceptance remains pending.
