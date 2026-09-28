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

### Duplicate-results UI limitation

On Mac16,5 / macOS 26.6.2, the generated fixture scanned four files and reached
the duplicate-results state through the Duplicates tab and action. Both an
accessibility-tree read and a screenshot request then crashed
`SkyComputerUseService`, while Aster remained running. An earlier reproduction,
`SkyComputerUseService-2026-09-28-090040.ips`, records `Array.remove(at:)` followed
by repeated `compactMap` frames in the tool process. TextEdit remained accessible
through the same control tool immediately afterward.

Commit `3dfa0c8` narrows the disabled state to the removal checkbox and adds
file-specific keeper labels. It passed 88 storage-inspection checks, 246
repository checks, the optimized build, strict signature verification and
runtime selftest. An exact live retry still crashed the control tool when the
duplicate results appeared. The change improves the review controls, but it is
not claimed to fix the tool crash. No duplicate-results UI acceptance pass is
claimed, including choosing a keeper or removing a reviewed duplicate through
that screen. The automated keeper/removal-policy checks passed independently.

The same tool-only crash also occurred after a reviewed Trash action from the
working Storage list: the selected generated `Large fixture.bin` disappeared from
its original location, then the tool crashed while reading the recovery result;
Aster stayed running. Recovery via Finder was not yet verified at that point.
Duplicate and recovery result groups now use explicit accessibility containment,
a bounded semantic grouping change whose live result still needs verification.
The fixture observer records future service outcomes and cannot reconstruct an
earlier process's in-memory Trash receipt. Five new receipt checks verify scope
filtering, keeper identity, returned Trash locations, and omission of private
content; the combined storage-inspection and repository run passes 339 checks.
