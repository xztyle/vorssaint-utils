# Aster replacement contract

Aster is Alejandro's personal, subscription-free Mac utility suite, based on
Vorssaint. Its purpose is to replace AlDente, Paste, Bartender, CleanShot X and
the useful cleanup functions of CleanMyMac in one app. The name Aster was chosen
by the owner. The source fork is `xztyle/vorssaint-utils`.

## Completion rule

Completion requires working software and real behavior checks on the owner's
Apple M4 Max, model Mac16,5, running macOS 26.6.2. Compilation, a simulated sensor,
a feature registry entry, or a passing structural test alone is not proof.
Do not mark the project complete while a required function is missing or while
hardware/permission-dependent behavior remains unverified.

## Battery care

- Configurable charge limit with clear actual charging state.
- Battery temperature cutoff and a separate resume threshold.
- Lower/upper charging range to prevent repeated small top-ups.
- Manual and automatic discharge while connected to power, with a lower bound.
- One-time top-up, then return to the saved charging policy.
- Calibration workflow with progress, cancellation and restoration of prior policy.
- Persistent schedules for the supported actions, including missed-run semantics.
- Verified behavior across unplugging, sleep/wake, app restart and system restart.
- Explicit capability detection, stale/missing-reading handling, competing-controller
  detection, authenticated privileged requests and a reliable return-to-system action.
- No hardware claim based only on a readme or successful write return code.

## Clipboard

- Fast history search at realistic large history sizes.
- Paste-informed visual cards, clear previews and an efficient keyboard workflow.
- The primary history opens as a drawer from the very bottom of the active display,
  across the screen and over the Dock. It is not a floating window above the Dock.
  Opening and closing use vertical motion, with Reduce Motion respected.
- Named pinned collections, editing and reordering.
- Preserve rich text, images and file references as appropriate for their types.
- Durable history, explicit retention, backups and migration without silent loss.
- Private-by-default exclusions and deliberate handling of secret-marked content.
- The user interface is an acceptance requirement, not optional polish.
- Research Paste's actual current interaction model online before designing changes.

## Menu bar

- Hide and reorder other apps' icons, plus an always-hidden section.
- A separate panel that keeps hidden items usable around the notch.
- Search, keyboard shortcuts, profiles and automatic reveal rules.
- Correct behavior with multiple displays, Spaces, full-screen apps and new/restarted apps.
- Preserve original layout on disable/removal and recover from stale item identities.
- State OS compatibility honestly; current Mac tests are mandatory.

## Screen capture

- Capture, corner preview, edit, and drag to an image-capable text input.
- Edited images must remain available in the corner and drag with all edits applied.
- The resting bottom-left preview is only the screenshot image: no persistent
  border, frame, backing, padding, caption, toolbar or shadow. Its size follows
  the image rather than a fixed card size.
- Reveal capture actions on hover, without changing the screenshot pixels.
- A leftward swipe moves the actual preview with the pointer, then smoothly
  carries the whole card past the source display's left edge on release. A short
  or cancelled swipe returns it to its starting position. A successful drop
  into another app takes precedence and must transfer the edited image as native
  image data or a file, including into image-capable text fields.
- Predictable preview lifetime, multiple captures, keyboard actions and cancellation.
- Keep existing capture, annotation, recording and local-sharing functions working.

## App-wide appearance

- Use macOS 26 Liquid Glass for top-level floating controls and navigation,
  following the system's light/dark appearance and user-selected accent.
- Keep content itself legible and visually clean. Glass must not cover or alter
  screenshots, image previews, data cards or text merely to increase its use.
- Respect Reduce Transparency, Increase Contrast and Reduce Motion. Keep the
  same functions available through keyboard and accessibility controls.
- Verify the principal surfaces of all five replacement features on this Mac.

## Cleanup

- Extend the existing cleaner and uninstaller with useful storage inspection,
  large/old-file discovery and duplicate handling where safe.
- Review results before removal; prefer Trash and preserve recovery paths.
- Add bounded malware/security inspection using credible available mechanisms.
  Explain evidence and limitations; never call a file safe merely because a limited
  scan did not flag it. Do not invent an antivirus engine or misleading guarantees.
- Avoid deleting user data, cloud-only files, shared app data or credentials by inference.

## Delivery and engineering

- Five branches: `feature/battery-care`, `feature/clipboard`, `feature/menu-bar`,
  `feature/screen-capture`, `feature/mac-cleanup`, each with a distinct worktree.
- The original research and implementation workers used the requested separate
  feature scopes. From the owner's later instruction onward, use GPT 6 Sol at
  xhigh for all further work; do not resume GPT 6 Astra workers.
- The primary agent owns shared identity/signing work, review, integration and final
  real-Mac verification. No external Fable/Claude review.
- Finish each branch, verify it, then merge it into main. Commit and push are authorized.
- Preserve an `upstream` remote. Periodic upstream changes must be merged with our
  app identity and feature requirements rechecked; no unattended overwrite.
- Browser research and browser tests use the Codex in-app browser only. Do not
  interact with the owner’s personal browser; it is in active use.
- Preserve source attribution and applicable licenses. Aster uses its own app name,
  icon, bundle identity, signing identity and update destination.
- Keep implementation files within 1000 lines and new functions within 30 lines.
  Meaningfully changed oversized files should be made smaller along real boundaries.
- Reuse existing code and framework-free policy helpers. Keep tests separate from source.
- Use existing localization, feature catalog and lifecycle machinery.
- Do not install competing charging controllers or start destructive cleanup while
  researching. Prepare the complete app before requesting the necessary user actions
  for macOS permissions and the transition away from currently active apps.

## Evidence log

Record per-feature research, implementation commits, automated checks, actual UI and
hardware checks, and unresolved failures separately. A feature's status is determined
by evidence, not by an agent saying it is complete.
