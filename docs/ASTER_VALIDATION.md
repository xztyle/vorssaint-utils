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
- An optimized Aster build and app selftest passed before the final baseline
  changes. The integrated final executable still requires its own build/selftest.
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

Implementation is being validated on its feature branch. Pure policy and injected
controller tests are separate from hardware proof. No Aster charging write,
daemon installation, sleep/reboot test or calibration cycle is recorded yet.

Required remaining actual-Mac checks include the bounded charge/hold/discharge/
charge qualification, range and thermal behavior, cancellation and restoration,
unplug, top-up, calibration, schedules, app/helper restart, sleep and system restart.
Do not interrupt the owner's work with a sleep or restart without coordination.

## Clipboard and menu bar

Feature branches are undergoing build and behavior checks. Generated clipboard
fixtures use a separate profile and must not read old history, monitor the system
clipboard or paste into the owner's working apps. Real capture/paste is a separate
test after the isolated UI pass. Menu-bar inspection must precede any layout move;
save and verify restoration of the original layout.

All browser research and browser acceptance checks use the Codex in-app browser.
The owner's personal browser is excluded from the workflow.

## Capture and cleanup

Research is complete. Feature implementation and integrated UI tests are pending.
Use generated local files for all removal, image input and malware test actions.
Do not send messages, upload to remote services or delete personal files for tests.

ClamAV 1.5.4 was installed through Homebrew for the optional local scanning backend.
No scanning daemon was started. Official definitions downloaded successfully;
their detached signatures were verified against ClamAV's signing certificate.
A bounded scan of two generated files reported the benign file as OK and the
standard harmless EICAR test file as a match, with the expected exit status 1.
This proves engine integration prerequisites, not Aster's forthcoming scanning UI
or the security of any personal file. No personal files were scanned.

## Final gate

Each feature needs its reviewed implementation, relevant automated tests, optimized
build and selftest, actual-Mac interaction evidence and recorded unresolved limits.
Only then merge that feature into main. Repeat the combined build and appropriate
integration checks after all five merges. No release, version tag or published
installer has been authorized.
