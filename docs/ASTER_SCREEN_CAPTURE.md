# Aster capture continuity

Captured images appear at the bottom left of their capture display by default.
A saved position preference still wins. New previews leave the receiving app's
keyboard focus alone. Clicking a preview makes its keyboard commands available.

Click the image or Edit to annotate it. Done returns the rendered result to the
same capture in the corner. Copy, Save and Save As commit a successful editor
output too. Closing or discarding uncommitted work restores the previous result.
Reopening a committed edit starts with the flattened image. The existing backdrop
and watermark are not applied twice.

Preview lifetime is 30 seconds by default, with 15 seconds, 60 seconds and
Until closed also available in capture settings. Hover, editing, dragging and
sharing pause dismissal. Returning from an interaction starts a fresh interval.
Copy, Save, Pin and a completed or cancelled drag leave the capture available.
Escape and Command-W dismiss the focused preview. Return, E and Command-E edit;
Command-C copies, Command-S saves, and Delete discards the focused capture.

Up to six previews share a 256 MiB image budget. The newest single image and
active interactions can exceed the budget so they are not lost. Older inactive previews
leave first and remain in History. An editor, hovered preview or active drag is
not evicted. A smaller display can keep fewer previews visible. Previews stack
within the visible display area and join Spaces, including full-screen apps.
Automatic placement uses a corner while several previews share a display.
All preview windows remain excluded from subsequent captures.

History keeps the same capture UUID when an edit replaces its pixels. Image and
thumbnail files use fresh revision names. The serial write queue commits the new
index before cleaning old files, and a failed index write retains the previous
entry. Recording files are unchanged. Drag offers PNG, TIFF and a PNG file URL;
all represent the committed export. Provider file requests retain the encoded
bytes, and native drag files remain in a private app temporary folder. Cleanup
removes only this app's transfers older than 48 hours at the next start.

## Isolated UI acceptance

The explicit argument `--capture-fixture=/private/tmp/aster-capture-UNIQUE`
launches three generated image previews before normal startup. It never creates
the application delegate, capture services, hotkeys, permission prompts, history
service, or a general clipboard reader/writer. A unique preferences suite supplies
editor preferences and is removed on normal termination. The provided temporary
root receives the initial images, each committed edit and `manifest.json`.
For a GUI launch that cannot pass arguments, a separately signed temporary app
copy may put the same absolute private temporary path in its Info.plist key
`AsterCaptureFixtureDirectory`. The argument takes precedence when both are set.
The key is absent from production builds. The fixture rejects relative paths,
the shared temporary root and paths outside a private temporary child directory.
External output controls are disabled or return no result in this mode. Save
acts as Done, writing only the fixture's committed image. Editor and corner drag
still use the real renderer. A fixture control window has named Preview and Edit
buttons for each capture. Preview window titles include the full UUID and revision.
The same control window contains a rich text input. It imports a dragged PNG through
AppKit, verifies a new image attachment, and writes a received PNG and JSON receipt
with acceptance, dimensions, hash and advertised types. It reads only the drag
pasteboard; the receiver's general copy, cut and paste commands are disabled.
Fixture windows share a level so named controls can select each preview or editor.
The fixture Window menu provides Command-0 for the receiver and Command-1 through
Command-3 for each capture (its open editor takes priority over its preview).
`ui-geometry.json` records visible window and receiver-input bounds in AppKit screen
points whenever a window moves, resizes or changes focus/visibility. Root owns GUI
interaction; a worker may launch this generated-only mode with explicit approval.

1. Inspect the early entry in `main.swift` and `ScreenshotCaptureFixture.swift`.
2. Launch a new app instance with a new private temporary root.
3. Confirm three previews appear. Edit the middle one, add a visible mark and
   crop, then choose Done. Confirm its changed corner thumbnail.
4. Drag that thumbnail into the isolated image receiver. Compare the receiver's
   PNG with the latest same-ID revision in the fixture root.
5. Reopen and cancel; confirm the committed image survives. Drag-cancel, close
   one preview, and confirm the other captures remain.

## Evidence

Implementation branch: `feature/screen-capture`.

- Optimized app build: passed, signed with Aster Local Signing.
- Automated screenshot, capture-storage, recorder and recording suites: passed
  after final preview and drag refinements (1,849 checks). The last screenshot
  run adds the large-image retention case and passes 817 checks.
- Runtime selftest: passed.
- The local synced staging folder gained unsigned filesystem metadata after
  packaging. A copy outside the synced folder passes deep, strict signature
  verification with the same Aster Local Signing identity.
- Tests use the production preview collection with explicit window doubles,
  controlled timers, real renderer/image-provider representations and private
  history files. They do not establish actual window, permission or drop behavior.
- Root's first fixture UI check edited Capture 3 with a red arrow and used Done.
  The corner returned and the same capture UUID gained revision 1. Selection of
  unnamed corner windows made the drag check ambiguous; the controls and receiver
  were added for that acceptance check.
- The first receiver launch exposed an AppKit designated-initializer crash. The
  receiver now owns a complete text system and uses the designated initializer.
  A regression constructs the actual class and imports an image attachment using
  a private pasteboard. The screenshot suite passes 822 checks, including new/existing
  temporary-root checks and rejection of the shared temporary root. A generated-only fixture launch stayed alive and wrote all
  three initial manifest entries after this repair.
- Real Mac UI acceptance on Mac16,5 / macOS 26.6.2: Capture 3 was edited with
  a visible arrow, Done returned it to the corner, and Command-3 selected its
  revision-1 preview. A real native drag inserted a PNG attachment into the
  fixture's AppKit rich text input. Receipt
  `received-323B197E-76D0-4C61-9121-4BF1A7D18E90.json` reports acceptance,
  `public.png`, one attachment and 1800 × 1000 pixels. Its PNG SHA-256 exactly
  matches capture `992037AF-4621-4C84-8C6B-D7B5B0D7ACE3` revision 1:
  `ccc9fe30b8d7b560aecf9df561a6ecd5a736d5113ffb35c1f7938cf886acd06f`.
- Capture 2's discard dialog was cancelled and the editor remained open. Undo
  then Done returned an image with no arrow visible. An ImageIO comparison of
  original and edited PNGs found 141 of 1,800,000 pixels changed by only one
  8-bit level in one channel; dimensions are identical. The renderer uses a
  DeviceRGB context, so this is consistent with color-conversion rounding.
  The exported image is not claimed to be pixel-identical to the original.
- All three previews remained available, including Capture 3's earlier edit.
  A second actual drag inserted Capture 2 revision 1 as the receiver's second
  image attachment; its saved PNG exactly matches that committed revision.
  That interaction was intended as a cancellation check but completed a drop,
  so actual drag cancellation remains unverified.
- The isolated fixture proves editing and native preview-to-rich-text drag with
  generated images. It does not request capture permission or record the screen.

## Production capture evidence — 2026-09-28

Root exercised installed integration build `1b7637c`, whose capture source matches
`cf1f9f2`, on Mac16,5 / macOS 26.6.2. This preceded the navigation candidate
`bdc9adb`; the observations below do not validate that navigation fix.

- The user approved macOS's direct screen-capture prompt. Capture Now then captured
  a region of a generated local heading in the Codex in-app browser. The resulting
  image was 1490 × 260 pixels at 2× scale, and its preview appeared at the bottom left.
- Root changed Preview Lifetime from 30 seconds to Until closed for this test.
  That test preference is still in effect unless root subsequently restores it.
- Edit opened the Screenshot editor through the Window menu. Root drew a red
  arrow. Done returned the committed image, including the arrow, to the preview.
- Copy from the preview followed by Command-V in TextEdit inserted the image into
  a generated RTFD duplicate document, “Untitled (PasteTarget copy)”. A screenshot
  visually confirms the captured image and red arrow. No byte comparison of that
  TextEdit attachment is claimed.
- A native drag began and created a 47,010-byte PNG under the app's temporary
  `CaptureTransfers` directory. Its SHA-256 is
  `3917a710c65b6014d5727ead253ec53e6dd19935ce99aa376ff713fc0d042062`.
  Automated cross-app drag attempts did not deliver an image to the in-app
  browser or TextEdit. The browser's explicit Paste action reported its virtual
  clipboard empty. These observations do not establish whether the native
  cross-app drop succeeds or fails.
- Root asked the user to drag the prepared preview manually into the generated
  TextEdit document on the right half of the screen. That result is pending.
  The app remained alive as PID 73188, with no crash observed during these steps.

Production capture, edit-to-preview continuity and external TextEdit copy/paste
are now observed. Manual external drag acceptance, actual drag cancellation,
multi-display and Spaces behavior remain unverified. The earlier generated-image
fixture drag receipts remain separate evidence and do not stand in for this
pending production cross-app drop.

## Bare corner card and left swipe — 2026-09-28

The floating preview now shows only the captured image at rest. Its panel is
transparent, borderless and shadowless. Close, Edit, Copy, Save and More appear
over the image while hovered. A leftward gesture moves the actual card with the
pointer. Releasing a sufficient horizontal swipe animates it completely past
the left display edge; a short or cancelled swipe returns it. The distance
adapts when the gesture starts close to that edge. Reduce Motion skips the
animation. Other drag directions keep the native image transfer, and a display
to the left remains a valid drag destination.

The branch also tracks a two-finger left swipe through AppKit's fluid swipe
progress. It moves the same card across the display, follows the system's
scroll-direction preference and returns on cancellation. Mouse drags still
start native image transfers in the other directions. [CleanShot's feature
list](https://cleanshot.com/features) calls out swipe control for its Quick
Access Overlay. This adds the trackpad interaction to the
existing pointer gesture; real trackpad feel remains a live acceptance check.

The `feature/screen-capture` branch passes 834 screenshot checks after the
trackpad and adaptive pointer swipe changes. A distinct signed generated-image
fixture showed a 320 × 178 point image-only card. The computer-control tool
could not route a reliable drag to this transient panel. Hands-on confirmation
of the card's swipe motion, hover controls and image-capable text input is still
pending; no visual swipe success is claimed from the automated check.
The full branch gate currently has 14 failures in notch-rail and switcher-scroll
visibility checks. The same 13 switcher failures also occur on current main
while the screenshot fixture is open. These are not counted as a passing full
gate; they need a clean rerun after fixture interaction ends.
