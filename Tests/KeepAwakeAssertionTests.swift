// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation
import IOKit.pwr_mgt

enum KeepAwakeAssertionTests {
    static func run(_ suite: TestSuite) {
        var live: [IOPMAssertionID: KeepAwakeAssertions.Kind] = [:]
        var next: IOPMAssertionID = 1, released: [IOPMAssertionID] = []
        var deny = false
        let assertions = KeepAwakeAssertions(create: { kind in
            guard !deny else { return nil }
            let id = next; next += 1; live[id] = kind; return id
        }, valid: { live[$0] == $1 }, release: { released.append($0); live.removeValue(forKey: $0) })
        assertions.apply(allowDisplaySleep: false)
        suite.expect(live.count == 2 && next == 3, "Keep Awake acquires system and display assertions")
        assertions.apply(allowDisplaySleep: false)
        suite.expect(next == 3, "healthy assertions survive periodic validation")
        live.removeAll() // A powerd restart invalidates both old handles.
        assertions.apply(allowDisplaySleep: false)
        suite.expect(live.count == 2 && next == 5 && released.isEmpty, "power-service restart reacquires both without releasing stale IDs")
        assertions.apply(allowDisplaySleep: true)
        suite.expect(live.count == 1 && live[3] == .system && released == [4], "display sleep releases only Aster's display assertion")
        assertions.clear()
        suite.expect(live.isEmpty && released == [4, 3], "ending Keep Awake releases the current session")
        deny = true; assertions.apply(allowDisplaySleep: false)
        deny = false; assertions.apply(allowDisplaySleep: false)
        suite.expect(live.count == 2, "a denied assertion is retried on the next check")
        live.removeAll(); assertions.clear()
        suite.expect(released == [4, 3], "ending after service failure does not release an unverified handle")
    }
}
