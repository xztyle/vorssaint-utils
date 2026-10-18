# Aster UX parity evidence

Current compatibility, 2026-10-01 (macOS 27.0.1): the earlier battery and
menu-bar results below apply to macOS 26. macOS 27 changed both systems. The
installed legacy battery helper cannot enforce Aster's saved policy on this Mac.
The native menu backend and independently owned battery policy are being tested;
compilation and simulated recovery tests do not establish hardware enforcement.
The owner's macOS manual charge limit is 100% and must remain 100%. Aster owns
its separate 75–80% rule. Keep Awake is enabled and set to start when Aster opens.

Status: in progress. The scope remains Bartender, Paste, AlDente, CleanShot X and
the useful cleanup functions of CleanMyMac. iPhone work was cancelled by the owner.

Continuation, 2026-10-01: open-source research and native evidence are recorded
in [MENU_BAR_SOURCES.md](MENU_BAR_SOURCES.md). The SaneBar-informed gesture moved
five real icons and passed physical verification. The corrected gesture also
releases the synthetic Command key after normal and cancelled moves; native
modifier/button state confirms release. Siri restoration remains incorrect even
though the owner can place it correctly by hand. Management is off and the ten
original-layout entries remain saved. Current source passes 81,839 full Swift
checks, preference cleanup and eleven installer checks. The unchanged battery
service currently holds 80% with charging off and the saved policy enabled.

Current status, 2026-09-30: all five restored Setapp apps have now been inspected
in native windows and quit. AlDente's popover, dashboard, charging/sailing/heat
controls, sleep behavior, energy controls and widget editor were inspected. Aster's
saved 75–80% policy was restored after the original was quit. The installed build
adds CPU/GPU/neural-engine/memory energy measurements, a second Mac-to-chip/Other
Sankey stage and a compact centered clipboard navigation row. Installation and
native acceptance are recorded below. Automatic prior-app paste into the disposable
TextEdit document and owner-confirmed native screenshot drop passed. Owner-confirmed cancelled
drag and smooth left dismissal also passed. Physical menu restoration and
lifecycle gates remain open.

Latest continuation: the card-attached preview and native draft editor are
installed. Search, Space opening, Copy, Edit a copy and button Cancel were
exercised with generated text. Automated editor cancellation passes, but the
computer-control key does not cancel the displayed draft. A physical Escape
check was requested to distinguish input routing from an app defect. Details
are recorded below.

The latest screenshot review found a conflict between Escape and active gestures.
The preview monitor now leaves keys to an active drag/swipe, and expiry cannot
close a swiping card. Production callback regression checks pass and the update is installed.
The owner subsequently confirmed cancelled-drag retention and smooth left dismissal.

## Reference availability — 2026-09-29

The `/Applications/Setapp` directory contains only its folder icon. Spotlight
returns none of the five application bundles; the native app inventory also does
not list them. `/Applications/Aster.app` exists and launches. These observations
do not prove that copies cannot exist elsewhere. No original app was launched or
tested during this pass. No competing battery controller was installed.

Official interfaces and documentation were inspected in the Codex in-app browser.
The owner's personal browser was not used. A website reference is recorded as
reference evidence, not as a successful test of the original application.

## UX requirements from the references

| App | Interaction to preserve | Evidence and remaining acceptance |
| --- | --- | --- |
| AlDente | Glanceable battery state, editable limit/range, one-time top-up and an animated power-flow diagram. Charger input splits into Mac consumption and battery charging; a discharging battery becomes a source. Both sources appear when the charger is insufficient. | Official charging, paused, discharge and dual-source diagram examples inspected. Aster's live diagram added; all four flow calculations covered. Real charging, unplugging and dual-source UI checks remain. |
| Paste | Bottom-screen timeline over the Dock; content previews and source/time metadata; direct Return/double-click/drop into the prior app; arrow navigation; Quick Look; type-to-search; collections; resize and compact mode. | Official current interface and help inspected. Production capture, old-copy search/restoration, keyboard preview and top-edge resizing exercised. Return automatically pasted the generated FIRST item into the actual prior TextEdit app. Global shortcut delivery and clipboard-card external drag remain live acceptance gates. |
| CleanShot X | Corner capture overlay; copy/save/edit/drop actions; swipe handling; reopening overlays; editing and native drag transfer of edited pixels. | Official Quick Access Overlay and annotation documentation/interface inspected. Owner's stricter image-only resting preview remains authoritative. The owner passed physical Shift-Command-4 capture, external TextEdit drop and card dismissal. The owner also passed cancelled-drag retention and smooth left dismissal. Multi-display and Spaces remain open. |
| Bartender | Fast reveal by pointer/gesture/keyboard, accessible hidden-item bar beneath the menu bar, notch overflow, keyboard search, presets and triggers, glass navigation. | Official Tahoe features reviewed. Aster organizer is currently disabled. Icon movement/restoration failures in the older validation log remain acceptance gates. |
| CleanMyMac | Clear scan → review → selected cleanup → results flow; useful storage visualization, drill-down and selection; visible reclaimable space and recovery. | Original Space Lens and Aster scanned generated files. Both maps and folder navigation were inspected. Aster's selection/size/review/Cancel were exercised without deletion. |

Sources:

- [AlDente features](https://apphousekitchen.com/aldente-overview/features/#power-flow)
- [Paste on Mac](https://pasteapp.io/help/paste-on-mac), [current interface](https://pasteapp.io/)
- [CleanShot features](https://cleanshot.com/features#quickaccess)
- [Bartender 6](https://www.macbartender.com/Bartender6/)
- [CleanMyMac Smart Care](https://macpaw.com/support/cleanmymac/knowledgebase/smart-care)
- [CleanMyMac Space Lens results](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-results)

## Power-flow implementation

The shared power-flow surface is in the Power menu panel and Battery Care settings.
It uses the existing monitor and sampling preference, with no extra background
sampler or change to battery policy. Animation stops for stale readings or Reduce
Motion. Missing quantities stay unknown. A charge reading greater than measured
adapter input produces a settling state instead of fabricated balanced wattages.

Diagram Mac power is derived from measured charger input and signed battery flow.
The independent system sensor stays visible in the measured breakdown; it is not
forced to match the diagram. An information control explains this distinction.
Activity rankings explicitly identify their CPU/GPU basis and do not claim watts
per app. Labels cover all fifteen app languages.

A read-only probe using the production SMC client on this Mac found:

- `PSTR`: 21.01 W system sensor; `PDTR`: 32.50 W adapter input.
- `PDBR`: 0.40 W display backlight; `PU1R` and `PU2R`: readable 0 W.
- CPU/GPU candidates `PCTR`, `PC0C`, `PCPC`, `PCPR`, `PG0C`, `PG0R`, `PGTR`
  and memory candidates `PMTR`, `PC3C`: absent. No component wattages were inferred
  from activity percentages.

The component key labels are cross-checked against the upstream
[Stats sensor catalog](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift).
The chart and measurements are content. Floating navigation retains Aster's shared
Liquid Glass surfaces; glass is not added over the data merely for decoration.

## Verification for this pass

- Focused metrics suite: 336 checks passed, including four power-flow modes,
  source conservation, missing/invalid/inconsistent/stale telemetry and localization.
- Release build: passed after correcting the contrast environment key.
- Installed and staged battery-service versions match exactly. This UI change does
  not require battery-helper re-registration.
- The final complete suite passed 80,911 checks plus preference cleanup. The
  optimized bundle was installed, passed its packaged selftest and passed deep,
  strict signature verification. The clipboard resize change also passed 8,621
  focused clipboard/preferences/repository/localization checks.
- The installed Power panel and Battery Care settings were visually inspected.
  Watts refreshed live with two decimals. The measured sensor breakdown opened.
  The saved policy remained enabled through both installations: 75–80%, heat
  cutoff/resume 38/35°C, automatic discharge on. Actual battery state was 80%,
  0 W and charging false, with no pending recovery. Charging qualification is
  still deferred until 75%; no complete recharge cycle is claimed.
- The installed production clipboard drawer captured generated text, found an
  older copy and previewed it using Down/Space. An explicit paste into a disposable
  TextEdit document reproduced it. Automatic prior-app paste is unproven because
  automation did not reliably change the foreground app or trigger the global
  history shortcut. No paste was sent into personal message fields.
- The invisible top edge resized the installed drawer, changed cards to compact
  mode, retained query/focus and remembered the chosen height on reopening.
  Full replacement parity remains in progress; original-app behavior, menu-bar
  recovery and screenshot external drop/swipe acceptance remain open.
- The Mac locked after the resize/reopen checks. The final diagnostic-only change
  makes the fixture report the resized target frame. That exact source was built
  and installed, but the final installed app has not been opened after this lock.
  The independent battery service still reported an enabled 75–80% policy,
  holding at 80%, 0 W, charging false and no pending recovery. Its version remains
  `15827a9705abdb5262df0db6a3bb4a1ec3f6e3af2c2518495439561d54497b9c`.
  The resize test left the saved drawer height at 280 points; restore the prior
  440-point height through the UI when access returns. Read-only menu enumeration
  succeeded with 11 stable items and no competing manager; no icon was moved.

## Storage-map continuation — 2026-09-29

The next goal turn made concrete source progress while the same Mac lock remained.
Spotlight and the task's research/download directories still yielded no original
application bundle or installer. No competing charger or trial was installed.

The CleanMyMac interaction gap was a flat storage list with no map or browsing
history. The candidate now adds proportional-area bubbles, direct-child navigation,
Back/Forward, breadcrumbs, linked hover/selection, an Other items group, and
responsive map/list placement. It reuses the scanned snapshots, Quick Look and
existing review/Trash controls. It adds no scan outside the chosen roots.
Reference details and verification boundaries are in `ASTER_CLEANUP.md`.

The candidate release build and packaged selftest passed. The full suite passed
81,485 checks plus preference cleanup after rerunning sequentially: an earlier
overlapping release build removed generated test inputs during compilation.
Strict bundle verification initially rejected local filesystem metadata on the
staging copy; clearing extended attributes on that generated bundle resolved it,
and deep, strict verification then passed. This candidate is not installed or
visually accepted yet.

The current appearance audit found the global Liquid Glass preference enabled
and the notch preference disabled. Shared floating backdrops use native macOS 26
glass; clipboard navigation and screenshot editing controls reuse them. Content
retains separate readable surfaces. This does not establish an app-wide visual
acceptance pass. Native access remains blocked by the Mac lock.

A fresh read-only battery status returned the policy enabled, 75–80%, automatic
discharge enabled, charging false, holding at 80%, 0 W and no pending recovery.
Charge qualification remains false, so a complete recharge cycle is still open.

## Live-access blocker audit — 2026-09-29

The preceding turn completed verification of the generated candidate bundle:
81,485 checks, packaged selftest and strict signature verification. This was
concrete progress, not a substitute for runtime acceptance.

Native access was rechecked in this continuation and still reports the Mac
locked. This condition has persisted across at least three consecutive goal
turns. A fresh Spotlight search yielded none of the five original bundles;
Setapp's application folder still contains only its icon. Copies elsewhere are
not ruled out. The previous requests for unlocking and original-app locations
remain unanswered.

Review of the recorded Docker/Siri/Control Center swap, off-row Wi-Fi Undo,
current transport and restoration regressions found the documented corrections
already present. Their physical behavior remains unproven. No further transport
change is justified by those old logs alone, and no icon was moved here.

Completion remains unproven for original-app runtime inspection, battery flow
across charging/unplugging, physical menu restoration, automatic clipboard paste
and external drops, screenshot swipe/drop behavior, and storage-map native
acceptance. All need an unlocked Mac; inspection also needs working original-app
copies. The goal is blocked on these external prerequisites. Its five-app scope
is unchanged, and neither feature completion nor replacement readiness is claimed.

## Restored reference apps and live retry — 2026-09-30

Native access returned in the resumed goal turn. The owner authorized restoring
the reference apps through Setapp. Paste 7.0.0 and CleanShot X 5.0.1 were installed
through Setapp and opened. Bartender, AlDente and CleanMyMac still need restoration;
the Mac locked again before their downloads could be started.

Paste's actual drawer was visually inspected. Search found an old entry; clicking
its card and pressing Space opened an anchored preview with Pin, Share and Edit.
Escape closed the preview, then cleared search, then closed the drawer. Two
generated text copies from a disposable TextEdit document appeared in its history.
Their source icon was Setapp: native automation's window Raise and targeted input
did not establish TextEdit as the real foreground app. Automatic prior-app paste
therefore remains unproven. CleanShot opened its readiness toast and native menu;
its capture/editor interactions have not yet been inspected. No charge controller
was restored or launched, and no cleanup was run.

Aster's recovery controls were enabled, Restore original layout was invoked,
an open reference-app menu was explicitly cancelled, and restoration was retried.
Both attempts retained the baseline and returned management to off. The before,
after and retry inventories in `work/acceptance/menu-recovery-live-*.json` show
the same visible physical icon order. The completed operation does show a failure
message in Settings; its temporary absence immediately after the click was not
a permanent missing-result defect.

The live retry logged Siri's exact window 5139 retained in all three routing
fields, while session delivery changed the process address from Control Center
625 to foreground Setapp 20921. Aster rejected that session event before an icon
moved. The candidate now permits a session process-address rewrite only with an
explicit original routing window. Event type, press hit-test windows, unique
delivery tokens, final host acknowledgement and whole-layout checks remain.
Host delivery and activation without an explicit routing window retain strict
process matching. Thirteen new checks cover the observed rewrite, wrong windows,
wrong event types and retained strict target/activation guards; the focused menu
and repository suites pass 682 checks.

The public [Ice event implementation](https://github.com/jordanbaird/Ice/blob/main/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift)
also matches its session event by token and window fields rather than a process
address. Its source was read as supporting evidence, not used as proof that this
candidate physically restores icons. The correction has not been installed or
tested live. Original-app inspection and all remaining acceptance gates stay open.

## Native references and installed corrections — 2026-09-30

Restored through Setapp: Paste 7.0.0, CleanShot X 5.0.1, Bartender 6.6.2,
CleanMyMac 5.7.0 and AlDente Pro 1.39.4. Setapp's auto-open-after-install option
was temporarily disabled for AlDente, then restored to its original enabled value.
No AlDente process was launched. The four inspected applications were subsequently
quit through Activity Monitor's normal Quit action; process enumeration confirmed
their main processes were absent. No reference preferences or personal history
were deleted.

CleanShot Quick Access defaults to the left, moves to the active display, keeps
captures indefinitely and closes after dragging unless Option is held. Its real
editor opened a generated PNG through Finder's Open With. Drawing another arrow
and clicking Copy closed the editor; an explicit paste into the generated TextEdit
document showed both arrows. The editor has glass tool groups and substantial dark
space around the image. The owner's requested image-filling canvas remains
authoritative. Native overlay swipe and cross-application drop remain untested.

Aster now dismisses a corner capture after an accepted native drop. Holding Option,
a failed drop or cancellation keeps the card. Embedded drag surfaces retain their
existing behavior. Thirteen additional tests exercise the actual production
drag-completion callback, its cleanup and callback ordering. These tests establish
the callback contract, not successful native cross-application transfer.

Paste's actual bottom drawer, card previews, search, anchored Space preview and
staged Escape behavior were inspected. Aster already follows that interaction
sequence and now has verified remembered resizing. Its header remains visually
different from Paste's compact centered navigation; complete visual parity is not
claimed. Automation did not make TextEdit the real foreground app, so automatic
prior-app paste remains pending. A later focus handoff was requested for the
generated TextEdit document. An attempted drawer-height restoration lost its
temporary window focus; the saved height remains 280 points.

Bartender's General, three-row physical icon layout and Advanced settings were
inspected. Its layout has Shown, Hidden and Always Hidden sections, drag organization,
spacers and groups. No original icon was moved. Aster's session event-address
correction is installed and passes 428 focused checks, but physical restoration
has not been retried. Aster's organizer remains disabled with its baseline retained.

CleanMyMac Space Lens scanned only generated files, showed proportional circles
and a linked checkbox list, drilled into a folder by double-click, and enabled Back.
Selecting a generated file under Documents produced a cloud-deletion warning;
Change Selection cancelled it and no cleanup occurred. A local temporary copy was
then scanned with Aster. Its measured circles, folder navigation, Back, selected
size and review sheet were exercised; Cancel closed the review without deletion.
The installed refinement shortens scope labels, hides inactive filter controls and
moves technical limits to help text. That final presentation still needs a visual
recheck after the service repair.

Live battery diagnosis found an unplugged registry record containing only
`AdapterDetails.FamilyCode=0` with no raw adapter details and both connection flags
false. Aster incorrectly treated any nonempty record as physical attachment.
The decoder now requires positive adapter family or rated watts. Unplugging during
qualification restores macOS without consuming a failure; a real physical
reconnection renews the bounded retry budget. A continuously attached failed
adapter does not receive unlimited retries. Eight additional battery checks cover
these cases; the focused battery suite passes 214 checks.

Installing by moving the previously registered app bundle exposed a macOS
BundleProgram lookup failure (launchd EX_CONFIG, "No such process"). Restoring an
old copy did not revive the registration. Before repair, the last authenticated
service snapshot showed no owned hardware or pending recovery, and a fresh
read-only hardware probe showed the normal charge controls. Battery Care was
temporarily suspended; the existing guarded repair unregistered the stale service
without hardware writes. The feature was restored and its service registered
through Settings. macOS required no new approval in this run. The saved policy
returned automatically and live charge/hold/discharge qualification completed.
The post-repair status reports both capabilities qualified, policy enabled,
75–80%, zero failures and charging below the lower bound. Evidence is saved in
`work/acceptance/battery-after-adapter-fix.json` outside the source checkout.
App update reliability remains a gate: this operator repair is not automatic
recovery, and future installs must release a changed helper before replacing its
registered bundle. No claim of seamless helper upgrades is made.

The installed helper version is
`1b34c454222676b5c22a42bfa4cbe6bc5f7f028675f9e0944c52761f79d0463a`.
The optimized build, installed selftest and deep strict signature verification
passed. The full suite passes 81,523 checks plus preference cleanup. This does not
replace the remaining real gesture, drop, foreground-paste, menu movement,
power-transition and AlDente inspection gates. The temporary in-app browser tab
and local reference server were closed; the personal browser was not used.

## Native AlDente inspection and measured chip flow — 2026-09-30

Aster first authenticated a return to system control and verified ownership and
recovery were both false. The original AlDente Pro was then launched. Its live
popover showed adapter to battery/Mac, followed by Mac to SoC/Other, and a plain
charging explanation above the graph. Clicking Mac hid the outgoing split and
clicking again restored it. The dashboard added CPU-chip, display, USB and Other
measurements, battery/adapter specification cards and historical graphs. Widget
edit mode showed rearrangement/removal and additional graphs; Done left the
original layout unchanged. No original charge-control operation was started.

Observed original policy: limit 80%, automatic discharge on, sailing difference
5%, heat protection 38°C. Its recommended sleep option prevents sleep until the
charge limit; Aster currently pauses charging during sleep. This is a remaining
behavior difference. The original was quit with its own Power control. A process
check confirmed its main app had exited, and Aster's exact saved enabled 75–80%,
38/35°C, automatic-discharge policy was restored and acknowledged successfully.

A read-only enumeration of this Mac's SMC found additional unnamed P keys, but
those were not assigned component names by inference. A direct Energy Model
probe instead found named CPU Energy (mJ), GPU Energy (nJ), ANE (mJ) and DRAM (mJ)
counters. The production sampler returned chip totals 20.44 W then 12.10 W on
successive one-second samples, with separate measured memory power. This does
not establish that AlDente's SoC uses the same physical measurement boundary.

The implementation uses a dynamically resolved read-only IOReport interface,
checks each channel's unit, differences integer counters over monotonic elapsed
time, and selects aggregate channels without double-counting per-core or die
readings. First reads, missing counters, counter resets, unsupported units and
long sampling gaps remain unknown and recover on the next valid interval. Chip
is CPU + GPU + neural engine. Memory stays separate. Other is Mac minus chip;
inconsistent sampling windows show settling and unknown flow rather than a
negative or invented residual. The Mac node hides/reveals the outgoing split.
The explanation now precedes the diagram. All fifteen languages cover the new
labels and the information control explains the measurement boundary.

Primary interface references:
[Stats reader](https://github.com/exelban/stats/blob/master/Modules/Sensors/readers.swift),
[Stats declarations](https://github.com/exelban/stats/blob/master/Modules/Sensors/bridge.h),
[NeoAsitop](https://github.com/op06072/NeoAsitop).
These informed API investigation; no third-party binary was installed or run.

The focused metrics suite passed 360 checks. The first complete run passed all
behavior checks but rejected em dashes in two new translations. Those were
corrected before the final build. The complete rerun and native acceptance follow.

## App-directory-preserving installation

The previous installation moved a bundle already registered with macOS, after
which launchd could no longer resolve its relative battery helper. The installer
now stages and verifies a complete candidate on the destination volume, replaces
only Contents, preserves the outer app directory, verifies the installed result
and restores the previous Contents if validation fails. A failed rollback retains
the previous contents instead of deleting its recovery copy. Five isolated tests
cover directory identity, rollback, failed staging, first installation and symlink
rejection. Changed-helper approval is still controlled by macOS; this change is
not a claim that every OS approval or reboot scenario has been eliminated.

## Installed power and clipboard acceptance — 2026-09-30

The optimized build, packaged selftest and deep strict signature checks passed.
The final complete gate passed 81,548 Swift checks, preference cleanup and eleven
isolated installer tests. Native Battery Care showed the enabled saved policy,
live three-stage power flow, CPU/GPU/neural-engine/memory readings and working
Mac-node hide/show. The first sample stays unknown; later samples are live.
The chart height also accounts for both outgoing chip nodes.

The installed clipboard drawer retained 280 points. Search found the two generated
FIRST/SECOND reference copies. The older FIRST item opened in preview. Escape
closed preview, then cleared search, then dismissed the drawer. No automatic
paste was sent: a read-only foreground check still returned Slack rather than the
disposable TextEdit document. The compact header's empty collection scroll area
initially spread Recent and Add apart; the final refinement removes that empty
area to keep the controls together in the center.

The initial directory-preserving update exposed a second issue: replacing the
running helper's executable invalidated authenticated XPC even though its code
hash and certificate were unchanged. The service was safely unregistered with
the existing guarded repair while hardware was returned to system control,
registered again, and the exact saved policy was restored. This was operator
recovery; it is not presented as automatic recovery.

The corrected installer preserves an unchanged helper's file identity with a
hard link. CMS signing bytes can vary between builds even when code is unchanged;
the host is therefore signed again with the same stable identity after retaining
the child. The child itself is not signed again. The candidate and installed host
must validate against the original designated requirement and strict signature.
A registered helper with changed code blocks installation before any installed
contents are replaced. That case still needs a deliberate release/unregister
sequence; no seamless changed-helper upgrade is claimed.

A real subsequent update preserved both app directory inode 35397683 and battery
helper inode 35435999. The authenticated battery request succeeded immediately;
75–80%, heat 38/35°C, automatic discharge and enabled state all remained intact.
No new OS approval or reconfiguration was needed for that unchanged-helper UI
update. The installed packaged selftest also passed. Original main apps remain
stopped. Remaining acceptance gates include native cross-app screenshot drop and
physical swipe, automatic prior-app paste, menu restore, multiple-display/Spaces
behavior and broader battery sleep/restart checks.

Final visual check: the final installed clipboard header keeps Recent and Add
adjacent in the screen center. The 280-point drawer still opens over the Dock.
The Mac then locked before the remaining gesture/previous-app checks. The user
was asked to unlock it and front the disposable TextEdit document; no dependent
paste was attempted. The final enabled policy and authenticated daemon status
were rechecked independently of desktop access. This turn made installed source
and runtime progress; the overall replacement goal remains active.

## Card-attached clipboard preview — 2026-09-30

The actual Paste preview attaches to its selected card. Aster's former sidebar
and separate Space sheet moved or covered the timeline. A single native popover
now reuses the existing content preview, editing, rich text and file preview
behavior. Space and the Preview action open this same surface above the card;
the drawer keeps its width and chosen height. Header and actions use the shared
glass backdrop. The preview's exact window participates in library keyboard and
outside-click routing, while other Aster windows still dismiss the drawer.
Copying a selected text fragment remains owned by the text view. Changing search
or collections, or dismissing the drawer, closes the preview.

The first candidate passed 81,564 Swift checks, preference cleanup, eleven
installer tests, its packaged selftest and deep strict signature verification.
The workspace copy acquired filesystem metadata that prevented strict signature
validation; a clean generated copy under `/private/tmp` verified successfully.
The app was quit through its own menu, installed with the existing verified
installer and relaunched through computer control. The app directory and helper
inodes remained 35397683 and 35435999. An authenticated request confirmed the
enabled 75–80%, 38/35°C, automatic-discharge policy and no pending recovery.
No new macOS approval or battery reconfiguration was needed.

The installed drawer searched only the two generated FIRST/SECOND acceptance
copies. Space opened the FIRST popover above its selected card. Its native tree
showed the correct full text and pin/edit/copy controls. Copy closed the drawer
and the clipboard's plain-text representation matched FIRST exactly. Edit a copy
opened the draft field and enabled Save after a generated suffix was entered.
The Cancel button discarded that draft and restored the original text. Escape
then closed the preview while keeping the searched timeline. The popover extends
above the drawer; the drawer-only screenshot crops its upper area. Complete
popover visual acceptance is not claimed from that cropped image.

Escape inside the native draft editor did nothing: AppKit retained the key and
SwiftUI's exit handler did not run. The corrected key handler requests draft
cancellation only for the preview's editable, non-field-editor text view. It
leaves input-method composition, modified keys and other windows alone. Editing
state is tracked by entry identity, so an old closing popover cannot cancel a
new card's editor. Closed popovers release their retained content.

Five additional checks invoke that actual production key handler with native
window/text-view/key objects. The focused clipboard suite passes 742 checks.
The final candidate passes 81,569 Swift checks, preference cleanup and eleven
installer tests. Its optimized build, packaged selftest and clean-copy strict
signature pass. Its battery-helper version matches the installed version.
Evidence and the candidate path are saved in `work/acceptance/clipboard-popover-*`
outside the checkout.

Desktop access was intermittent, then computer control reported the Mac locked
when selecting Dock to bring TextEdit forward. The owner was asked to unlock it
and front the disposable Untitled document. The final Escape correction is not
installed or natively rechecked yet. No further GUI action or automatic paste
was attempted after that lock. Screenshot cross-app drag/swipe, actual prior-app
paste, physical menu restore, multiple displays/Spaces and battery lifecycle
acceptance remain open. This turn made concrete source and installed runtime
progress; the replacement goal remains active.

## Native draft-editor continuation — 2026-09-30

The previously staged window-monitor correction was installed. The strict
signature passed, app/helper inodes remained 35397683/35435999, and an
authenticated daemon request confirmed the exact enabled 75–80%, 38/35°C,
automatic-discharge policy with no pending recovery. In the generated FIRST
draft, the control tool's Escape still left the editor open.

The preview now reuses the existing plain-text AppKit editor. Its optional
native cancellation delegate handles a draft cancellation command directly,
without relying on SwiftUI's exit handler or an event's window identity.
Input-method composition retains native handling, and existing scratchpads
without the callback retain their prior behavior. Four checks exercise that
actual delegate with native text views. The focused clipboard gate passes 746
checks; the full gate passes 81,573 Swift checks, preference cleanup and eleven
installer checks. The optimized candidate, packaged `--selftest` and strict
signature also pass. A mistyped diagnostic flag initially opened an extra test
instance; it was quit through its own UI and the correct selftest was rerun.

This candidate was installed and relaunched through the verified installer and
computer control. The app/helper file identities and exact enabled battery
policy remained intact. The native generated draft is editable, but the control
tool's Escape again produced no cancellation. A physical key check is pending;
automated delegate checks do not establish the actual keyboard workflow.

A fresh live battery status reports external power connected, 30% charge,
36.85°C, 0 W and a heat hold. Both capabilities are qualified and the policy
remains enabled with no recovery pending. The separate 35°C resume threshold
explains holding after a prior heat cutoff; this is not evidence of a complete
charging cycle or lifecycle acceptance.

TextEdit's disposable Untitled document remains available. Selecting it through
its own Window menu did not change the actual foreground application from
Slack. No automatic test paste or screenshot drop was sent into Slack.
Cross-app acceptance, physical menu restoration, multiple displays/Spaces and
battery lifecycle gates remain open. No VM was created; the owner asked about
virtualization only.

A subsequent source review found that the live energy-app list retained its old
rows indefinitely when a fresh result was empty. It now accepts that empty result
and resets loading when collapsed, so idle activity does not show old consumers.
The optimized build, packaged selftest and clean strict signature pass. This small
display correction is staged separately; it is not yet installed or natively
accepted. The pending physical Escape check was left undisturbed.


## Prior-app paste and edited capture acceptance — 2026-09-30

Opening TextEdit through Finder's exposed Open action changed the actual
foreground application to `com.apple.TextEdit`. The previous Raise/Window-menu
attempts had not done that. Aster's nonactivating History button then opened the
normal drawer while TextEdit remained the actual foreground app. Search was
restricted to the two generated reference copies. Selecting FIRST and pressing
Return closed the drawer and inserted its exact generated text in the disposable
Untitled document automatically. No manual Command-V was used for this pass.
The control tool did not trigger the global Carbon history shortcut, so this
proves the remembered-app/Return workflow, not physical shortcut delivery.

Capture Now opened the real selection interface. Selecting the disposable
TextEdit window produced a corner card containing only the image at rest.
Its Edit action opened the image-filling canvas. A third red arrow was drawn,
and Return committed it back to the same corner card. The generated transfer PNG
contains all three arrows at 1172 by 976 pixels. The copied acceptance artifact is
`work/acceptance/capture-aster-edited-third-arrow.png` outside the checkout.

Dragging this edited card toward a verified exposed TextEdit point started an
AppKit transfer and created its PNG, but did not insert another TextEdit
attachment or complete the session through the control tool. Escape then closed
the preview. No successful external drop, cancellation recovery or independent
left swipe is claimed from that attempt. Its evidence is recorded in
`work/acceptance/capture-external-drag-attempt.json`.

Source review found that the preview's local Escape monitor still acted during
an active drag/swipe. It now leaves input with the gesture. The expiry scheduler
also checks the swipe state, so leaving the card's bounds during the gesture
cannot schedule premature dismissal. Real unposted AppKit key events exercise
the production registered callback; drag/swipe keys pass through, idle commands
retain their behavior and the retained card can be edited after cancellation.
The existing production drag-completion checks still cover successful, failed,
cancelled and Option-retained transfers. These checks do not prove native drop
or physical swipe feel.

The current authenticated service baseline is enabled 75–80%, 38/36°C with
automatic discharge off. This differs from the earlier saved 38/35°C,
automatic-discharge-on baseline; the current settings are authoritative.
It reports a heat hold at 30%, 36.45°C and zero battery watts, no recovery pending.
No policy or hardware operation was changed for this acceptance pass.


The final candidate passes 81,603 Swift checks, including 877 screenshot checks,
preference cleanup and eleven installer checks. Its optimized release build,
packaged selftest and deep strict signature pass. The installed app and unchanged
battery helper retain inodes 35397683 and 35435999. The authenticated daemon
reports the exact current enabled policy after installation, with no recovery
pending. No OS approval or reconfiguration was required. The idle energy-list
refresh correction is included in this installed candidate.

The relaunched app's Power panel refreshed live. Charging resumed naturally from
the heat hold without a policy change. One observed transition showed charging
102.92 W above an adapter reading of 14.55 W; the diagram correctly displayed
Readings settling and unquantified source links. A later observation showed
128.55 W adapter, 22.31 W charging and 106.25 W calculated Mac consumption.
A read-only comparison of SMC and battery-current fields is in progress to
investigate transition lag. These observations do not prove a full charge cycle.

Computer control reported intervening user changes during the capture attempt;
the resulting corner surface was not kept available for a controlled gesture
check. Native external drop and drag cancellation remain unverified for this
candidate. The owner was asked to perform the screenshot-to-TextEdit drop with
the normal shortcut. No settings were changed to force a charging test, and no VM
was created.


## Owner-confirmed native screenshot drop — 2026-09-30

The owner performed the requested physical Shift-Command-4 capture and dragged
its corner card into the disposable TextEdit Untitled document without Option.
The reply was: “The image appears and the card disappears.” This passes physical
region-shortcut delivery, native image transfer and accepted-drop dismissal for
the installed screenshot-gesture update. It does not establish edited-pixel
fidelity for that particular drop, cancelled-drag retention, swipe motion or
Control-modified screenshot-to-clipboard delivery. The receipt is
`work/acceptance/screenshot-native-drop-owner-pass.json` outside the checkout.


## Fresh signed battery-power display — 2026-09-30

Read-only comparisons found that AppleSmartBattery current fields remained
unchanged for about twenty seconds while the adapter/system sensors refreshed.
The mismatch could temporarily put the power diagram into its settling state.
The Apple-silicon B0AP key supplies signed 32-bit little-endian milliwatts, as
identified by the upstream [Asahi power driver](https://github.com/AsahiLinux/linux/blob/79a307df1e18f144610742ac9ee60080c3983875/drivers/power/supply/macsmc-power.c).
A scoped pure decoder now reads that key for the monitor, retaining the existing
current-times-voltage fallback for unavailable or unsupported readings. Zero
and negative readings remain meaningful; the shared SMC codec and privileged
battery helper were not changed.

A thirty-second read-only probe of this actual production decoder produced
fifteen distinct power readings versus two distinct IORegistry current readings.
During discharge, the first direct reading was -81.037 W against 81.0378 W from
the independent system sensor; the last was -51.233 W against 51.2338 W. No
hardware test or power-state change was requested for the probe. The sensor
summary and raw samples are recorded in `work/acceptance/production-live-power-*`
outside the checkout.

The focused metrics gate passes 390 checks; the complete gate passes 81,634
Swift checks, preference cleanup and eleven installer checks. The optimized
release, candidate and installed selftests, and deep strict signature pass. The
helper code identity/version are unchanged, as are the installed app/helper
inodes 35397683 and 35435999. The exact current enabled 75–80%, 38/36°C,
automatic-discharge-off policy survived installation. Authenticated status
reports both capabilities qualified and no recovery pending.

The installed Power panel refreshed from waiting to live readings. One captured
charging frame showed adapter 133.89 W, battery 49.93 W and derived Mac 83.97 W
against the separate system sensor's approximately 85 W. Opening the measured
breakdown exposed fresh CPU, GPU, neural-engine and memory interval readings.
The saved native panel screenshot and accessibility text are
`work/acceptance/battery-live-power-installed-panel.*`. The sources are sampled
sequentially and may still differ during rapid changes; no simultaneity or
per-application watt measurement is claimed.

The daemon event record also shows recovery from the earlier failed hold
verification, automatic completion of charge/hold/discharge/charge qualification,
a heat pause, cooling and charging again. That is evidence of automatic recovery
on this Mac, not a completed upper-limit, top-up, calibration, schedule, sleep
or system-restart acceptance pass. No new macOS approval was needed for this
display update, and no VM was created.


The owner then completed both requested physical gesture checks: dragging right
and pressing Escape retained the card; left dragging/swiping moved it smoothly
off-screen. The response was “both work.” Cancelled native drag and physical
left-dismissal acceptance are passed. The receipt is
`work/acceptance/screenshot-native-gestures-owner-pass.json`. Multi-display and
Spaces behavior remain open; this is not a blanket screenshot-parity claim.

## Menu-bar host delivery correction — 2026-09-30

A native Restore original layout retry with the fresh-power build failed without
changing any of thirteen visible icon positions. Management returned to off and
the ten-entry original baseline remained saved. Its event log shows that the
initial session accepted the Siri press, then host delivery rewrote its two
hit-test fields from 5139 to 31849 while retaining explicit window 5139 and host
625. The strict press check rejected this host-stage rewrite.

The matcher now accepts that rewrite only at host delivery after the session has
verified the press, with the same explicit window, host, event type and Command
modifier. An initial session press, an unverified host press, an ordinary click,
a changed explicit window/process/type, or a missing Command modifier still
fails. Eleven recorded-event and delivery-phase regressions bring the focused
menu suite to 439 checks. The full gate passes 81,645 Swift checks, preference
cleanup and eleven installer checks. The optimized installed build, packaged
selftest and strict signature pass, with unchanged helper identity/version and
exact saved battery policy. Physical restoration is being checked separately.


The host-delivery correction reached press/release acknowledgements in the next
native retry, but the icon did not change position. Management returned to off
and preserved all thirteen icons plus the original baseline. The mover's press
and destination were at the row's top edge. They now use the row's interior
height, preserving a horizontal gesture; the press point lies inside the source
icon. The focused gate passes 441 menu checks and the full gate passes 81,647
Swift checks, preference cleanup and eleven installer checks. This optimized
update is installed with selftest, strict signature, exact saved battery policy
and stable registered app/helper identities verified. Its physical restoration
retry also left all thirteen icons unchanged. Management is off and the original
baseline is retained. Host acknowledgement and interior coordinates do not yet
establish physical restoration; that acceptance gate remains failed.

## Confirmed 81% overshoot and control-service correction — 2026-09-30

The owner reported that the 80% limit reached 81%. The authenticated live record
confirms a hold command at 80%, followed by a false verification failure about
55 seconds later. AppleSmartBattery still reported the old +56.22 W charging
flow throughout that period. The failure returned control to macOS and reset
qualification. Policy intent stayed enabled; this failure was not lost settings.
The subsequent signed SMC comparison reported 0 W while the registry retained
old discharge readings as well. Raw evidence is outside the checkout in
`work/acceptance/battery-upper-limit-*` and `battery-hold-flow-comparison-*`.

The protected service and monitor now share the scoped B0AP reader. A fresh zero
or negative flow clears the lagging charging flag; a fresh positive flow can
override a lagging paused flag. Unsupported live data retains the registry
fallback. A genuine positive flow after hold still fails verification. The
regression exercises the actual sensor decoder and controller, including the
observed stale-current sequence, without hardware writes.

Manual discharge requires verified discharge capability, while top-up still
requires charging and calibration requires both. This keeps the safe discharge
action available when charging qualification must wait for the lower bound.
Reauthorizing the helper records a durable request to restore an enabled saved
policy. A disabled policy is not automatically activated.

The focused battery gate passes 238 checks; the complete gate passes 81,672
Swift checks, preference cleanup and eleven installer checks. The optimized
candidate passes packaged selftest and deep strict signature verification.
Five read-only production sensor samples on this Mac reported 81%, 0 W and
charging false. That is production sensor evidence, not an upper-limit pass.

The candidate helper version is
`18d21bce572b8df65f4555a0b82dd28c4d4c7e4e4e4cd5e8163ffa625ff28a16`.
It is not yet installed. The live helper must return hardware to macOS and
unregister before the installer accepts a changed helper. The control tool
repeatedly lost the settings window, so the owner was asked to turn off the
Battery care feature and quit Aster. The exact enabled 75–80%, 38/36°C,
automatic-discharge-off policy and a rollback app are saved. Installation,
automatic policy restoration and a new real charging cycle remain required.

## Safe service update installed; macOS approval renewal pending — 2026-09-30

The settings-control blocker was bypassed through a new closed, signed app
entry point, `--battery-prepare-update`, which reuses the actual uninstall
path's authenticated return-to-system and ownership/recovery checks. It keeps
the saved policy and feature settings. A successful release records durable
policy-restoration intent. The next normal app launch registers a replacement
only when that enabled saved intent exists. A normal first launch or disabled
saved policy does not install a privileged service automatically. CLI registration
also records the actual helper version, preventing an unnecessary second upgrade.

The native installation used two verified packages: an interim host with the
old helper and launch plist unchanged, then the final package after authenticated
release and confirmed removal of the old launchd service. Aster was quit through
its own native shortcut. Both installation steps passed the existing guard.
The app-directory inode stayed 35397683; the current helper version is
`18d21bce572b8df65f4555a0b82dd28c4d4c7e4e4e4cd5e8163ffa625ff28a16`.
The exact saved enabled 75–80%, 38/36°C, automatic-discharge-off policy remains.
The complete final gate passes 81,707 Swift checks, preference cleanup and eleven
installer checks; battery care passes 264 and menu bar passes 450. Candidate,
interim and installed packaged selftests and strict signatures pass.

Aster relaunched as PID 87247 and registered the new helper automatically.
However, launchd never started it: the job reports EX_CONFIG and the kernel
records an enforced launch-constraint violation for the new executable. Its
installed code hash and plist SpawnConstraint match; strict signature verification
passes. Refreshing this app's LaunchServices registration did not establish a
successful service connection. The enabled macOS background switch alone is not
proof of a working controller. No charge-limit or self-recovery pass is claimed.

System Settings was opened to Login Items & Extensions. Aster's background
switch was on. Refreshing that existing approval brought up the native Login
Items Touch ID prompt. The owner was asked to complete that authentication;
the previous manual feature-off/quit request is superseded. The pending prompt
is saved as `work/acceptance/battery-menu-safe-update-approval-prompt.png`.
Before approval, a read-only production helper probe reported 87%, +44.285 W
and hardware in system charging state. Battery protection is not active during
this approval/start failure, despite saved enabled policy intent.

The exact native release, installation, first status, launchd/kernel logs and
read-only probe are in `work/acceptance/battery-menu-safe-update-*` outside the
checkout. Approval completion, actual helper startup, saved-policy restoration,
stable hold and a new charge-to-80% cycle are still required.

## Destination-bound menu move transaction — 2026-09-30

The previous interior-coordinate candidate failed real restoration. The mover
now uses Ice's explicit source press and destination release, both delivered to
the dragged item's host. It carries a verified destination window alongside
its current frame. Each phase requires actual source-frame change after the
delivery handshake; acknowledgement alone is insufficient. Interrupted
delivery releases at the original position. Generic hover-routing exceptions
remain phase-specific and ordinary activation stays strict.

The actual production move and frame-wait bodies were compiled against inert
relay/window endpoints. They verify distinct press/release windows, original
host routing, modifier clearing, both failure phases, fallback release and
abort on unchanged geometry. No input is posted by these tests. The final
installed package includes this correction, but physical menu restoration has
not yet been retested. Management remains off and its original baseline stays
saved. Multi-display and Spaces gates remain open.

## Approval restored control; host update retained the live service — 2026-09-30

The owner approved the Login Items Touch ID prompt. Native System Settings then
showed Aster's background switch on. Launchd started the installed replacement
as PID 49955, and authenticated status succeeded. The enabled 75–80%, 38/36°C
policy returned automatically without re-entry; the pending restoration flag
cleared. The first reading reported a hold at 95%, 0 W and charging false,
with hardware ownership and no pending recovery. The battery reached that high
level during the earlier inactive-service period, not because Touch ID itself
enabled charging. A real recharge-to-80% pass is still required.

During the next readings, the native UI and saved policy both showed automatic
discharge enabled. Five authenticated samples confirmed the discharge command,
physical adapter presence, negative live battery power and enabled 80% limit.
The latest owner configuration is preserved; automatic discharge is now on.
The evidence is `battery-after-touch-id-status.json` and
`battery-after-approval-automatic-discharge.jsonl` outside the checkout.

The app now tracks an authenticated helper response separately from macOS
registration. An unreachable service shows that the saved range is inactive,
provides a connection retry, and refreshes its local battery reading instead of
leaving stale telemetry visible. Controls require a responding service. The
initial replacement policy cannot overwrite saved editor intent during automatic
restoration, and failed saves return to the last saved policy rather than an
inactive stale daemon snapshot. The status copy covers all fifteen languages.
Tests compile the actual response/error handlers and editor methods against
inert endpoints; no system preferences or hardware are modified by those tests.

The focused battery gate passes 290 checks; the complete gate passes 81,763
Swift checks, preference cleanup and eleven installer checks. The optimized
release, staged and installed packaged selftests, and deep strict signatures
pass. This host-only update retained the identical live helper code identity
and executable inode 36658241, the app directory inode 35397683, and helper
version `18d21bce572b8df65f4555a0b82dd28c4d4c7e4e4e4cd5e8163ffa625ff28a16`.
The protected service continued discharging while the app was closed for
installation, and after the updated host relaunched as PID 54888. No new
background-service approval was required for this unchanged-helper update.
The native updated settings view shows enabled policy, negative live flow and
the saved range. Evidence is `battery-service-availability-*` outside the checkout.

Automatic discharge completion at 80%, sustained hold there and a new actual
charging cycle remain unverified. The current successful service response and
app restart do not establish sleep, system restart, top-up or calibration parity.

## Native destination transaction still needs correction — 2026-09-30

The installed two-phase menu transport was physically exercised through Menu
Bar settings → Restore original layout. Both phases were acknowledged: Siri
window 5139, then Clock window 24, delivered to host 625. The before and after
inventories retained the same thirteen-item order. The original ten-item
baseline remains saved, and management is off. This is a native restoration
failure, not a success inferred from delivery. Raw inventory and logs are
`menu-destination-*-restore-inventory.json` and
`menu-destination-restoration-runtime.log` outside the checkout.

The release position was computed before the source press. Removing a source
to the left of the destination can shift that destination, making the stored
drop coordinate wrong. The transaction now re-reads the same destination
window after the confirmed source-frame change and computes the requested
side from its current frame. A missing or off-row destination releases at the
original position. This matches the refreshed-endpoint handling in Thaw's
move transaction. The actual production body is tested against a reflowing
destination, left/right placement and disappearing targets. The focused menu
gate passes 453 checks. The complete gate passes 81,766 Swift checks, preference
cleanup and eleven installer checks. The optimized correction was installed
with strict signatures and packaged selftests verified, retaining the same live
battery helper and app-directory inodes. Another native restoration attempt is
still pending; no menu restoration pass is claimed.

## Automatic discharge reached the owner's 80% limit — 2026-09-30

The restored service reduced the displayed macOS charge from 95% to 80%, then
changed from discharge to hold. Authenticated samples at the transition show
0 W and charging false, physical adapter presence, an enabled 75–80% policy,
hardware ownership and no pending recovery. The current configuration retains
automatic discharge on and 38/36°C heat thresholds. The app's native Power
popover independently shows Battery 80%, Charging paused and 0.0 W.

The unchanged battery service remained PID 49955 with one execution while the
host was quit, updated and reopened as PID 76522. Its event history retains
the discharge-to-hold transition without a subsequent verification failure.
One read-only CLI observation failed during the second host replacement; the
first sampling run therefore ended before its intended three-minute hold gate.
That observation gap is not counted as a pass. A fresh post-update hold run
was started, with the app open and the owner using its Power popover.

Evidence outside the checkout: `battery-restored-automatic-limit-cycle.jsonl`,
`battery-at-80-during-second-host-update.json`,
`battery-post-update-control-continuity.json` and
`battery-post-update-native-power-panel.txt`. The new post-update hold run passed
thirteen authenticated samples across 190 seconds: 80%, charging false, 0 W,
enabled policy, hardware ownership and no pending recovery throughout. Its
report is `battery-post-update-80-hold-report.json`.

A bounded manual discharge to 75% was then started through the installed app's
authenticated, validated diagnostic request. The exact enabled 75–80% policy,
automatic discharge and 38/36°C thresholds remain saved in the operation for
automatic restoration. Aster stays open. The next gate observes actual charging
back to 80% and another three-minute hold. No charging-cycle pass is claimed yet.

The installed fresh-destination transport was retried against the actual menu
bar. Source and destination events reached Control Center, but the thirteen
items retained their order. The original ten-item baseline remains saved and
management is off. Native restoration still fails; delivery acknowledgements
are not a movement pass. Evidence: `menu-reflow-before-restore-inventory.json`,
`menu-reflow-after-restore-inventory.json` and
`menu-reflow-restoration-runtime.log`.

A subsequent candidate removes cursor disassociation during command drags,
matching the public reference's hidden-but-associated cursor. Release
confirmation and resting-frame checks still precede restoring the pointer.
The actual production cleanup body passes 453 focused menu checks against
inert endpoints. This candidate has not yet passed native restoration. Aster
remains open while the battery completes the charging-cycle gate.

The actual recharge cycle passed: 55 authenticated samples showed charging
from a minimum of 75% to a maximum of 80%, then 180.65 seconds of hold at 80%
with charging false and 0 W. Hardware ownership and the exact enabled policy
remained intact, with no pending recovery. Aster was open throughout this
cycle. The helper remained PID 49955 with one execution. Evidence:
`battery-75-to-80-live-cycle.jsonl` and
`battery-75-to-80-live-cycle-report.json`. This establishes the repaired live
charge-to-limit behavior, not every sleep/restart or calibration scenario.

The associated-cursor candidate built, signed and passed packaged self-test,
then failed its physical restoration retry. Unlike prior attempts, the
acknowledged press now produced a release with destination hit-test windows
24/24 but event window 5139, the acknowledged Siri press origin. Aster rejected
that recorded host rewrite, released safely and retained the thirteen-item
physical order plus the ten-item baseline. Evidence:
`menu-cursor-restoration-runtime.log` and
`menu-cursor-association-native-report.json`. The battery helper's PID and
executable inode remained unchanged; authenticated post-update status still
shows 80%, 0 W, owned hardware, enabled policy and no pending recovery.

The next correction recognizes only this completed-press release form at the
verified host stage. Both destination hit-test fields, host, release type,
location and cleared modifiers must still match. The captured event window
must be the same origin acknowledged earlier by this transaction; closing or
failing the transport discards that origin. No unrelated window is accepted.

The captured-origin release correction passed 469 focused and 81,783 full
Swift checks, preference cleanup, eleven installer checks, optimized build,
strict signature verification and installed self-test. Its physical retry
reached both delivery acknowledgements without rejecting the recorded host
release, but the thirteen-item menu order still did not change. Management
is off and the ten-item baseline remains saved. This fixes the observed
delivery rejection but does not establish working native restoration.
Evidence: `menu-drag-origin-native-report.json`, the corresponding before/after
inventories and `menu-drag-origin-restoration-runtime.log`.

## Full visible menu gesture and cleanup recheck — 2026-09-30

The installed mover now uses a full horizontal Command-drag gesture inside one
notch-safe display segment. Four drag events, a fresh release endpoint and all
release recovery guards passed 489 focused checks and the optimized build. The
actual restoration retry still failed: press and release were acknowledged but
all thirteen physical icons retained their order and frames. Management is off;
the original ten-entry baseline is retained. See
`menu-visible-drag-native-report.json` and its inventories/runtime log.

After this host update, authenticated battery status still reported the saved
enabled 75–80% policy, automatic discharge on, owned hardware, no pending recovery,
80%, hold, not charging and 0 W. See
`battery-after-visible-drag-update-status.json`.

Current cleanup checks scanned only a generated five-file scope. The map opened
a subfolder and Back returned to the overview. A three-copy duplicate review
retained its keeper and remaining extra copy after moving one copy to Trash.
Finder Put Back restored the text file; every original hash matched. The shipping
ClamAV page updated and independently verified official definitions, completed a
four-file local scan, and cleared its report when a different generated folder
was chosen. A normal visible generated app was also reviewed and moved to Trash.
Put Back was disabled for that app; Finder Move Here restored it with all hashes
unchanged. The generated app was moved out of Applications after this test.
See `cleanup-current-*` and `uninstaller-current-visible-*` evidence.

The final presentation candidate exposes recovery directly in duplicate results
and avoids claiming that Trash movement frees disk space. Its uninstaller names
Finder's manual move as a recovery fallback. The menu gesture now uses the top
edge of the menu row and waits briefly for the real cursor warp before pressing,
matching the current Thaw gesture geometry. This correction passed 490 focused
checks and the optimized build; its native movement gate still needs a retry.

The final candidate is now installed: 81,805 full checks, preference cleanup,
eleven installer checks, packaged selftest and strict signatures passed. The
registered app directory and battery-helper vnode were retained. Authenticated
status still reported enabled 75–80%, automatic discharge on, owned hardware,
no recovery, 80%, hold, not charging and 0 W. The direct duplicate recovery link
was exercised in the installed build; it selected the exact generated text file
in Finder Trash and Put Back restored unchanged contents. See
`cleanup-final-recovery-report.json` and `cleanup-menu-final-install-report.json`.

The installed top-row menu retry still failed, despite acknowledged press/release.
All thirteen physical icons retained their order and frames. Management is off
and the saved baseline remains. See `menu-top-row-native-report.json`. Bartender
movement and restoration remain the main unfinished native gate; other required
battery lifecycle and display/Space acceptance gates are not waived.

Aster is left running on Battery Care. The unchanged service remains PID
49955 with one execution; fresh authenticated status after this update still
shows 80%, charging false, 0 W, the exact enabled 75–80% policy with automatic
discharge, owned hardware and no pending recovery. The app update did not
require approval or policy re-entry. Further menu transport work remains.
