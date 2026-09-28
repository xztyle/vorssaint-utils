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

The feature branch is `bd51e78`. The latest integration battery suite passed
162 checks; its optimized build and selftest passed. The signed app and helper
retain the same local signing identity and authenticated request boundary.

The owner approved the background service. After temporarily allowing native
charging to 100%, the real qualification measured charging at 43.763032 W and
then a hold at 0 W. The intentional discharge stage failed because the controller
mistook its own adapter cutoff for physical unplugging. Later telemetry measured
-18.2295 W. The failed sequence restored system control, with policy disabled,
no hardware ownership and no recovery pending. macOS's limit was restored to 80%.

`51b137a` distinguishes physical adapter presence (`AppleRawExternalConnected`)
from effective power connection. Regression checks cover the intentional cutoff
and actual unplugging. The correction has not yet completed real qualification.

Installing that build exposed a helper replacement problem. The first new helper
launch failed a macOS launch constraint; later launches could not resolve the
registered program and exited with EX_CONFIG. `b3d1ed9` fixes the premature
re-registration race by awaiting asynchronous service removal. Restoring the
exact previous signed app did not recover the broken registration.

Battery care availability is currently off. The actual read-only hardware probe
reports AC enabled and charge inhibit cleared; its default state object is not
proof of the protected saved journal. The last authenticated status before the
launch failure was disabled and unowned. A current administrator read of the
journal is requested from the owner. Computer Use denied Terminal, so no alternate
UI route was used to bypass that restriction.

`bd51e78` adds an explicit, unregister-only maintenance diagnostic. It requires
the feature off, stable signing and the actual restored hardware baseline. It
awaits removal completion and does not write hardware or saved state. Execution
is pending the independent journal check; the normal authenticated restoration
guard remains unchanged. Re-registration and actual helper response must follow
before another qualification attempt.

`558b5dd` gives measured charge, battery temperature and power visible
localized labels and distinct VoiceOver names. The battery development build
passed; the existing 162 battery checks passed but do not exercise that UI.
Solid SettingsCard content groups fit Apple's guidance to place Liquid Glass on
floating controls rather than every data card.

Remaining actual-Mac checks include full charge/hold/discharge/charge qualification,
range and thermal behavior, cancellation/restoration, unplug, top-up, calibration,
schedules, app/helper restart, sleep and system restart. Coordinate sleep, unplug
and restart with the owner. Final intended use is macOS at 100% and Aster enforcing
the saved 75–80% range; the temporary native 80% limit remains during repair.

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

`7c77372` exposes all file URLs in a copied multi-file clip through a native
external drag from the file icon. A generated two-file payload check passed in
the 691-check clipboard suite, and the optimized build passed. The drawer's
navigation and footer now use shared glass; content stays legible, with solid
surfaces for Reduce Transparency and Increase Contrast. The external drop,
automatic paste and shortcut still need live Mac checks.

Menu-bar implementation and its earlier signing/selftests passed. Initial GUI
checks exposed a trapping conversion of a macOS status-window ID and blank
WindowServer titles. Exact identifier validation and AX identity resolution fixed
those failures. A later passive GUI diagnostic resolved all ten icons and kept
their frames unchanged. Accessibility is approved.

The first successful Docker-to-Hidden move used the acknowledged event relay.
Docker moved from x=1473 to x=1708, between the hidden-section dividers. Siri and
Control Center also exchanged order, so this did not establish correct isolated
reordering. Undo then moved Wi-Fi off the menu row, and Now Playing disappeared.
Root restored both system icons through System Settings, preserving Now Playing's
Show When Active setting. All original icons are visible again.

The next corrections restrict planning to displaced items, keep drag gestures on
the top edge, reject off-row geometry, complete acknowledged releases, wait for
stable frames and preserve Undo when an original identity is temporarily missing.
The installed retry exposed another concrete failure: WindowServer changes hover
fields during a valid drag. `a226ea8` accepts those hover-field changes only for
drag/release while preserving token, event type, host PID and explicit destination
checks. Its 388 menu checks passed, including the recorded event patterns.

The latest correction is built but not installed. Menu management is off. Original
physical order is not yet restored, and its recovery baseline remains saved.
Actual reorder/Undo/restoration, always-hidden access, notch panel, search,
shortcuts, profiles, reveal rules, new/restarted icons and display/Space/full-screen
behavior remain required live gates.

`080a8df` fixed a real menu event-tap source failure path and replaced a brittle
teardown guard with lifecycle checks. Its branch passed 405 menu and 257
repository checks. `b7a54cb` puts the floating menu search panel on the shared
glass surface. The development build and 405 menu checks passed. That panel and
the corrected drag/Undo path still need live visual and behavioral checks.

All browser research and browser acceptance checks use the Codex in-app browser.
The owner's personal browser is excluded from the workflow.

## Capture and cleanup

Capture's focused tests, optimized build and generated native drop fixture passed.
The fixture preserves edited capture identity, exact transferred PNG bytes and
multiple previews; discard cancellation and undo were also exercised. These are
separate from the production checks below.

The owner approved Screen Recording and the follow-up direct-capture prompt.
Installed `1b7637c`, containing capture `cf1f9f2`, captured a real 1490 × 260 pixel
region of the generated local browser test page. It appeared in the bottom-left
preview. Editing added a red arrow, and Done returned the arrow to the corner.
Copying that preview and pasting into a separate TextEdit document preserved the
image and arrow, verified visually. The original generated text document was
preserved through TextEdit's Duplicate conversion action.

An actual native drag generated a 47,010-byte PNG with SHA256
`3917a710c65b6014d5727ead253ec53e6dd19935ce99aa376ff713fc0d042062`.
App-bound automation did not deliver the external drop to TextEdit or the in-app
browser. The latter also uses a separate virtual clipboard. These observations do
not establish a product defect or a successful external drag. The old installed
preview's lifetime is temporarily Until closed; restore the prior 30-second
setting after acceptance unless the owner chooses otherwise.

`771c064` changes the resting bottom-left preview to the screenshot image
alone. Actions appear on hover; a left-edge drag dismisses only when no other
app accepts the drop. The screenshot suite passed 830 checks, and the separate
development bundle built and passed selftest. A generated-image fixture was
launched through Computer Use before any app or helper startup. Its actual
320 × 178 point corner window showed only image pixels, with no frame, border,
backing, caption or toolbar. Escape closed it. Pointer automation could not
reliably address that transient window, so hover, left drag, cancellation during
drag and external drop are still unverified in the live UI. See the capture
branch's `ASTER_SCREEN_CAPTURE.md` for implementation and test details.

Settings navigation also hung when search jumped to a disabled feature. `bdc9adb`
replaces the nested lazy feature cards and overlapping delayed jumps with bounded
cards and one cancellable target jump. Its relevant 1,482 checks passed; the old
navigation failed three regression checks. The combined build contains the fix,
but actual visible navigation must still pass after installation.

Cleanup's generated engine tests, optimized build and selftest passed. Live
result-header changes fixed an app-control accessibility-reader crash without
requiring a Codex restart. A duplicate scan displayed exactly Original.txt and
Duplicate.txt. Choosing Original as keeper, selecting Duplicate, reviewing both
paths and moving Duplicate to Trash succeeded. The recovery panel showed the
actual Trash URL. Finder Put Back restored Duplicate with the same hash as
Original, and restored the earlier generated 8 MiB large file. No personal files
were removed. The 180-day old-file filter selected the 400-day sample; the large
filter showed none at 100 MB and the 8 MiB file at 1 MB.

`be160e3` fixes the generated receipt observer's treatment of an existing root and
missing original under /private/tmp. The old code fails its regression and the
new storage suite passes 94 checks. Actual production recovery UI had already
shown the correct Trash URL. The same commit changes security-inspection result
headers after that separate view triggered the accessibility-reader crash.
Two unregistered generated startup plists are prepared for the live retry; the
security result view and updated receipt observer still need that check.

`006ef0f` stops the cleaner's progress glyph animation under Reduce Motion.
The optimized build passed. The later combined signed bundle includes this
change and remains uninstalled.

ClamAV 1.5.4 was installed through Homebrew for optional local scans. No scanning
daemon was started. Official definitions passed detached-signature verification.
Actual malware UI inspected four generated files and displayed the expected
harmless EICAR match, with Partial coverage because a link and app package were
excluded. No personal files were scanned. This is bounded engine/UI evidence,
not a claim that the owner's files are safe or that all malware is detectable.
Use only generated files for removal, image input and malware acceptance checks.

## Worker and model routing

Five researchers and four separate implementation workers were created with the
requested model settings. The environment refused a tenth separate worker and
also refused restarting a finished worker. The active clipboard implementation
worker therefore continued cleanup in its dedicated cleanup worktree with the same
GPT 6 Astra/xhigh settings. The owner was told about the limitation. All five
feature scopes retain their separate research, implementation branches and review.

The owner later required GPT 6 Sol at xhigh for all further work. The Astra
workers were interrupted. Sol workers continued capture, clipboard, menu and
battery UI work; the primary agent owns integration and Mac acceptance.

## Final gate

The detached `work/integration` checkout combines all five branches before their
acceptance merges to main. Shared defaults, feature labels, backup settings and
entry points were reconciled. Menu and battery restoration remain ahead of normal
uninstall. Earlier integration failures in expected feature count, translated
punctuation and test preference cleanup were corrected.

Integration `8076c3e` combined the five feature branches before the cleanup
fixture retry. Its
optimized build and packaged selftest passed. The full suite passed **70,812
checks**, including 257 repository and 830 screenshot checks; preference cleanup
passed. The previous full run failed one source guard because capture borderless
menus were not both explicitly sized. `f78c1d2` corrected the menu sizing, and
the exact combined source passed the final repeat. Earlier, `080a8df` fixed a
real menu event-tap source failure path and replaced another brittle guard with
lifecycle checks. Its feature branch had passed 405 menu and 257 repository checks.

That bundle was copied without synced-folder metadata to
`/Applications/.Aster-verified-8076c3e-ac6d74f7.app` and passed deep strict
signature verification. Its executable SHA256 is
`30f823a3ba7454d6b8ebd621c1722283aa327a5c42f06a305e4dc569d6f1b4cd`.
It has not replaced the installed app. A separate generated-image development
fixture checked the bare screenshot preview without changing the battery helper.
The installed app remains the restored `1b7637c`, and the stopped helper's broken
registration is unresolved as described above.

The first signed cleanup fixture opened ordinary onboarding because macOS
resolved its prepared `/private/tmp` path to `/tmp` before a path check. It was
closed without setup. Cleanup branch `aa51c35` now resolves the path through
the scanner's canonical path check, requires the prepared marker, and accepts
the `/tmp` alias in a regression check. Its scoped suite passed 97 checks and
the development build passed. A newly signed, distinct generated-only fixture
opened the intended cleanup view. The actual UI showed two generated startup
entries without the earlier accessibility-reader crash. A generated duplicate
was reviewed, moved to Trash, shown in the recovery view, and restored through
Finder Put Back with a matching SHA256. No personal file was scanned or removed.

Current detached integration `b0da423` contains cleanup `aa51c35` and the
other four feature heads. Its optimized build and packaged selftest passed.
The full suite passed **70,815 checks** and preference cleanup passed. A fresh
metadata-free bundle at `/Applications/.Aster-verified-b0da423-ew52lblr.app`
passed deep strict signature verification, with executable SHA256
`19bd2ac2872a09a645dada8857babd165c7835f609ca1cac4b8eaee995e755d1`.
It has not replaced the installed app. All feature heads are pushed: battery
`558b5dd`, clipboard `7c77372`, menu `b7a54cb`, capture `f78c1d2`, cleanup
`aa51c35`. Actual-Mac replacement acceptance remains incomplete.

The current screen-capture branch `9906312` adds continuous left-swipe motion
to the bare corner image. Mouse dragging moves the card directly; a two-finger
trackpad swipe uses AppKit's gesture progress and release animation. A short or
cancelled gesture now eases the card back instead of snapping it. A completed
gesture slides the whole card off-screen before closing. The 834 screenshot checks, optimized build
and packaged selftest pass. The image-only preview was observed in a generated
fixture, but the Mac locked before live swipe feel and cross-app drop could be
verified. The new trackpad behavior has not yet been launched in a fixture or
installed app.

A generated-only app was selected in the installed Aster uninstaller, moved to
Trash, and restored with matching bytes through Finder's manual Move Here flow.
Finder's Put Back was disabled for this dot-prefixed test app. A visible-name
generated app is now signed and staged under `/private/tmp` for that test; it
has not been placed in Applications. No personal app was removed.

The upstream Vorssaint update through `bc51165` was merged into main. Its full
suite completed 79,560 checks with the same 14 notch and switcher visibility
failures already reproduced before this update; all other suites passed. New
menu-bar icon labels were rebranded to Aster in every provided localization.

Current detached integration `cbbccbe` combines upstream main and all five
feature branches. Its optimized release build and packaged selftest pass. A
metadata-free copy at `/private/tmp/aster-integrated-eased-23_9ahme/Aster.app`
passes deep strict signature verification. It is not installed; the protected
battery journal must be read before replacing the production app or helper.
The combined screenshot suite passes 834 checks. The last full combined run,
before the trackpad addition and feature-count correction, reported 15 failures
in 70,968 checks: one stale feature count, one notch-rail visibility check and
13 switcher-scroll visibility checks. The feature-count correction passes its
1,105-check suite. The other 14 failures also reproduced on unchanged main
while the screenshot fixture was open. A clean full rerun after closing the
fixture is required; no current full-suite pass is claimed. The protected
battery journal still needs its independent administrator read before the
production app or helper is replaced.

The full combined run after the trackpad change completed **70,970 checks**.
Only those same 14 layout checks failed; all other suites, including the 834
screenshot checks, passed, and preference cleanup passed. A distinct signed
generated-image trackpad fixture is staged for the live gesture check but has
not been launched while the Mac is locked.

After the eased swipe and upstream merge, the combined suite completed
**80,584 checks** with those same 14 layout failures and no new failures.
Screenshot, battery, clipboard, menu, cleanup and localization suites passed.
A newly signed generated-image fixture for the eased swipe is staged at
`/private/tmp/aster-swipe-eased-vfd4gn3d/Aster Swipe Eased.app`; it has not
been launched while the Mac remains locked.

Replacement acceptance has not passed. Main retains the baseline and evidence
docs; feature merges await their actual-Mac gates. Each feature needs its reviewed
implementation, relevant tests, optimized build/selftest, actual behavior evidence
and recorded limits. After all five acceptance merges, repeat the combined build
and appropriate integration checks. No release, version tag or published installer
has been authorized.
