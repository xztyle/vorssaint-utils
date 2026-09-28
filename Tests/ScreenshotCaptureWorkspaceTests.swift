// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production collection, with window effects replaced by explicit test surfaces.
enum ScreenshotCaptureWorkspaceTests {
    enum ScreenshotSelectionController {
        struct Capture { let image: CGImage; let scale: CGFloat; let anchorRect: CGRect }
    }
    final class ScreenshotQuickPreviewController {
        enum Action: Hashable { case edit, pin, copy, save, saveAndCopy, discard }
        var fixtureWindowTitle: String?
        var isInteracting = false
        var interactionEnded: (() -> Void)?
        let visibleCapacity = 6
        let protectedWindowIDs: Set<CGWindowID> = [101]
        let displayID: CGDirectDisplayID = 1
        let action: (Action) -> Set<Action>
        let onClose: () -> Void
        var closed = false
        init(capture: ScreenshotSelectionController.Capture, strings: ScreenshotFeatureStrings,
             defaultAction: ScreenshotDefaultAction, preferences: UserDefaults, dragDirectory: URL?,
             action: @escaping (Action) -> Set<Action>,
             share: @escaping (ScreenshotShareDuration, @escaping (ScreenshotShareRecord?) -> Void) -> Void,
             shareFile: @escaping () -> URL?, onClose: @escaping () -> Void) {
            self.action = action; self.onClose = onClose
        }
        func close() { guard !closed else { return }; closed = true; onClose() }
        func show(inNotch: Bool) {}
        func setStackIndex(_ index: Int, count: Int) {}
        func bringForward() {}
    }
    final class ScreenshotEditorController {
        let protectedWindowIDs: Set<CGWindowID> = [202]
        var onCommit: ((ScreenshotRenderer.Export) -> Void)?
        var onClose: (() -> Void)?
        let capture: ScreenshotSelectionController.Capture
        let flattened: Bool
        init(capture: ScreenshotSelectionController.Capture, preferences: UserDefaults,
             fixtureDirectory: URL?, flattened: Bool) { self.capture = capture; self.flattened = flattened }
        func show() {}
        func close() { onClose?() }
        func bringForward() {}
    }

    static func run(_ suite: TestSuite) {
        guard let image = ScreenshotContinuityTests.baseImage() else { return }
        let capture = ScreenshotSelectionController.Capture(image: image, scale: 2, anchorRect: .zero)
        let workspace = Workspace(fixtureDirectory: URL(fileURLWithPath: "/tmp"))
        let firstID = workspace.add(capture)
        let secondID = workspace.add(capture)
        workspace.openEditor(id: firstID)
        suite.expect(workspace.items.count == 2 && workspace.items[1].preview != nil,
                     "editing one capture preserves the other capture and both IDs")
        suite.expect(workspace.protectedWindowIDs == [101] && workspace.editorWindowIDs == [202],
                     "all preview windows are protected separately from ordinary editor windows")
        workspace.items[0].editor?.close()
        suite.expect(workspace.items[0].revision == 0 && workspace.items[0].capture.image === image,
                     "cancel restores the prior committed capture without a history edit")
        commitAndReopen(workspace, firstID: firstID, secondID: secondID, suite: suite)
        workspace.closeAll()
        suite.expect(workspace.items.isEmpty, "feature teardown closes all previews and active editors")
    }

    private static func commitAndReopen(_ workspace: Workspace, firstID: UUID, secondID: UUID, suite: TestSuite) {
        workspace.openEditor(id: firstID)
        guard let item = workspace.items.first, let editor = item.editor,
              let crop = item.capture.image.cropping(to: CGRect(x: 0, y: 0, width: 50, height: 40)) else { return }
        var committedID: UUID?
        workspace.committed = { id, _, _ in committedID = id }
        editor.onCommit?(.init(image: crop, scale: 2))
        editor.close()
        suite.expect(committedID == firstID && item.revision == 1 && item.capture.image.width == 50,
                     "Done commits edited pixels under the original history ID")
        var outputWidth = 0
        workspace.output = { _, capture, action in outputWidth = capture.image.width; return [action] }
        _ = item.preview?.action(.copy)
        suite.expect(outputWidth == 50, "corner output uses committed pixels, not the original capture")
        workspace.openEditor(id: firstID)
        suite.expect(item.editor?.capture.image.width == 50 && item.editor?.flattened == true,
                     "reopening starts with committed pixels without applying the old backdrop twice")
        suite.expect(workspace.add(item.capture, id: secondID) == secondID && workspace.items.count == 2,
                     "restoring a visible history ID does not create another preview")
    }
}
