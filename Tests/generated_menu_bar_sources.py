# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Compile menu transactions against inert test endpoints."""


def generate_menu_bar_sources(write, declaration):
    write("MenuBarNativeSection.swift", "import AppKit\n"
          + "extension MenuBarNativeSectionTests {\nfinal class Host: Fixture {\n"
          + declaration("Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarNativeBackend.swift", "    func move(")
          + declaration("Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarNativeBackend.swift", "    func prepareForStartup()")
          + declaration("Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarNativeBackend.swift", "    func loadSavedMembership(")
          + "}\n}\n")
    operations = "Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerOperations.swift"
    mover = "Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarItemMover.swift"
    write("MenuBarBestEffortRestoration.swift", "import AppKit\nimport os\n"
          + "extension MenuBarBestEffortRestorationTests {\nfinal class Host: Fixture {\n"
          + declaration(operations, "    private func applyLayoutSteps(").replace("    private func", "    func", 1)
          + declaration(operations, "    private func restorationMayContinue(")
          + "}\n}\n")
    write("MenuBarActivation.swift", "import Foundation\n"
          + "extension MenuBarActivationTests {\nfinal class Host: Fixture {\n"
          + declaration(operations, "    func activateItem(")
          + declaration(operations, "    func restoreActivationVisibility(")
          + "}\n}\n")
    write("MenuBarPointerRecovery.swift", "import AppKit\nimport os\n"
          + "extension MenuBarPointerRecoveryTests {\nfinal class Host: Fixture {\n"
          + declaration(mover, "    private func dragWithCursor(").replace("    private func", "    func", 1)
          + "}\nfinal class MoveHost: MoveFixture {\n"
          + declaration(mover, "    private func postCommandDrag(").replace("    private func", "    func", 1)
          + declaration(mover, "    private func postRoutedDrag(")
          + declaration(mover, "    private func postDirectMove(")
          + declaration(mover, "    private func currentDestination(")
          + declaration(mover, "    private func sendMoveEvent(").replace("    private func", "    func", 1)
          + "}\n}\n")
    relay = "Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarItemEventRelay.swift"
    write("MenuBarTapLifecycle.swift", "import AppKit\n"
          + "extension MenuBarTapLifecycleTests {\nfinal class Host: Fixture {\n"
          + "".join(declaration(relay, prefix).replace("    private func", "    func", 1)
                    for prefix in ["    func start()", "    private func installMouseObservers(", "    private func install(", "    func close()"])
          + "}\n}\n")
