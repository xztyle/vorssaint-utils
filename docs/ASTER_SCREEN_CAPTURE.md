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
External output controls are disabled or return no result in this mode. Save
acts as Done, writing only the fixture's committed image. Editor and corner drag
still use the real renderer. A fixture control window has named Preview and Edit
buttons for each capture. Preview window titles include the full UUID and revision.
The same control window contains a rich text input. It imports a dragged PNG through
AppKit, verifies a new image attachment, and writes a received PNG and JSON receipt
with acceptance, dimensions, hash and advertised types. It reads only the drag
pasteboard; the receiver's general copy, cut and paste commands are disabled.
Fixture windows share a level so named controls can select each preview or editor.
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
- Actual capture permissions, multi-display/Spaces, drag receivers and hardware
  behavior on Mac16,5 macOS 26.6.2 remain the root's acceptance gate.
