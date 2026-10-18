# Open source menu-bar approaches

Research requested by Alejandro on 2026-09-30. Only public source was used.
Aster remains one app; no separate manager runs alongside it.

| Project | Relevant approach | Use in Aster |
| --- | --- | --- |
| [Thaw](https://github.com/thaw-app/Thaw) | Window-bound move events, passive session/host acknowledgements, private null-event barriers, bounded release watchdog | Adapted event routing. The destination-bound press now changes the native frame. Acknowledgements still do not establish correct placement. |
| [SaneBar](https://github.com/sane-apps/SaneBar) | Visible Command-drag through the HID stream: settle pointer, hold press, 10–14 bounded drag steps, release and settle | Adapted for icons whose entire path stays inside one notch-safe screen region. Aster adds refreshed final drag, explicit Command press/release, identity checks, cancellation recovery and physical-layout verification. |
| [Hidden Bar](https://github.com/dwarvesf/hidden) | Simple divider-based hide/reveal | Confirms the basic interaction model; Aster already has adaptive expanding dividers. No Hidden Bar source copied. |

Source revisions inspected:

- Thaw: `8748c72062e3733d3caeb45f04218afa94613ca4`, GPLv3.
- SaneBar: `2311b2379018dd67e4134866b1ce4d599227d457`, MIT.

The MIT notice is included in `Resources/ThirdPartyNotices.txt` and the app
bundle. Existing Ice/Thaw attribution and Aster's GPL license remain.

Aster's visible-gesture tests execute the production transport with an inert
posting endpoint. They verify the event sequence, refreshed release point and
cancellation recovery without sending input. Those tests do not prove that
macOS moved an icon. The separate native acceptance evidence is authoritative.

## Native result on the owner's Mac

The first observer/barrier candidate acknowledged delivery without physical
movement (`menu-thaw-transport-native-report.json`). The later destination-bound
press moved Siri's frame from x=1728 to x=1915, but release returned it to x=1842,
left of Control Center (`menu-clock-interior-runtime.log`). A second independent
release handshake timed out and was removed. Delivery is not placement.

The SaneBar-based transport physically restored Wi-Fi, Now Playing, Battery,
ABC and Claude. Each step passed Aster's real section, window, neighbor and
unmoved-item checks before the next step ran. Docker's unchanged failed step
did not erase those successes. Evidence: `menu-difference-native-runtime.log`
and `menu-difference-settled-inventory.json`.

Siri still lands left of Control Center instead of between Control Center and
Clock. The owner confirmed that a manual Command-drag can keep it on the right;
this is not accepted as an operating-system restriction. Aster's refreshed
interior drop and alternative trailing Control Center anchor both failed native
adjacency verification (`menu-hid-anchor-quarter-third-runtime.log`,
`menu-protected-neighbor-runtime.log`). All ten baseline entries remain saved;
management is off. A follow-up measurement of the owner's manually placed icon
is pending to compare its physical position with the inventory.

The native HID gesture also exposed a stuck modifier: after release, macOS
reported Command held with no mouse button pressed. Aster now sends explicit
Command modifier press/release events and releases both mouse and Command on
cancellation. Native status after the corrected gesture reports Command false
and mouse false. Cancellation between modifier press and mouse press is tested.
This fix is verified independently of the unresolved Siri order.

Current source passes 523 focused and 81,839 full Swift checks, preference
cleanup and eleven installer checks. The installed gesture candidate passes
optimized build, signature verification and packaged self-test. The latest
editor-label change is tested in source and its signed candidate passes self-test;
installation and final GUI acceptance are pending because the Mac locked. The unchanged
battery helper retains inode 36658241 and PID 49955. Fresh authenticated status
shows the saved policy enabled, 80%, charging false, 0 W and no pending recovery
(`battery-menu-continuation-status.json`). This does not close other lifecycle
or display acceptance gates.
