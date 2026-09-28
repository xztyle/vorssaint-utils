// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

// MARK: - Titles, descriptions and permission names

extension AppFeature {
    /// Titles reuse the strings users already see across the app; only names
    /// with no clean existing form live in the hub strings.
    func hubTitle(_ s: Strings, hub: FeatureHubStrings) -> String {
        switch self {
        case .switcher: return s.switcherSection
        case .dockPreview: return s.dockPreviewName
        case .dockClick: return hub.titleDockClick
        case .windowMaximizer: return s.windowMaximizeName
        case .windowLayout: return FeatureStrings.windowLayout(L10n.shared.language).title
        case .autoQuit: return s.autoQuitName
        case .quitWindowProtection: return FeatureStrings.quitProtection(L10n.shared.language).name
        case .scrollInverter: return s.invertMouseScroll
        case .scrollHorizontal: return s.scrollHorizontalName
        case .focusFollowsMouse: return s.focusFollowsMouseName
        case .smoothScroll: return s.smoothScrollName
        case .mouseAcceleration: return s.mouseAccelerationName
        case .mouseNavigation: return hub.titleMouseNavigation
        case .mouseButtonShortcuts: return FeatureStrings.mouseButtons(L10n.shared.language).pageTitle
        case .middleClick: return s.middleClickSection
        case .keyboardDebounce: return s.keyDebounceName
        case .textSnippets: return FeatureStrings.snippets(L10n.shared.language).pageTitle
        case .superKey: return FeatureStrings.superKey(L10n.shared.language).pageTitle
        case .mouseClickDebounce:
            return FeatureStrings.mouseClickDebounce(L10n.shared.language).title
        case .clipboardHistory: return FeatureStrings.clipboard(L10n.shared.language).title
        case .pastePlain: return s.pastePlainName
        case .finderCutPaste: return s.cutPasteName
        case .finderRename: return FeatureStrings.finderRename(L10n.shared.language).hubTitle
        case .shelf: return s.shelfName
        case .urlCleaner: return s.urlCleanerName
        case .diskImageInstaller:
            return FeatureStrings.diskImageInstaller(L10n.shared.language).title
        case .mixer: return s.mixerSection
        case .soundOutputSwitcher: return s.soundOutputSwitcherTitle
        case .audioPriority: return hub.titleAudioPriority
        case .micMute: return s.micMuteName
        case .musicBlock: return hub.titleMusicBlock
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).pageTitle
        case .extraBrightness: return s.extraBrightnessName
        case .batteryCare: return FeatureStrings.batteryCare(L10n.shared.language)[.title]
        case .menuBarOrganizer: return FeatureStrings.menuBarOrganizer(L10n.shared.language).pageTitle
        case .bluetoothSleep: return FeatureStrings.bluetoothSleep(L10n.shared.language).pageTitle
        case .quickLauncher: return s.launcherName
        case .quickToggles: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .colorPicker: return s.colorPickerName
        case .screenOCR: return s.ocrName
        case .screenshot: return FeatureStrings.screenshot(L10n.shared.language).pageTitle
        case .screenRecorder: return FeatureStrings.recorder(L10n.shared.language).pageTitle
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).pageTitle
        case .wallpaper: return FeatureStrings.wallpaper(L10n.shared.language).pageTitle
        case .notchGestures: return FeatureStrings.notchGestures(L10n.shared.language).title
        case .notchTimer: return FeatureStrings.notchActivities(L10n.shared.language).timer
        case .notchAccessories: return FeatureStrings.notchActivities(L10n.shared.language).accessories
        case .notchNotifications: return FeatureStrings.notchNotifications(L10n.shared.language).title
        case .notchLyrics: return FeatureStrings.notchMusicExtras(L10n.shared.language).lyrics
        case .notchQueue: return FeatureStrings.notchMusicExtras(L10n.shared.language).queue
        case .notchLiveEqualizer: return FeatureStrings.notchMusicExtras(L10n.shared.language).liveEqualizer
        case .notchDownloads: return FeatureStrings.notchFiles(L10n.shared.language).downloadsTitle
        case .notchCalendar: return FeatureStrings.notchCalendar(L10n.shared.language).title
        case .notchAgents: return FeatureStrings.notchAgents(L10n.shared.language).title
        case .notch: return FeatureStrings.notch(L10n.shared.language).title
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        case .commandBar: return FeatureStrings.commandBar(L10n.shared.language).pageTitle
        case .cleaningMode: return s.cleaningMenuItem
        case .mediaTools: return s.mediaName
        case .cleaner: return s.cleanerName
        case .uninstaller: return s.uninstallerName
        case .killProcess: return FeatureStrings.killProcess(L10n.shared.language).pageTitle
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).title
        case .homebrew: return s.homebrewName
        case .appUpdates: return FeatureStrings.appUpdates(L10n.shared.language).pageTitle
        case .monitorCPU: return s.monitorShowCPU
        case .monitorGPU: return s.monitorShowGPU
        case .monitorMemory: return s.monitorShowMemory
        case .monitorNetwork: return s.monitorShowNetwork
        case .monitorDisk: return s.diskSection
        case .monitorPower: return s.powerSection
        case .connectedDevices: return FeatureStrings.connectedDevices(L10n.shared.language).title
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).title
        }
    }

    func hubDescription(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .switcher: return hub.descSwitcher
        case .dockPreview: return hub.descDockPreview
        case .dockClick: return hub.descDockClick
        case .windowMaximizer: return hub.descWindowMaximizer
        case .windowLayout: return hub.descWindowLayout
        case .autoQuit: return hub.descAutoQuit
        case .quitWindowProtection: return FeatureStrings.quitProtection(L10n.shared.language).description
        case .scrollInverter: return hub.descScrollInverter
        case .scrollHorizontal: return L10n.shared.s.scrollHorizontalCaption
        case .focusFollowsMouse: return L10n.shared.s.focusFollowsMouseCaption
        case .smoothScroll: return hub.descSmoothScroll
        case .mouseAcceleration: return L10n.shared.s.mouseAccelerationCaption
        case .mouseNavigation: return hub.descMouseNavigation
        case .mouseButtonShortcuts: return FeatureStrings.mouseButtons(L10n.shared.language).hubDescription
        case .middleClick: return hub.descMiddleClick
        case .keyboardDebounce: return hub.descKeyboardDebounce
        case .textSnippets: return FeatureStrings.snippets(L10n.shared.language).hubDescription
        case .superKey: return FeatureStrings.superKey(L10n.shared.language).hubDescription
        case .mouseClickDebounce:
            return FeatureStrings.mouseClickDebounce(L10n.shared.language).caption
        case .clipboardHistory: return hub.descClipboardHistory
        case .pastePlain: return hub.descPastePlain
        case .finderCutPaste: return hub.descFinderCutPaste
        case .finderRename: return FeatureStrings.finderRename(L10n.shared.language).hubDescription
        case .shelf: return hub.descShelf
        case .urlCleaner: return hub.descURLCleaner
        case .diskImageInstaller:
            return FeatureStrings.diskImageInstaller(L10n.shared.language).hubDescription
        case .mixer: return hub.descMixer
        case .soundOutputSwitcher: return hub.descSoundOutputSwitcher
        case .audioPriority: return hub.descAudioPriority
        case .micMute: return hub.descMicMute
        case .musicBlock: return hub.descMusicBlock
        case .keepAwake: return hub.descKeepAwake
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).hubDescription
        case .extraBrightness: return hub.descExtraBrightness
        case .batteryCare: return FeatureStrings.batteryCare(L10n.shared.language)[.description]
        case .menuBarOrganizer: return FeatureStrings.menuBarOrganizer(L10n.shared.language).hubDescription
        case .bluetoothSleep: return FeatureStrings.bluetoothSleep(L10n.shared.language).hubDescription
        case .quickLauncher: return hub.descQuickLauncher
        case .quickToggles: return FeatureStrings.quickToggles(L10n.shared.language).hubDescription
        case .colorPicker: return hub.descColorPicker
        case .screenOCR: return hub.descScreenOCR
        case .screenshot: return FeatureStrings.screenshot(L10n.shared.language).hubDescription
        case .screenRecorder: return FeatureStrings.recorder(L10n.shared.language).hubDescription
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).hubDescription
        case .wallpaper: return FeatureStrings.wallpaper(L10n.shared.language).hubDescription
        case .notchGestures: return FeatureStrings.notchGestures(L10n.shared.language).description
        case .notchTimer: return FeatureStrings.notchActivities(L10n.shared.language).timerDescription
        case .notchAccessories: return FeatureStrings.notchActivities(L10n.shared.language).accessoryDescription
        case .notchNotifications: return FeatureStrings.notchNotifications(L10n.shared.language).description
        case .notchLyrics: return FeatureStrings.notchMusicExtras(L10n.shared.language).lyricsDescription
        case .notchQueue: return FeatureStrings.notchMusicExtras(L10n.shared.language).queueDescription
        case .notchLiveEqualizer: return FeatureStrings.notchMusicExtras(L10n.shared.language).liveEqualizerDescription
        case .notchDownloads: return FeatureStrings.notchFiles(L10n.shared.language).downloadsDescription
        case .notchCalendar: return FeatureStrings.notchCalendar(L10n.shared.language).description
        case .notchAgents: return FeatureStrings.notchAgents(L10n.shared.language).hubDescription
        case .notch: return FeatureStrings.notch(L10n.shared.language).description
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).hubDescription
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).hubDescription
        case .commandBar: return FeatureStrings.commandBar(L10n.shared.language).hubDescription
        case .cleaningMode: return hub.descCleaningMode
        case .mediaTools: return hub.descMediaTools
        case .cleaner:
            let description = hub.descCleaner
            guard WhatsAppDownloadSupport.isEnabled else {
                return description
            }
            return description + " · "
                + FeatureStrings.whatsAppDownloads(L10n.shared.language).hubDescription
        case .uninstaller: return hub.descUninstaller
        case .killProcess: return FeatureStrings.killProcess(L10n.shared.language).hubDescription
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).hubDescription
        case .homebrew: return hub.descHomebrew
        case .appUpdates: return FeatureStrings.appUpdates(L10n.shared.language).hubDescription
        case .monitorCPU: return hub.descMonitorCPU
        case .monitorGPU: return hub.descMonitorGPU
        case .monitorMemory: return hub.descMonitorMemory
        case .monitorNetwork: return hub.descMonitorNetwork
        case .monitorDisk: return hub.descMonitorDisk
        case .monitorPower: return hub.descMonitorPower
        case .connectedDevices: return FeatureStrings.connectedDevices(L10n.shared.language).hubDescription
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).hubDescription
        }
    }
}

extension AppPermission {
    func name(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .accessibility: return hub.permAccessibility
        case .screenRecording: return hub.permScreenRecording
        case .fullDiskAccess: return hub.permFullDisk
        case .filesAndFolders: return hub.permFilesAndFolders
        case .notifications: return hub.permNotifications
        case .automationFinder: return hub.permAutomationFinder
        case .automationTerminal: return hub.permAutomationTerminal
        case .automationPlayback: return FeatureStrings.notchMusicExtras(L10n.shared.language).automationPermission
        case .audioCapture: return hub.permAudioCapture
        case .microphone: return FeatureStrings.recorder(L10n.shared.language).microphonePermissionName
        case .calendar: return FeatureStrings.notchCalendar(L10n.shared.language).title
        case .camera: return FeatureStrings.cameraPreview(L10n.shared.language).permName
        case .appManagement: return FeatureStrings.settingsCategories(L10n.shared.language).appManagement
        }
    }

    func explainer(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .accessibility: return hub.explainAccessibility
        case .screenRecording: return hub.explainScreenRecording
        case .fullDiskAccess: return hub.explainFullDisk
        case .filesAndFolders: return hub.explainFilesAndFolders
        case .notifications: return hub.explainNotifications
        case .automationFinder: return hub.explainAutomationFinder
        case .automationTerminal: return hub.explainAutomationTerminal
        case .automationPlayback: return FeatureStrings.notchMusicExtras(L10n.shared.language).automationExplanation
        case .audioCapture: return hub.explainAudioCapture
        case .microphone:
            return FeatureStrings.recorder(L10n.shared.language).microphonePermissionExplain
        case .calendar: return FeatureStrings.notchCalendar(L10n.shared.language).permission
        case .camera: return FeatureStrings.cameraPreview(L10n.shared.language).permExplain
        case .appManagement: return hub.explainAppManagement
        }
    }
}
