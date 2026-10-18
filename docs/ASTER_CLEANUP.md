# Storage and security

The existing Cleaner now includes a **Storage and security** view. Choose local
folders, scan their contents, inspect the folder totals, and filter by file size
or last modification date. Results begin unselected. The existing cache cleaner
and uninstaller remain separate tools.

## Review and recovery

- Review lists every selected path before moving anything to Trash. It does not
  empty Trash. Trashed files still occupy space, so displayed sizes are estimates,
  not a promise of immediate free space. APFS clones and hard links can share data.
- Duplicate detection groups by length, streams SHA-256, then compares every byte.
  Hard-link aliases are counted once. Choose a keeper before selecting other copies;
  removal refuses a group with no surviving, unchanged keeper. Only the selection
  checkbox is disabled until a keeper is chosen; file details and Reveal remain
  usable. Keeper accessibility labels include the filename and expose the full
  path as a hint, using the existing localized action text.
- Before each move, Aster checks scope, file and ancestor identities, size,
  nanosecond modification time, ownership and local eligibility again. A changed
  or unavailable item must be scanned again. It never retries with elevated access.
- The current session retains the actual returned Trash URL and any path-specific
  failure. **After restarting Aster, open Trash in Finder, select the item, and use
  Put Back.** Aster shows this instruction even without session receipts. It does
  not provide a permanent-delete or empty-Trash action for these results.

## Scope and limits

Storage inspection accepts up to eight explicitly selected folders. It excludes
whole-home/system roots, symbolic links, known provider locations, ubiquitous and
dataless files, packages, credential locations, shared/app-group directories,
foreign-owned files, and files or directories with group/world-write or shared ACL
grants. It stays on each selected root's device. Exclusions and denied paths are
visible; excluded content is never inferred to be removable.

Enumeration is limited to 50,000 files, 10,000 directories and 120 seconds, with
at most 200 issue details. Directory entries are read incrementally. Hashing and
byte verification share a 32 GiB read budget and 120-second deadline. File reads
use 1 MiB chunks and a no-follow descriptor walk; metadata is checked before and
after reading. Worker threads suppress dataless materialization. Cancellation,
limits, errors and exclusions produce partial coverage rather than an empty pass.
The UI reveals results in pages and permits at most 500 selected paths per review.

Scans, selections and paths are kept only in memory. Nothing scans personal folders
on startup or on a schedule. Turning off Cleaner cancels work and clears results.
Settings backup includes only the generic large-file and age thresholds.

## Security evidence

Selected applications receive bounded, read-only `codesign` verification and
`spctl` Gatekeeper assessment. Signing identity, signature state, quarantine
attribute and Gatekeeper result are distinct evidence. An unsigned application
is not a malware finding. Unsupported, denied and timed-out checks remain unknown.

Application inspection is capped at 200 apps and 120 seconds. Individual signature
and Gatekeeper calls have an eight-second maximum, reduced by the remaining total
budget; signing metadata has a four-second maximum. Startup inspection reads only
the stated user/system LaunchAgents and LaunchDaemons folders, with a 200-file
limit per folder, a 30-second total deadline and a 64 KiB plist bound. It reports
the configured executable; it does not modify startup entries. macOS manages
XProtect. Aster also links to Software Update and Login Items settings.

## Optional local malware engine

Aster runs an **external ClamAV command-line installation**. It does not bundle an
engine or a signature database. The setup button explicitly installs the Homebrew
`clamav` formula after confirmation; an existing native macOS installation is also
detected. There is no service, daemon, root helper, background monitor, upload,
automatic quarantine or malware deletion.

Definitions live in the current Aster bundle's private Application Support
`MalwareScan/Definitions` directory. Update runs FreshClam once with an explicit
configuration. Every update and scan verifies the main, daily and bytecode
databases with `sigtool` and the engine's trusted signing certificates. Missing,
unverified, future-dated or older-than-seven-day daily definitions block scanning.
TLS and definition signature checks are never disabled. Diagnostic output is
retained for display, including failed updates.

Only files admitted by the selected-folder scan enter malware scanning. Aster
validates each file and makes private local snapshots; the engine receives these
copies, never writable originals. Copies are removed on completion or failure.
After a process crash, the next explicit scan also discards marked private copies
from an interrupted run. Unmarked directories are preserved. No scan copy or
private result enters settings backup.

The limit is 2,000 files, 256 MiB per file and 2 GiB total, with a 120-second copy
budget and a five-minute scanner deadline. Archives have a 512 MiB expansion,
1,000-member and depth-12 limit. Scanner output is capped at 1 MiB. All engine
arguments are separate process arguments; paths never become shell commands.
Official databases only, no symlink following, encrypted/limit alerts and a
definition-age check are explicit scanner options. Exit 0 means no matches within
the stated scope; exit 1 supplies findings; exit 2, cancellation or timeout means
incomplete coverage. Limits and encrypted-content alerts are incomplete coverage,
not malware findings. A result never proves that a file or Mac is safe.

ClamAV is distributed separately under GPLv2; Aster retains its GPL-3.0-or-later
source license and upstream attribution. Official references:

- [One-shot scanning](https://docs.clamav.net/manual/Usage/Scanning.html)
- [Signature management](https://docs.clamav.net/manual/Usage/SignatureManagement.html)
- [Native packages](https://docs.clamav.net/manual/Installing/Packages.html)
- [ClamAV license](https://github.com/Cisco-Talos/clamav/blob/main/COPYING.txt)

## Verification

`./build.sh --test-suite=storage-inspection` exercises generated local fixtures,
real Trash movement and restore, duplicate keeper enforcement, replaced parents,
changed files, hard-link exclusion, missing/unknown metadata, cancellation,
budgets, all 15 locales, settings validation, fixture isolation, private-snapshot
recovery and signature/engine result distinctions. It never scans personal files.

The optional `ASTER_CLAMAV_TEST_DATABASE` environment variable points this test at
an already prepared official database. The test copies it into private temporary
storage, verifies it, performs one real update, scans harmless EICAR and benign
fixtures, and verifies that both originals remain. This path is never used by the
shipping app. Target-Mac ClamAV 1.5.4 produced the expected one match in two files,
with complete coverage and a successful verified update.

`--cleanup-fixture=<empty private directory>` opens the actual view with generated
files and no ordinary app delegate, background features or permission prompts.
An arbitrary existing nonempty directory is refused. A matching preparation
marker permits reuse without rewriting fixtures, including files already moved
out of the fixture. `action-state.json` records generated-scope files, selections,
duplicate groups and keeper choices, returned Trash URLs for those generated
originals, and malware outcome counts. The observer runs only in fixture mode,
after the service publishes a change. It reads no file contents, excludes outside
paths and diagnostic/finding text, and does not infer that a UI interaction passed.
This route disables personal folder/app pickers, engine installation and System Settings launch. Root UI
acceptance is recorded separately in `ASTER_VALIDATION.md`; CLI checks do not
claim that UI interactions, Finder Put Back, cloud providers or external-volume
Trash behavior were exercised on the owner's data.

### Live Mac verification

On Mac16,5 / macOS 26.6.2, duplicate and recovery result groups with separate
SwiftUI GroupBox labels crashed the computer-control tool's accessibility reader;
Aster remained running. Moving the titles inside explicitly contained groups
made both results readable in the actual app.

The generated-file UI test selected Original.txt as keeper, selected only
Duplicate.txt for removal, reviewed both exact paths, and moved the extra copy to
Trash. The recovery panel revealed the real returned Trash path. Finder's Put
Back restored Duplicate.txt to its original folder; its SHA-256 still matched
Original.txt. The earlier 8 MiB Large fixture.bin was also restored through Finder.
No personal file was scanned or removed.

The age filter at 180 days showed the 400-day-old Keep.txt. The large-file filter
showed no fixture at 100 MB and only Large fixture.bin at 1 MB. The actual malware
UI detected the harmless EICAR fixture with verified ClamAV definitions and
reported partial coverage because excluded entries remained outside the scan.

Startup inspection repeated the tool-reader crash with labeled result groups.
Its titles now use the same readable arrangement. The signed generated-only UI
fixture displayed both startup entries without a reader crash: the missing
executable reported Unknown, and `/usr/bin/true` reported Signature valid.
The fixture receipt writer also now normalizes paths lexically: Foundation's file
URL normalization resolved the existing /private/tmp scope to /tmp but left a
trashed, absent original unchanged, incorrectly omitting its receipt. The new
missing-original regression fails before the fix and passes with it. The signed
fixture entry also uses canonical filesystem paths, so `/tmp` and `/private/tmp`
name the same prepared folder. The actual UI recorded a generated duplicate's
original and returned Trash paths; Finder Put Back restored the file with the
same SHA-256 as its keeper. All 97 storage-inspection checks pass. Combined
integration `b0da423` passed its optimized build, packaged selftest, full
70,815-check suite, and preference cleanup. Its copied bundle passed deep strict
signature verification but remains uninstalled while the battery helper's
protected journal is checked. External-volume and cloud-provider behavior has
not been exercised on the owner's data.

The installed Aster uninstaller also selected a generated-only 12 KB app under
Applications. Its review listed only that app, then Move to Trash reported Done
and the original path was absent. Finder Trash showed the exact item. Finder's
Put Back command was disabled for this dot-prefixed test bundle; Finder Move Here
restored it to Applications instead. The restored generated marker matched its
original SHA-256. The temporary app was then removed from Applications. This
proves the reversible Trash path for a generated app, but Put Back for a normal
visible app and the remaining user-app cleanup cases still need a live check.

## Continuing a duplicate review after Trash

When a group has three or more identical copies, moving one extra copy to Trash
now keeps the remaining keeper and extra copies in the review. The group keeps
its identity and keeper choice. It disappears only when one copy remains. If
the keeper becomes unavailable, Aster clears that choice and requires a new
explicit keeper before any further removal. Generated three-copy checks cover
these cases; the focused storage suite passes 101 checks. The real three-copy
UI flow still needs a live generated-file check.

## Malware result scope

The malware report now clears when a different folder is chosen, a folder is
rescanned, a new malware scan starts, or a scanned file is successfully moved
to Trash. This prevents an old finding or clean result from appearing to
describe a changed file set. The focused storage suite passed 101 checks, and
the optimized signed build and app selftest passed. Live UI behavior with a
changed generated folder remains to be checked.

On first opening the malware page, Aster now checks the installed ClamAV tools
and private definitions automatically. After a successful Homebrew installation,
it refreshes the version and verification state without another button press.
The manual Definitions control remains available for later updates or retries.

## Storage-map candidate — 2026-09-29

Storage browsing now uses an allocated-space bubble map and a linked list. Circle
area, not diameter, is proportional to measured local bytes. Up to sixteen circles
are packed without overlap; additional items are represented by an Other items
circle and remain accessible in the paginated list. Zero-size items stay in the
list. Excluded content is not assigned a guessed size. Nested selected roots do
not count the same scanned contents twice.

A folder click drills into its direct children. Back/Forward, clickable breadcrumbs
and a double-click on the empty map area navigate the scanned hierarchy. Hovering
a circle or row highlights its counterpart. File circles reuse Quick Look, Finder
reveal and the existing explicit selection/review/Trash flow. Browsing does not
select folders or scan additional paths. Large/old filters keep their whole-scope
search when chosen; they do not infer descendant folder sizes from matching files.

The map sits beside compact rows when the available width permits, and above the
list in a narrow window. Navigation uses the shared Liquid Glass backdrop; data
circles use the native accent and secondary colors. Reduced motion removes the
hover transition, and increased contrast strengthens circle outlines.

The reference for these interactions is MacPaw's current
[Space Lens results guide](https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-results).
Its text was read; the remote screenshot could not be displayed by the web tool.
The original app is absent and the Mac is locked. This is a built candidate, not
a claim of visual acceptance or of inspecting the original application's runtime.
Generated-file and geometry checks cover area ratios, bounds, non-overlap,
50,000-item grouping, size overflow, nested roots, filters and navigation history.

The final candidate release build, packaged selftest and deep, strict signature
verification passed. The complete suite passed 81,485 checks plus preference
cleanup. Generated staging metadata had to be cleared before strict signature
verification. The installed app still precedes this storage-map candidate;
native layout and interaction checks remain pending while the Mac is locked.

## Native Space Lens comparison — 2026-09-30

CleanMyMac 5.7.0 was restored and its Space Lens scanned only generated sample
files. Its map/list, double-click folder drill-down, Back and review controls were
inspected. Selecting a sample in Documents produced a cloud-deletion warning;
Change Selection cancelled it and no file was removed. CleanMyMac was then quit.

Aster intentionally skipped that cloud-root sample. A local temporary copy
produced measured 13.1 MB and 4.2 MB folder circles, a 1 MB file and the small
README. Folder-circle navigation and Back worked. Selecting the 1 MB file updated
the estimated selected size, and Review showed exactly that path. Cancel closed
the sheet without deletion. The final installed refinement uses short scope names,
shows size/age controls only for their selected filter, and puts technical limits
in help text. Its release build passed; that final presentation awaits a native
recheck. The full functional suite passes 81,523 checks plus preference cleanup.

## Current installed cleanup recheck — 2026-09-30

The installed app scanned a new private, generated five-file folder. Its short
scope label and filter-specific controls were present. The allocated-space map
opened Archive and Back returned to Sample. The duplicate view found three equal
copies, required an explicit keeper, reviewed only Copy One.txt for removal, and
moved that copy to Trash. The remaining two-copy group retained Original.txt as
keeper and still allowed selecting Copy Two.txt. Finder Put Back restored Copy
One.txt; hashes of all five generated files remained unchanged. Evidence:
`cleanup-current-fixture.json`, `cleanup-current-storage-map.png`,
`cleanup-current-three-copy-after-trash.txt`, `cleanup-current-recovery-report.json`.

The shipping malware page detected ClamAV 1.5.4 and blocked scanning while its
private definitions were missing. Updating downloaded official definitions and
the separate signature check accepted them. FreshClam's retained output included
NULL X509 store messages despite its successful database tests/update; Aster did
not suppress those diagnostics. The local generated-file scan reported four
files, zero skipped, no matches within the stated scope. Choosing a different
generated folder cleared that report and disabled scanning until the new folder
is scanned. Evidence: `cleanup-current-malware-result.txt` and
`cleanup-current-malware-changed-scope.txt`.

The recovery link is now also included directly in duplicate results using the
existing shared recovery view. This final presentation change awaits installation
and a native recheck. The preceding full gate passed 81,804 checks, preference
cleanup and eleven installer checks.

A normal visible generated app under Applications also passed review and Trash
movement. Finder's Put Back remained disabled, so this is not a Put Back pass.
Finder's Move Here restored it to Applications instead, with every bundle file's
SHA-256 unchanged. The never-launched test app was then moved back into the private
generated fixture folder, removing it from Applications. See
`uninstaller-current-visible-trash-report.json` and
`uninstaller-current-visible-recovery-report.json`.

The completion messages now say bytes were removed or moved to Trash, rather than
claiming immediate recovered disk space. Uninstaller recovery instructions name
moving the item back to its original folder, with Put Back used when available.
All fifteen locales have the new messages. These presentation changes passed the
optimized build and are included in the final candidate.

The final candidate is installed. Its release build, strict signatures, packaged
selftest, 81,805-check full suite, preference cleanup and eleven installer checks
passed. A native duplicate removal then displayed the exact returned Trash link
directly in duplicate results. That link selected Copy One.txt in Finder Trash,
and Put Back restored it. All five original fixture files retained their hashes.
See `cleanup-final-duplicate-recovery-link.txt` and
`cleanup-final-recovery-report.json`. No personal file was scanned or removed.

## macOS 27 definition recovery — 2026-10-02

The native ClamAV 1.5.4 integration exposed a patched daily.cld without its
separate signature. Scanning refused it, as required. Updates now download into
a private staging directory and reuse only verified complete CVD files and their
signatures. An unverifiable CLD triggers a fresh full daily CVD download. All
three databases must pass signature and freshness checks before publication.
Failed downloads, verification and cancellation leave the previous database
unchanged. A failed directory promotion restores the previous directory.

On macOS 27.0.1 the actual backend recovered from that generated database
fixture, updated from the official mirror, and scanned two generated originals:
one EICAR match, one benign file, complete coverage, originals retained. The
focused production/recovery suite passes 688 checks without optional live
network tests. This code still needs installation and a native UI acceptance
pass; these are backend results. No personal file was scanned or removed.
