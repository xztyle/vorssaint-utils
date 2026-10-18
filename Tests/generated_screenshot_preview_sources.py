# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint and Aster contributors

"""Compile production preview interaction handlers against controlled inputs."""


def generate_screenshot_preview_sources(write, declaration):
    preview = "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift"
    write("ScreenshotPreviewHover.swift", "import Foundation\n"
          + "extension ScreenshotPreviewHoverTests {\nfinal class Controller: State {\n"
          + "".join(declaration(preview, prefix).replace("private func", "func", 1)
                    for prefix in ["    private func hoverChanged(", "    private func scheduleAutoDismiss(",
                                   "    private func perform("])
          + "}\nstruct Preview {\nlet embedded: Bool\nlet hoverChanged: (Bool) -> Void\n"
          + declaration("Sources/Vorssaint/UI/Screenshot/ScreenshotQuickPreviewView.swift",
                        "    private func previewHoverChanged(").replace("private func", "func", 1)
          + "}\n}\n")
    write("ScreenshotPreviewTransfer.swift", "import Foundation\nimport AppKit\n"
          + "extension ScreenshotPreviewTransferTests {\nfinal class Surface: State {\n"
          + declaration("Sources/Vorssaint/Services/QuickTools/ScreenshotDragTransfer.swift",
                        "        func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint,")
          + "}\n}\n")
    write("ScreenshotPreviewKeyboard.swift", "import AppKit\nimport Carbon.HIToolbox\n"
          + "extension ScreenshotPreviewKeyboardTests {\nfinal class Controller: State {\n"
          + "".join(declaration(preview, prefix).replace("private func", "func", 1)
                    .replace("_ event: NSEvent", "_ event: AppKit.NSEvent")
                    for prefix in ["    private func installKeyMonitor(",
                                   "    private func ownsPreviewKey(",
                                   "    private func handlePreviewKey(",
                                   "    private func handlePreviewCommand(",
                                   "    private func isCloseCommand("])
          + "}\n}\n")


def generate_notch_capture_keyboard_sources(write, declaration, preview, selection):
    write("NotchCaptureKeyboard.swift", notch_capture_preview_source(declaration, preview)
          + notch_capture_selection_source(declaration, selection))


def notch_capture_preview_source(declaration, preview):
    return ("import Foundation\nimport Carbon.HIToolbox\n\nextension NotchCaptureKeyboardContract {\n"
          + "final class NotchService {\nstatic var shared = NotchService()\n"
          + "var presentationWindow: NSPanel? = NSPanel()\nvar acceptsSystemFeedback = true\n"
          + "var expanded = true\nvar selected = NotchModule.captures\nvar showingAppPanel = false\n"
          + "var showingSections = false\nvar selectedMetric: Int?\nvar captureControls: Int?\n"
          + "var captureID: UUID?\nvar captureContent: Bool? = true\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchService.swift", "    func isCaptureVisible(")
          + "}\nfinal class Preview {\n"
          + declaration(preview, "    enum Action {")
          + "var keyMonitor: Any?\nvar closed = false\nvar shownInNotch = true\nlet presentationID = UUID()\n"
          + "var dragging = false\nvar swiping = false\n"
          + "var actions: [Action] = []\nfunc perform(_ action: Action) { actions.append(action) }\n"
          + "func close() { closed = true }\nfunc attach(_ panel: NSPanel) { installKeyMonitor(for: panel) }\n"
          + "".join(declaration(preview, prefix) for prefix in [
              "    private func installKeyMonitor(", "    private func ownsPreviewKey(",
              "    private func handlePreviewKey(", "    private func handlePreviewCommand(",
              "    private func isCloseCommand("])
          + "}\n")


def notch_capture_selection_source(declaration, selection):
    return ("final class Selection {\n"
          + "final class Options { var controlsInNotch = true; var hasFocusedControl = false }\n"
          + "enum Outcome { case cancelled }\nvar screenCaptureOptions: Options? = Options()\n"
          + "var keyMonitor: Any?\nvar globalKeyMonitor: Any?\nvar spaceIsDown = false\n"
          + "var acceptsWindowClick = true\nvar loupeAcceptsKeyboardActions = false\n"
          + "var actions: [String] = []\nvar draggingPanel: ScreenshotOverlayPanel?\n"
          + 'func finish(_ outcome: Outcome) { actions.append("cancel") }\n'
          + 'func captureFullDisplayUnderMouse() { actions.append("fullDisplay") }\n'
          + "func panelUnderMouse() -> ScreenshotOverlayPanel? { draggingPanel }\n"
          + 'func repeatLastRegion() { actions.append("repeat") }\n'
          + "func selectCaptureTool(for event: NSEvent) -> Bool { false }\n"
          + "static func isScrollingCaptureKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isLoupeKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isCopyColorKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isNudgeKey(_ event: NSEvent) -> Bool { false }\n"
          + "func toggleScrollingCapture() {}\nfunc toggleLoupe() {}\nfunc copyLoupeColor() {}\n"
          + "func nudgePointer(keyCode: Int, fast: Bool) {}\nfunc attach() { installKeyMonitor() }\n"
          + declaration(selection, "    private static func isRepeatRegionKey(")
          + declaration(selection, "    private static func matchesShortcutKey(")
          + declaration(selection, "    private func installKeyMonitor()")
          + "}\n}\n")
