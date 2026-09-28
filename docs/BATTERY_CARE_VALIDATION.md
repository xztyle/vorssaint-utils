# Battery care validation, 2026-09-28

This is implementation evidence, not acceptance of the AlDente replacement.
The primary agent owns hardware activation and the remaining actual-Mac gate.

## Automated checks

The optimized app build passed, including compilation of the separate protected
battery daemon, helper selftest, app assembly and deep signature verification with
**Aster Local Signing**. `build/Aster --selftest` returned `SELFTEST OK`.
No daemon was installed or started by the battery implementation worker.

The final scoped test compilation used three workers and passed:

```text
battery-care: OK (121 checks)
preferences: OK (97 checks)
repository: OK (246 checks)
features: OK (1103 checks)
settings: OK (366 checks)
localization: OK (7346 checks)
uninstaller: OK (48 checks)
TESTS OK (9327 checks)
```

Battery tests cover range and heat hysteresis; fresh/missing sensor data; signed
current decoding; manual/automatic discharge bounds and timeout; top-up unplug;
calibration transitions, observed hold time, cancellation and restart pause;
missed-task freshness, duplicate claims, stable ties, DST gap/fold and biweekly
behavior; invalid protocol and policy data; exact CHTE byte order, denied writes,
readback mismatch and controller drift; failed restore with durable retry;
journal failure before writes; measured qualification stages with injected
readings; malformed RPC replies; and exactly-once XPC failure/timeout completion.
All 15 locale tables and settings-backup inclusion/exclusion pass.

`git diff --check`, `zsh -n build.sh` and `zsh -n Tools/uninstall.sh` passed.
Removal was not executed against the real app. Its source now blocks deletion
until hardware/helper restoration succeeds, preserves upstream Vorssaint,
checks the menu recovery baseline, and moves Aster's bundle to Trash.

## Read-only host evidence

The built helper's `--probe` observed on the actual host:

- Mac model: `Mac16,5`.
- macOS: `26.6.2`, build `25G83`.
- Battery: 80%, 34.65°C, external power connected, `IsCharging=false`, 0 W.
- CHTE/CHIE metadata/read shapes eligible; both controls read as system/charge allowed.
- No known competing process detected by the bounded process inspection.
- The firmware value was independently read at `IODeviceTree:/chosen`:
  `system-firmware-version=mBoot-18000.161.10`.

The first built diagnostic used the wrong registry node for the firmware string
and reported `unknown`. The final source fixes that path so a firmware change
also invalidates old qualification. Key eligibility is not write capability.

## Rebuild and hardware gate still required

After the successful optimized bundle, scoped tests found and fixed the
battery-only Energy page visibility gate and locale-aware decimal formatting.
The final source also includes the correct firmware node and stricter removal
preflight. **These final small changes require an incremental app/helper rebuild.**
The primary agent agreed to own that rebuild and its app selftest.

No SMC write, root helper registration, daemon start, qualification, actual
charge/discharge transition, thermal cutoff/resume, full top-up, complete
calibration, sleep/lid/reboot behavior, or real uninstall has been claimed here.
Those remain the explicit actual-Mac gate in `BATTERY_CARE.md` and the product
contract. The interface refuses control until bounded qualification passes.

## Diagnostic entry points for the primary agent

Successful pre-final-fix signed bundle: `build/stage/Aster.app` in this feature
worktree. Use the rebuilt signed app executable, not an ad-hoc standalone copy:

```sh
Aster.app/Contents/MacOS/Aster --battery-status
Aster.app/Contents/MacOS/Aster --battery-register
Aster.app/Contents/MacOS/Aster --battery-request '{"version":1,"kind":"qualify"}'
Aster.app/Contents/MacOS/Aster --battery-request '{"version":1,"kind":"returnToSystem"}'
```

Register and request entry points require the Battery care feature availability
preference and stable signing. Registration can require macOS approval. The
helper's `--probe` and `--selftest` are read-only. Neither starts its daemon loop.

## Root integration checks

The final source was rebuilt, packaged with the stable local certificate, and
passed the packaged app selftest. The app was installed at `/Applications/Aster.app`.
macOS initially reported `.notFound` before first registration; authorization now
attempts registration for that state, matching the existing fan-service behavior.
macOS can throw `Operation not permitted` after registering a service pending
approval. Both entry points now inspect the resulting approval state instead of
misreporting that expected pending state as an unavailable helper.

The owner approved Aster under App Background Activity. Authenticated status then
reached the running root daemon, reporting no ownership, recovery or competing
controller and a disabled policy. The subsequent bounded qualification tried its
initial charging stage. The Mac stayed at 80%, not charging, with 0 W battery
power; after 90 seconds the helper restored system control and reported failed
verification. It retained neither hardware ownership nor a pending recovery.

System Settings independently showed the native charge limit set to 80% and
“Charged to 80% Limit”. That setting was not changed. A temporary change to 100%,
followed by restoring 80%, awaits the owner's approval before retrying. This run
proves service startup and the timed failure/restoration path, not successful
charge, hold or discharge qualification. Battery policy remains off.

The registration fixes passed an optimized build and packaged selftest. The
battery suite still passes 121 checks. The physical acceptance list above remains
open; no successful calibration, sleep or reboot claim follows from these checks.

## Native-limit retry and adapter-presence correction

The owner later approved a temporary native limit of 100%. The primary agent ran
qualification on the same Mac. Stage 0 measured charging at 43.763032 W and passed;
stage 1 measured 0 W and passed. Verification failed five seconds after beginning
the discharge stage, before its ten-second settling period. The helper restored
system control with no remaining ownership or recovery. The primary agent then
restored the native 80% limit and confirmed it in System Settings.

Source inspection found that every qualification tick treated `ExternalConnected`
as cable presence. That also describes effective AC availability, which can be
removed by the intentional CHIE adapter cut. This explains the early failure, but
the failed run did not retain raw registry telemetry at that exact transition.
A subsequent read-only registry sample exposed both `AppleRawExternalConnected`
and `ExternalConnected` as true. The correction uses the raw attachment reading
for cable presence and preserves effective AC as separate diagnostic telemetry.
An explicit raw false still cancels control; malformed raw data fails freshness;
absence of the raw key keeps the conservative legacy behavior.

The controller regression fixture now decodes realistic registry samples with
raw attachment true and effective AC false during adapter cut. All four modeled
qualification stages pass. Separate real-unplug simulations abort qualification
and manual discharge and restore both controls. These are injected tests, not a
claim that discharge or unplug has passed on the host.

Inspection also confirmed that CLI registration leaves the saved helper hash
unset. The old app upgrade guard skipped that case. The corrected guard follows
the existing restore, unregister and register sequence for an unknown hash too.
Tests execute the production upgrade method with isolated doubles and verify
that failed restoration, remaining ownership or pending recovery cannot
unregister the service.

The correction passed `battery-care` (144 checks) and `repository` (246 checks),
390 checks total, with two build workers. The primary agent owns the combined
optimized app/helper build, packaged selftest, helper replacement, and the next
hardware retry with raw telemetry logging. The updated helper has not yet been
tested against actual adapter cut or physical unplug. The remaining hardware
acceptance list is unchanged.

## Helper replacement launch failure

The combined optimized app/helper build containing the adapter correction passed
its packaged selftest. After installation and service replacement, the first
helper launch failed at 10:10:21 with a code-signing spawn-constraint mismatch
(`c[5]p[1]m[1]e[0]`). Later launch attempts reported a missing program even though
the bundled executable existed at the correct path. The initial code-signing
failure is the relevant evidence; no helper charging request ran afterward.

A read-only Security framework query found that the default lightweight code
requirement of each locally signed helper contains only its own code hash. The
old and new helpers have different hashes but the same certificate-based
designated requirement. A cached previous spawn hash is therefore a supported
hypothesis, not a proven reading of the saved service constraint.

Source inspection also found a definite registration race: synchronous
`unregister()` does not wait for the old process to exit. The SDK documents that
re-registration is safe after the asynchronous completion. The replacement path
now waits for that completion and dispatches registration to the main queue,
matching [Apple DTS guidance](https://developer.apple.com/forums/thread/783539).
The restore/ownership/recovery checks still run before unregistering. Failed
unregister completion leaves the replacement unregistered.

The SDK call typecheck passed, and scoped tests passed 149 battery checks plus
246 repository checks, 395 total. They verify that neither restoration alone nor
an unfinished unregister can register the replacement, and that completion errors
stop registration. The primary agent owns the combined rebuild and safe recovery
through the previous verified helper. Recovery and a successful replacement launch
remain pending; no security setting or launch constraint was weakened.
