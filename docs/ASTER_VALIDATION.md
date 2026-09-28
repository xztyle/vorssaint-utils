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
- The integrated final executable still requires its own build/selftest.
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
RTF/plain text before dismissing the drawer. General clipboard capture, direct
paste, cross-app drag and display/Space checks remain open. A CUA no-window timeout
was not proof of a frozen app.

Menu-bar implementation `7b03b9f` passed 9,845 focused checks. Root rebuilt its final
source, packaged/signed the app and ran the packaged selftest successfully. Actual
read-only inventory found one display and 11 items: seven stable, four provisional,
six movable; no competing manager. No live menu layout change has been made.
Save and verify restoration of the original layout during the interaction gate.

The owner granted Accessibility. The first GUI startup crashed because macOS 26
returned a remote status-window number of 8,589,934,592, beyond a WindowServer
UInt32 identifier. Root replaced the trapping conversion with exact validation;
the regression, optimized build, packaged selftest and next GUI launch passed.
The live manager still left ten of eleven items unresolved and locked. Root is
testing standard AXPosition/AXSize fallback and cache fixes before attempting
movement. Turning the manager off removed its controls and cleared the completed
restoration baseline; no user icon was deliberately moved.

All browser research and browser acceptance checks use the Codex in-app browser.
The owner's personal browser is excluded from the workflow.

## Capture and cleanup

Capture's initial focused suites and optimized build passed. Actual UI editing
added an arrow to generated Capture 3; Done returned it to the corner with the
same capture ID and revision 1. The separate generated-only drop receiver then
crashed on an AppKit text-view initializer. The worker added actual construction
and image-import regressions and is rebuilding the correction before retrying
the drag. This test fixture failure is recorded separately from the menu crash.

Cleanup's first optimized integration build passed. Generated-file tests include
an actual Trash move and restoration through its returned URL. Its actual ClamAV
backend scanned private snapshots of benign/EICAR controls after verifying official
definitions and produced the expected one finding while retaining the originals.
Final source review, build and UI acceptance remain in progress.
Use generated local files for all removal, image input and malware test actions.
Do not send messages, upload to remote services or delete personal files for tests.

ClamAV 1.5.4 was installed through Homebrew for the optional local scanning backend.
No scanning daemon was started. Official definitions downloaded successfully;
their detached signatures were verified against ClamAV's signing certificate.
A bounded scan of two generated files reported the benign file as OK and the
standard harmless EICAR test file as a match, with the expected exit status 1.
This proves engine integration prerequisites, not Aster's forthcoming scanning UI
or the security of any personal file. No personal files were scanned.

## Worker limit

Five researchers and four separate implementation workers were created with the
requested model settings. The environment refused a tenth separate worker and
also refused restarting a finished worker. The active clipboard implementation
worker therefore continues cleanup in its dedicated cleanup worktree with the same
GPT 6 Astra/xhigh settings. The owner was told about the limitation. All five
feature scopes retain their separate research, implementation branches and review.

## Final gate

Each feature needs its reviewed implementation, relevant automated tests, optimized
build and selftest, actual-Mac interaction evidence and recorded unresolved limits.
Only then merge that feature into main. Repeat the combined build and appropriate
integration checks after all five merges. No release, version tag or published
installer has been authorized.
