# Aster battery care

Battery care runs in a dedicated signed launch daemon. The Aster window can close
without ending a saved charge policy. Battery care starts unavailable in the
feature catalog and never registers or writes hardware until the user enables
its feature and installs its service. The initial editor values preserve the
owner's previous preferences: 75–80%, 38°C cutoff, 35°C resume and automatic
discharge. The policy itself starts off.

## Before control is available

The first backend accepts exactly `CHTE: ui32/4 bytes` and `CHIE: hex_/1 byte`.
It never writes firmware range keys. The explicit **Test charge control** action
requires AC, a fresh battery reading, 20–90% charge and a cool battery. Stop other
charging controllers first. The test runs charge, inhibit, discharge and charge
stages, each bounded to 90 seconds. Each stage requires three measured power-flow
samples after a ten-second settling period. Every SMC write is read back. The
final step restores the system before saving qualification. Unknown key shapes,
write denial, drift or failed power evidence keep controls unavailable. A system
update invalidates qualification. Apple's own charge limit can prevent a charge
stage; Aster does not change that setting.

Qualification is evidence for those measured transitions on the current machine.
It does not prove sleep, lid, reboot, thermal, complete top-up or calibration
behavior. These require separate actual-Mac acceptance checks.

## Policy and recovery

The lower bound starts charging; the upper bound stops it. The latch survives
helper restart, so entering the range does not cause repeated top-ups. Automatic
discharge stops at the upper bound. Manual discharge can target 10–99%. Adapter
cut stops at the target, thermal trouble, lost readings, unplug, cancellation or
a six-hour deadline. Charge inhibit and adapter cut are never deliberately active
together. A missing or stale sensor restores AC and inhibits charging under an
active policy. Missing signed-current readings cannot qualify discharge.

The battery sample separates physical adapter presence (`connected`, from
`AppleRawExternalConnected` when available) from effective AC availability
(`externalPowerConnected`, from `ExternalConnected`). An intentional adapter cut
can remove effective AC while the cable remains attached. A physical disconnect
still cancels qualification and discharge. A malformed physical-presence reading
fails closed; systems without that reading keep the conservative effective-AC
fallback. Measured current, temperature and freshness guards remain required.

Heat protection stops immediately at the cutoff and resumes only after a full
minute at or below the resume temperature. Resume must be at least two degrees
below cutoff. Temperature means the battery sensor, not CPU temperature.

Top-up saves the exact policy and charges to 100% until unplug or cancel.
Calibration saves the policy and runs 100% → 10% → 100% → one hour of measured
full-charge samples. Thermal protection stays active. Calibration and manual
discharge require deliberate resume after sleep or daemon restart. Top-up also
requires deliberate resume after daemon restart because a missed unplug cannot
be inferred. A 48-hour operation deadline prevents abandoned calibration.

Aster inhibits active charging before acknowledging sleep and reconciles on wake.
This can stop charging below the limit during sleep. It does not prevent lid
sleep or make a firmware persistence guarantee. Shutdown restores AC and clears
inhibit before exit; the durable policy is reconciled when launchd starts the
helper again. A helper upgrade stops control safely and leaves the saved editor
policy available for explicit re-enabling.

A root-only journal records ownership before the first write. Files use descriptor
relative access, exclusive creation, no-follow opens, atomic rename and fsync.
A shared lock prevents development and production helpers controlling together.
On corruption or failed restoration, the daemon keeps retrying and retains its
registration. App removal refuses to proceed until restoration is confirmed.
The explicit **Return to macOS** disables all Aster policy and schedules, restores
AC first, clears inhibit second, and verifies both keys. It leaves native macOS
charge preferences alone. The screen shows measured state separately from the
requested action; restoring keys is not a claim that macOS must start charging.

## Schedules

Schedules have stable IDs, a named time zone, date/time, action, target and repeat
rule: once, daily, weekdays, weekly, every two weeks or monthly. Monthly tasks
skip months without that calendar day. A nonexistent DST time runs at the next
valid local time; a repeated time runs only at its first occurrence. A named time
zone is retained when the Mac changes zones. Exact same-time tasks sort by stable
UUID; the first exclusive operation wins, and a conflicting operation is logged
as skipped. A scheduled return to macOS pauses policy until another scheduled
limit/action; the explicit Return button disables the schedule service itself.

Missed tasks skip by default. Opt-in missed tasks can run once at the next
opportunity within six hours. Only the most recent occurrence per task is eligible.
Occurrence claims and resulting state are committed before hardware writes, so
restart cannot duplicate an already claimed action. If wall time moves backward,
no past occurrence runs again. Policy/schedules are included in settings backup;
privileged ownership, qualification, calibration state and event history are not.
Restoring preferences never silently authorizes hardware control on another Mac.

## Diagnostics and acceptance

The helper's `--selftest` and `--probe` never write hardware. The latter prints the
actual sample, key eligibility, machine/OS fingerprint and detected competitors.
Use the signed app executable for authenticated diagnostics:

```sh
Aster.app/Contents/MacOS/Aster --battery-status
Aster.app/Contents/MacOS/Aster --battery-register
Aster.app/Contents/MacOS/Aster --battery-request '{"version":1,"kind":"qualify"}'
Aster.app/Contents/MacOS/Aster --battery-request '{"version":1,"kind":"returnToSystem"}'
```

Register/request require Battery care availability. Registration can require the
owner's approval in System Settings. Requests are closed intents; there is no
arbitrary key writer, executable path or shell argument channel. Both client and
server pin the other party's identifier and the current signing certificate.
Ad-hoc signatures fail closed. `--battery-register` does not bypass macOS approval.

After replacing an installed app, its normal Battery care refresh compares the
saved helper hash with the bundled helper hash. An unknown saved hash, including
registration through `--battery-register`, also requires an upgrade. The app first
requests Return to macOS and verifies that ownership and recovery are both clear.
Only then does it unregister the old service. It waits for macOS to finish that
operation, then registers the bundled service on the next main-queue turn.
Failed restoration retains registration. macOS may require approval again.
Diagnostic status/register commands alone do not perform this upgrade; open the
Battery care panel or run the normal app with Battery care enabled. The status
field `helperBuild` is the protocol version, not the bundled executable hash.

Tests in `BatteryCareTests.swift` and `BatteryControllerTests.swift` exercise the
pure policy and an injected transport/state store. Run `./build.sh --test-suite=battery-care`, the optimized app build, app selftest and helper
selftest. Simulated evidence is deliberately separate from actual hardware.

The actual-Mac gate must record: all four qualification transitions and restore;
75–80 range; safe low heat threshold cutoff/resume; manual/automatic discharge and
unplug; full top-up/unplug; a complete calibration cycle/cancellation; schedule
and missed wake runs; app quit/relaunch; daemon crash/relaunch; lid sleep below and
above limit; complete restart; and final Return to macOS with observed power flow.
Closed-lid external-display adapter cut needs its own check. Missing hardware
checks mean the AlDente replacement is not yet accepted.

## Attribution

The implementation is original GPL-3.0-or-later Aster code. Community observations
of raw CHTE/CHIE values were cross-checked against the read-only host probe and the
MIT-licensed `actuallymentor/battery` and GPL-3.0 Stasis projects. No GPL-2-only
batt implementation was copied. AppleSMC charging keys are private and unsupported;
capability and measured behavior, not OS version or README claims, govern control.
