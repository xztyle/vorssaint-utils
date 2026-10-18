#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint and Aster contributors

"""Compile battery service and editor methods against inert test endpoints."""

SERVICE = "Sources/Vorssaint/Services/BatteryCare/BatteryCareService.swift"
SETTINGS = "Sources/Vorssaint/UI/Settings/BatteryCareSettings.swift"


def service_methods(declaration, prefixes):
    return "".join(declaration(SERVICE, prefix)
                   .replace("private ", "", 1)
                   .replace("UserDefaults.standard", "defaults")
                   .replace("DispatchQueue.main.async", "self.mainQueue.async")
                   .replace("AppFeature.batteryCare.isAvailable", "featureEnabled")
                   .replace("BatterySensor.sample()", "sampleBattery()")
                   for prefix in prefixes)


def generate_battery_service_sources(write, declaration):
    write("BatteryHelperUpgradeContract.swift", "import Foundation\n"
          + "extension BatteryHelperUpgradeTests.Service {\n"
          + service_methods(declaration, ["    private func upgradeIfNeeded(",
              "    func recordAuthorizedBuild(", "    func recordPendingPolicyRestoration(",
              "    func syncWithPreferences(", "    var restoringPolicy:",
              "    private func failed(", "    private func markUnavailable(", "    private func received("])
          + "}\nextension BatteryHelperUpgradeTests.RemovalFixture {\n"
          + declaration(SERVICE, "    static func detachForRemoval(")
          + "}\nextension BatteryHelperUpgradeTests.PolicyEditor {\n"
          + "".join(declaration(SETTINGS, prefix).replace("private ", "", 1) for prefix in [
              "    private var statusTitle:", "    private var canConfigure:",
              "    private func receiveSnapshot(", "    private func savePolicy("])
          + "}\n")
