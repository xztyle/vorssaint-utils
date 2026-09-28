# Features search navigation

On macOS 26.6.2, the installed integration build `1b7637c` stopped responding
when Screenshot was selected from Settings search. Screenshot and Screen
Recording were unavailable in the feature catalog. Search therefore opened the
Features hub, not the Screenshot settings form. Granting Screen Recording
permission does not change feature availability.

The preserved process sample is dominated by SwiftUI lazy-stack estimates and
row placement inside the Features hub. The page nested seven feature cards in a
lazy stack inside an eager stack. A search first jumped to the group, then began
two animated row jumps only 80 milliseconds apart; each animation lasted 300
milliseconds.

The candidate uses a regular stack for those bounded cards. It expands the
requested group, then makes one immediate row jump with inherited animation
disabled. The brief highlight still fades afterward. A newer request invalidates
an older queued jump.

The regression fixture runs the actual navigation methods with inert scrolling
and deterministic scheduling. The old navigation fails the recorded-jump checks.
The candidate passes them, and the real Features view completes hidden layout at
772- and 1,050-point window widths. The fixture never shows a window, starts a
feature service or changes production preferences.

The hidden fixture did not reproduce the live hang and cannot expose the hidden
window's accessibility children. A visible test of the integrated app remains
required: open Features directly, then search for a disabled Screenshot feature,
confirm the target is visible and controls remain responsive, and repeat with a
collapsed group and a newer search request. Root owns this test and the final
optimized build and packaged self-test.
