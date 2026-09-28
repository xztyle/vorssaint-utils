# Aster verification record

Status: **in progress; replacement acceptance has not passed**.

Target: Apple M4 Max, Mac16,5, macOS 26.6.2. Checks below were run on
2026-09-28. Automated checks, actual UI behavior and battery power behavior are
separate evidence. A passing build does not establish a working replacement.

## Shared app identity

Baseline commit: `84a5839` on the owner's fork.

- Independent Aster app name, icon, bundle identity and stable local certificate.
- Upstream hosted sharing, feedback submission and binary updates are disabled.
- Original source attribution and the upstream remote are preserved.
- Baseline test suite: **69,795 checks passed**.
- Actual signing checks: **6 passed**, including wrong identity, ad-hoc signing,
  missing certificate and altered executable rejection.
- The final shared baseline suite passed **69,795 checks** after switching to an
  exact generated-source manifest and replacing a flaky 10 ms visibility-test wait
  with main-queue callback completion. Preference cleanup passed.
- Combined builds and selftests have since passed; see the final gate below.
- Existing sensor diagnostics read battery, CPU and GPU temperatures on this Mac.
- No GitHub Actions run was available for the fork at the time of inspection.

## Transition from the old utilities

At the owner's request, AlDente, Paste, CleanShot X, Bartender, CleanMyMac's menu
and health monitor, and iStat Menus 7 were stopped. The remaining iStat and
CleanMyMac protected services were stopped through macOS's administrator prompt.
Process inspection confirmed that these utilities and their helpers were absent.
They have not been uninstalled or had their login settings disabled; reboot can
start them again. Battery restart checks must account for competing controllers.

The prior AlDente configuration was read narrowly: 75–80% charging range,
38°C heat cutoff and automatic discharge. These are the initial Aster editor
values, with control disabled until explicit service setup and qualification.

## Battery care

Implementation commits `3b06ad5` and `df50725` are on the battery feature branch.
Scoped suites passed **9,327 checks**, including 121 battery checks. Root rebuilt
the final app and helper, verified packaging/signing, and ran the packaged app
selftest successfully. The read-only probe now includes firmware
`mBoot-18000.161.10` in its qualification fingerprint.

Root installed the signed battery build at `/Applications/Aster.app` and the owner
approved its background service. First registration required handling macOS's
`.notFound` and pending-approval states; the fixes passed an optimized build,
packaged selftest and 121 battery checks. Authenticated status reached the running
daemon with policy disabled. The initial qualification attempted its charging
stage, timed out after 90 seconds without measured charge power, and restored
system control with no hardware ownership or pending recovery.

System Settings showed macOS's own 80% charge limit blocking charging at the
current 80%. Permission to temporarily change it to 100% and restore 80% is
pending. The limit remains unchanged. There is no successful power-flow
qualification, sleep/reboot test or calibration cycle yet.

Required remaining actual-Mac checks include the bounded charge/hold/discharge/
charge qualification, range and thermal behavior, cancellation and restoration,
unplug, top-up, calibration, schedules, app/helper restart, sleep and system restart.
Do not interrupt the owner's work with a sleep or restart without coordination.

## Clipboard and menu bar

Clipboard implementation `9a1faac` passed an optimized build, packaged selftest,
688 clipboard checks and 9,500 related checks. Generated clipboard fixtures use a
separate profile and pasteboard, without personal history or global paste actions.
Actual UI checks found the initial floating presentation did not meet the owner's
request; it was replaced with a full-width drawer over the Dock. The live receipt
records a 2056 × 440 point panel at (0,0), matching the screen's bottom and width,
at window level 21 above Dock level 20. Search, image preview, formatted rich-text
preview and the transition into edit-a-copy were exercised. Copy put PNG/TIFF on
the named fixture pasteboard. Normal dismissal raced later UI inspection; the
fixture alone now stays open while the owner works elsewhere. Its rebuilt app
passed selftest. Actual UI checks then saved an edited copy while preserving the
original rich text, created a colored collection and pinned the copy into it,
found and previewed generated item 49,999 in a 50,000-entry library, and copied
RTF/plain text before dismissing the drawer. The installed combined app then
captured two generated TextEdit copies through the general clipboard. Selecting
the older copy and pressing Command-V in TextEdit preserved its bold formatting.
Both entries survived an abrupt app termination and relaunch, and remained readable
in the bottom drawer. Automatic paste into the prior app, the global shortcut,
cross-app drag and display/Space checks remain open: app-targeted test input did
not establish normal foreground-app activation. A CUA no-window timeout was not
proof of a frozen app.

Menu-bar implementation `7b03b9f` passed 9,845 focused checks. Root rebuilt its final
source, packaged/signed the app and ran the packaged selftest successfully. Actual
read-only inventory found one display and 11 items: seven stable, four provisional,
six movable; no competing manager. These were initial read-only checks.

The owner granted Accessibility. The first GUI startup crashed because macOS 26
returned a remote status-window number of 8,589,934,592, beyond a WindowServer
UInt32 identifier. Root replaced the trapping conversion with exact validation;
the regression, optimized build, packaged selftest and next GUI launch passed.
The live manager still left nine of ten items unresolved after standard AX geometry
and cache fixes. A passive diagnostic launched through LaunchServices confirmed
the GUI has Accessibility permission but receives blank WindowServer titles. The
resolver wrongly rejected specific Control Center AX identifiers in that case;
some third-party apps expose one unnamed AX icon. Fix `c9e5940` passed 215 menu
checks, 215 test-harness checks, an optimized build and selftest. A second passive
GUI diagnostic resolved all ten icons, protected Clock and Control Center, and
left every icon frame unchanged. The GUI process was launched by LaunchServices
with parent PID 1. Turning the manager off removed its controls and cleared the
completed restoration baseline before movement tests began.

The first actual Docker-to-Hidden action failed without moving an icon. Binding
input to the hosted window (`2744f07`) alone did not fix delivery. A bounded
session/host acknowledgement relay and independent release watchdog (`bf83176`,
`ba0e9b8`) passed 266 menu checks and the combined optimized build/selftest. The
next real GUI action succeeded: Docker moved from x=1473 to x=1708, between the
always-hidden divider at x=1670 and hidden divider at x=1753. Both press and release
were acknowledged for window 2611 in host PID 625. Siri and Control Center also
exchanged order during the move; do not claim only the target changed. Undo and
full layout restoration remain unverified. The owner was interacting with Aster,
so further UI work is waiting for a brief coordinated test interval.

All browser research and browser acceptance checks use the Codex in-app browser.
The owner's personal browser is excluded from the workflow.

## Capture and cleanup

Capture's focused suites and optimized build passed. The separate generated-only
drop receiver initially crashed on an AppKit text-view initializer; the corrected
initializer, explicit text system and real image-import regressions pass. Live UI
then added an arrow to Capture 3, returned the same capture ID/revision 1 to the
corner, and dragged it into a native image-capable text input. The accepted PNG
hash exactly matches the committed edited image. A second preview also dragged
successfully. All three previews remained available. Cancel in the discard dialog
preserved the editor. Undo removed the annotation with only 141 pixels differing
by one 8-bit channel level after rendering. Drag cancellation, production capture
permission and a separate receiving app remain unverified. See ASTER_SCREEN_CAPTURE.md
on the feature branch for the precise fixture receipts.

Cleanup's final optimized build and selftest passed, with 88 core checks, 91 real
engine checks and 9,039 related checks. Generated-file tests include an actual
Trash move and restoration through its returned URL. The ClamAV backend verifies
official definitions, scans private benign/EICAR snapshots and produces exactly
the expected finding while retaining the originals. Live UI found a collapsed
fixture window; its correction now shows 1060 × 780 points of content and the
four generated files, with the link and package correctly skipped. Duplicate
results repeatedly crash the app-control service's accessibility reader at
`Array.remove(at:)`; Aster stays running and control of other apps still works.
Restarting Codex is not required to recover those other controls. Narrowing the
disabled duplicate controls and explicitly grouping results did not resolve this
tool failure. A further result-header change is built but awaits its live retry.

A GUI-triggered duplicate scan produced exactly the generated Original.txt and
Duplicate.txt pair with no incomplete-analysis flag; its generated-only receipt
confirms completion, not readable UI or keeper selection. The real Storage review
sheet showed only Large fixture.bin, and Move to Trash removed that generated
file from its original location. The recovery panel then triggered the same
tool-reader crash; Finder recovery remains unverified. No personal file was removed.

Actual malware UI checks passed: Definitions found ClamAV 1.5.4 and verified
current official definitions, then Malware scan inspected four generated files
and displayed one Eicar-Test-Signature match for the harmless test sample. It
correctly displayed Partial coverage because traversal excluded a link and app
package. The action receipt reports four scanned, zero malware-stage skips,
one finding, no failure or cancellation, and incomplete=true. This is bounded
engine/UI evidence, not a claim about the security of the owner's files.
Use generated local files for all removal, image input and malware test actions.
Do not send messages, upload to remote services or delete personal files for tests.

ClamAV 1.5.4 was installed through Homebrew for the optional local scanning backend.
No scanning daemon was started. Official definitions downloaded successfully;
their detached signatures were verified against ClamAV's signing certificate.
A bounded scan of two generated files reported the benign file as OK and the
standard harmless EICAR test file as a match, with the expected exit status 1.
The subsequent app UI check is recorded above. No personal files were scanned.

## Worker limit

Five researchers and four separate implementation workers were created with the
requested model settings. The environment refused a tenth separate worker and
also refused restarting a finished worker. The active clipboard implementation
worker therefore continues cleanup in its dedicated cleanup worktree with the same
GPT 6 Astra/xhigh settings. The owner was told about the limitation. All five
feature scopes retain their separate research, implementation branches and review.

## Final gate

A detached `work/integration` checkout combines the five feature branches for
early integration testing without changing main. Shared defaults, feature labels,
backup settings and entry points were reconciled; both menu restoration and
battery restoration remain ahead of uninstall. Its initial 3,403 scoped checks
found two failures: an expected feature count and translated punctuation. A full
run then found one unswept test preference namespace. All were corrected. The
latest combined full suite passed **70,530 checks** and preference cleanup. The
latest combined optimized build, packaged selftest and strict signature checks
passed. The original combined candidate was integration commit `4496af9`.
The installed candidate is now `1b7637c`, including the acknowledged menu mover
and cleanup result receipts. Its relevant combined suites passed 359 checks
(266 menu, 93 cleanup), optimized build and selftest. It is installed at
`/Applications/Aster.app`, with the previous app retained in a local backup. Its
installed selftest passed. A passive LaunchServices diagnostic confirmed that
Accessibility remains granted and all ten menu items resolve, with two protected.
The installed app can still authenticate to the battery service, which remains
disabled under normal system control with no hardware ownership or recovery owed.
The later result-header candidate `4c1b99b` is built and awaits its installed/live
check; it has not replaced the running app while the owner is using Aster.
This installation does not establish replacement acceptance: the outstanding live
checks and charging qualification above are still required. Main retains the
reviewed baseline and evidence docs; feature merges await acceptance.

Each feature needs its reviewed implementation, relevant automated tests, optimized
build and selftest, actual-Mac interaction evidence and recorded unresolved limits.
Only then merge that feature into main. Repeat the combined build and appropriate
integration checks after all five merges. No release, version tag or published
installer has been authorized.
