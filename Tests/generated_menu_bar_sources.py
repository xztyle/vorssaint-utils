# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Compile menu transactions against inert test endpoints."""


def generate_menu_bar_sources(write, declaration):
    operations = "Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerOperations.swift"
    mover = "Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarItemMover.swift"
    write("MenuBarActivation.swift", "import Foundation\n"
          + "extension MenuBarActivationTests {\nfinal class Host: Fixture {\n"
          + declaration(operations, "    func activateItem(")
          + declaration(operations, "    func restoreActivationVisibility(")
          + "}\n}\n")
    write("MenuBarPointerRecovery.swift", "import AppKit\n"
          + "extension MenuBarPointerRecoveryTests {\nfinal class Host: Fixture {\n"
          + declaration(mover, "    private func dragWithCursor(").replace("    private func", "    func", 1)
          + "}\n}\n")
