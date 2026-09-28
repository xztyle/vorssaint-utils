// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

extension SwitcherModelFeatureTests {
    static func scrollNavigationChecks(_ suite: TestSuite) {
        func event(_ vertical: Int32, horizontal: Int32 = 0, continuous: Bool = false,
                   phase: CGScrollPhase? = nil, momentum: Int64 = 0, scrollCount: Int64 = 0,
                   timestamp: CGEventTimestamp = 1_000_000_000) -> CGEvent {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line,
                                wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            event.setIntegerValueField(.scrollWheelEventScrollCount, value: scrollCount)
            event.timestamp = timestamp
            return event
        }
        var navigation = SwitcherScrollNavigation()
        suite.expect(navigation.selectionDelta(for: event(-3)) == 1,
                     "a wheel sample selects the next app regardless of acceleration")
        suite.expect(navigation.selectionDelta(for: event(3)) == -1,
                     "reverse scrolling selects the previous app")
        suite.expect(navigation.selectionDelta(for: event(0)) == 0,
                     "zero scrolling preserves the selection")
        suite.expect(navigation.selectionDelta(for: event(1, horizontal: -3)) == 1,
                     "horizontal scrolling uses the dominant axis")
        let step = Int32(SwitcherScrollNavigation.gestureStep)
        suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began)) == 0,
                     "a gesture below the threshold preserves the selection")
        suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .changed)) == 1,
                     "continuous scrolling accumulates to one step")
        suite.expect(navigation.selectionDelta(for: event(-10 * step, continuous: true, momentum: 1)) == 0,
                     "trackpad momentum does not change the selection")
        suite.expect(navigation.selectionDelta(for: event(0, horizontal: step, continuous: true, phase: .began)) == -1,
                     "a horizontal trackpad gesture changes the selection")
        _ = navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began))
        suite.expect(navigation.selectionDelta(for: event(step / 2, continuous: true, phase: .changed)) == 0
                     && navigation.selectionDelta(for: event(step / 2, continuous: true, phase: .changed)) == -1,
                     "reversing direction resets accumulated movement")
        _ = navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began))
        suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began)) == 0,
                     "a new gesture does not inherit the previous remainder")
        for phase in [CGScrollPhase.ended, .cancelled] {
            for terminalDelta in [Int32(0), -step] {
                navigation = SwitcherScrollNavigation()
                _ = navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began))
                suite.expect(navigation.selectionDelta(for: event(terminalDelta, continuous: true, phase: phase)) == 0,
                             "terminal Core Graphics phase \(phase) with delta \(terminalDelta) preserves selection")
                suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .changed)) == 0,
                             "terminal Core Graphics phase \(phase) clears the previous remainder")
                suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .changed)) == 1,
                             "scrolling after Core Graphics phase \(phase) accumulates from zero")
            }
        }
        _ = navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began))
        suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .changed,
                                                        timestamp: 2_000_000_000)) == 0,
                     "a pause resets the trackpad remainder")
        suite.expect(navigation.selectionDelta(for: event(-10 * step, continuous: true, phase: .changed)) == 1,
                     "a large trackpad sample does not skip multiple apps")
        let synthetic = event(-10 * step, continuous: true)
        synthetic.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
        suite.expect(navigation.selectionDelta(for: synthetic) == 0,
                     "a remaining smooth-scroll frame does not change the selection")

        func wheel(line: Int64 = 0, fixed: Double, point: Int64 = 0, continuous: Bool = false,
                   horizontal: Bool = false, timestamp: CGEventTimestamp = 1_000_000_000) -> CGEvent {
            let sample = event(0, continuous: continuous, timestamp: timestamp)
            sample.setIntegerValueField(horizontal ? .scrollWheelEventDeltaAxis2 : .scrollWheelEventDeltaAxis1,
                                        value: line)
            sample.setDoubleValueField(horizontal ? .scrollWheelEventFixedPtDeltaAxis2 : .scrollWheelEventFixedPtDeltaAxis1,
                                       value: fixed)
            sample.setIntegerValueField(horizontal ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventPointDeltaAxis1,
                                        value: point)
            return sample
        }
        for continuous in [false, true] {
            for horizontal in [false, true] {
                for inverted in [false, true] {
                    navigation = SwitcherScrollNavigation()
                    let fractions = [-0.25, -0.5, -0.5, -0.75]
                    let expected = [0, 0, inverted ? -1 : 1, inverted ? -1 : 1]
                    for index in fractions.indices {
                        let sample = wheel(fixed: fractions[index], continuous: continuous, horizontal: horizontal,
                                           timestamp: 1_000_000_000 + UInt64(index) * 500_000_000)
                        ScrollWheelSupport.applyDirection(to: sample, isContinuous: continuous,
                            invertVertical: inverted, invertHorizontal: inverted, horizontalModifier: nil)
                        suite.expect(navigation.selectionDelta(for: sample) == expected[index],
                            "fractional wheel movement retains its remainder across pauses and inversion: continuous=\(continuous), horizontal=\(horizontal), inverted=\(inverted), sample=\(index)")
                    }
                }
                navigation = SwitcherScrollNavigation()
                suite.expect(navigation.selectionDelta(for: wheel(line: -1, fixed: 0, continuous: continuous,
                                                                  horizontal: horizontal)) == 1,
                             "a whole-line wheel notch advances once in either representation")
                navigation = SwitcherScrollNavigation()
                _ = navigation.selectionDelta(for: wheel(fixed: -0.75, continuous: continuous, horizontal: horizontal))
                suite.expect(navigation.selectionDelta(for: wheel(fixed: 0.5, continuous: continuous, horizontal: horizontal)) == 0
                    && navigation.selectionDelta(for: wheel(fixed: 0.5, continuous: continuous, horizontal: horizontal)) == -1,
                    "reversing a fractional wheel resets the previous direction's remainder")
            }
        }
        navigation = SwitcherScrollNavigation()
        suite.expect(navigation.selectionDelta(for: wheel(fixed: 0, point: -5, continuous: true)) == 0
            && navigation.selectionDelta(for: wheel(fixed: 0, point: -5, continuous: true,
                                                    timestamp: 2_000_000_000)) == 1,
            "a slow point-only continuous wheel notch advances once without the trackpad threshold")
        navigation = SwitcherScrollNavigation()
        _ = navigation.selectionDelta(for: wheel(fixed: -0.75))
        suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began)) == 0
            && navigation.selectionDelta(for: wheel(fixed: -0.25)) == 0,
            "switching between wheel lines and trackpad points clears the other device's remainder")
        navigation = SwitcherScrollNavigation()
        _ = navigation.selectionDelta(for: event(-step / 2, continuous: true, phase: .began, scrollCount: 1))
        _ = navigation.selectionDelta(for: event(0, continuous: true, phase: .ended, scrollCount: 1))
        suite.expect(navigation.selectionDelta(for: event(-step / 2, continuous: true, scrollCount: 1)) == 0,
                     "a phaseless trackpad transition is not treated as a mouse notch")

        func code(_ path: String) -> String {
            ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
        let switcher = code("Sources/Vorssaint/Services/Switcher/AppSwitcher.swift")
        suite.expect(switcher.contains("CGEventType.scrollWheel.rawValue") && switcher.contains("case .scrollWheel:"),
                     "the switcher subscribes to and handles scroll-wheel events")
        for path in ["Sources/Vorssaint/Services/SmoothScrollService.swift",
                     "Sources/Vorssaint/Services/MouseButtons/MouseButtonShortcutService.swift"] {
            suite.expect(code(path).contains("AppSwitcher.shared.scrollNavigationActive"),
                         "\(path) yields scrolling to the open switcher")
        }
        suite.expect(!code("Sources/Vorssaint/Services/ScrollInverter.swift").contains("AppSwitcher.shared.scrollNavigationActive"),
                     "scroll direction still transforms wheel events before they reach the open switcher")
    }
}
