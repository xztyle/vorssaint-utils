// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors
import Foundation
import Security

let arguments = CommandLine.arguments
precondition(arguments.count == 4)
let text = AppCodeIdentity.requirement(identifier: arguments[1])
var requirement: SecRequirement?
precondition(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
var target: SecStaticCode?
let url = URL(fileURLWithPath: arguments[2])
precondition(SecStaticCodeCreateWithPath(url as CFURL, [], &target) == errSecSuccess)
let accepted = SecStaticCodeCheckValidity(target!, [], requirement) == errSecSuccess
let expected = arguments[3] == "accept"
precondition(accepted == expected, "Unexpected signature decision: \(text)")
print("PASS \(arguments[3]): \(url.lastPathComponent)")
