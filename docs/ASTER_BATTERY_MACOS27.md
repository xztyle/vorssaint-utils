# Aster battery control on macOS 27

The owner requires the macOS manual charge setting to stay at **100%**.
Aster must enforce its independently owned rule. The application never writes
`com.apple.smartcharging.topoffprotection` or changes that system setting.

## Current evidence

The legacy helper cannot write its charging key on this M4 Max after the macOS
27.0.1 / firmware update. Its saved 75–80% policy survives, but is not active.
The replacement is installed. After refreshing its existing background
approval, helper PID 24295 connected and restored the saved enabled 75–80%
policy. Its measured hold and discharge qualification passed. The automatic
rule then registered the same owned token with target 80 and drain enabled;
live discharge measured about 25–32 W. The displayed percentage initially
lagged while raw remaining capacity declined, then updated to 95%.

Two GUI-only updates preserved the helper's PID and inode 39283012 and its
healthy lease without another approval. Keep Awake returned on, Indefinite.
The actual macOS charging sheet still shows its manual slider at 100%, with
Optimized Battery Charging off. `pmset -g battlimit` reports only Aster's owned
rule and the matching effective rule, not an Apple manual limit.

The final 80% hold and below-range recharge qualification remain unverified.
A registered policy by itself is never reported as verified charge control.
Evidence: `macos27-native-first-connected-status.json`,
`macos27-native-second-connected-status.json`,
`macos27-native-stable-rule-status.json`, and the two host-install receipts.

## Native owned policy

The resident helper writes one UUID-owned ChargeCtrlPolicy in powerd's charging
policy archive. Its PID owns the lease; macOS releases a dead owner's lease.
A root-only journal stores the token, boot UUID, PID and requested command before
any preferences mutation. A new helper can reclaim only that journaled token.
Another app's token, owner or reason is never changed or removed.

The archive is parsed as bounded property-list objects, without instantiating
archived classes. Unknown root fields and all unrelated records survive edits.
Malformed data, an unexpected owner, active foreign rules or an unterminated
foreign archived rule stop import. The powerd executable must resolve exactly
before SIGHUP. Read-back checks require both the helper-owned and effective
registration rows to match Aster's reason and flags.

A normal charging command uses the configured upper ceiling with drain disabled.
Holding uses a ceiling of 1 with drain disabled; the low ceiling requests a
charging pause, not a discharge target. A discharge command uses the requested
target with drain enabled. A one-time full charge removes only Aster's policy.
These command meanings still require measured qualification on the actual Mac.

## Recovery and sleep

An unchanged healthy rule performs no preference writes or service restarts.
A lost registration retries its existing token, at most once per minute and
three times per ten minutes. Removal failures retain the recovery receipt and
use the same bounded retry window. A helper restart retains qualification only
when the machine, firmware, macOS and native backend fingerprint still match.

Keep Awake validates its macOS power assertions every 30 seconds and reacquires
expired handles after a power-service restart. It preserves the chosen display
sleep setting and does not release unverified old handles. Calibration and
manual discharge pause after helper restarts or sleep; the saved normal policy
can resume automatically.

## Sources

The owned archive format and resident lease approach adapt the MIT-licensed
[Battery compatibility patch](https://github.com/actuallymentor/battery/pull/479),
revision `2124764eef17aaba4b0f1ea97969d79185609029`. Attribution and its license
are included in `Resources/ThirdPartyNotices.txt`. Its original PowerUI-setting
workaround is explicitly excluded from Aster.
