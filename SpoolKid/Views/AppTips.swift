//
//  AppTips.swift
//  SpoolKid
//
//  Purpose: TipKit tip definitions for contextual app guidance.
//  These tips appear only after the welcome guide is completed to help
//  users discover features as they navigate the app.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import Foundation
import TipKit

// MARK: - Shared event donated when the welcome guide finishes

struct WelcomeGuideCompleted {
    static let event = Tips.Event(id: "welcomeGuideCompleted")
}

// MARK: - Tips

struct WriteTagTip: Tip {
    var title: Text {
        Text("Write Tag")
    }
    var message: Text? {
        Text("Put filament data on a blank tag, typed in or taken from a spool in your library.")
    }
    var image: Image? {
        Image(systemName: "pencil.and.list.clipboard")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

struct ScanTagTip: Tip {
    var title: Text {
        Text("Scan Tag")
    }
    var message: Text? {
        Text("Hold your iPhone near a spool's tag to see what it holds and what you can do next.")
    }
    var image: Image? {
        Image(systemName: "wave.3.right")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// The Tags bar's Scan Label icon.
struct ScanLabelTip: Tip {
    var title: Text {
        Text("Scan Label")
    }
    var message: Text? {
        Text("Point the camera at a spool's label or QR code to find or add its filament.")
    }
    var image: Image? {
        Image(systemName: "camera.viewfinder")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

struct SpoolmanManageTip: Tip {
    var title: Text {
        Text("Your Library")
    }
    var message: Text? {
        Text("Tap the title to change how spools are grouped, and a group's header to open its page.")
    }
    var image: Image? {
        Image(systemName: "server.rack")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// The Library bar's first icon.
struct LocationsTip: Tip {
    var title: Text {
        Text("Locations")
    }
    var message: Text? {
        Text("Where your spools live: shelves, dry boxes, printers.")
    }
    var image: Image? {
        Image(systemName: "mappin.and.ellipse")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// The Library bar's second icon.
struct EmptySpoolsTip: Tip {
    var title: Text {
        Text("Empty Spools")
    }
    var message: Text? {
        Text("Empty-spool weights, so a scale reading becomes the filament left.")
    }
    var image: Image? {
        Image(systemName: "circle.circle")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// The Library bar's third icon.
struct WeighSpoolsTip: Tip {
    var title: Text {
        Text("Weigh Spools")
    }
    var message: Text? {
        Text("Weigh spools one after another and update what's left.")
    }
    var image: Image? {
        Image(systemName: "scalemass")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// The Library bar's prominent action.
struct AddSpoolTip: Tip {
    var title: Text {
        Text("Add Spool")
    }
    var message: Text? {
        Text("Add a new spool to your library.")
    }
    var image: Image? {
        Image(systemName: "plus")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// Weigh Spools' Finish icon.
struct WeighFinishTip: Tip {
    var title: Text {
        Text("Finish")
    }
    var message: Text? {
        Text("End the session. A reading still on screen is saved first.")
    }
    var image: Image? {
        Image(systemName: "checkmark")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// Weigh Spools' Choose icon.
struct WeighChooseTip: Tip {
    var title: Text {
        Text("Choose")
    }
    var message: Text? {
        Text("Pick the next spool to weigh from your library.")
    }
    var image: Image? {
        Image(systemName: "list.bullet")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// Weigh Spools' Scan icon.
struct WeighScanTip: Tip {
    var title: Text {
        Text("Scan")
    }
    var message: Text? {
        Text("Scan the next spool's tag to weigh it.")
    }
    var image: Image? {
        Image(systemName: "wave.3.right")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

struct AboutTip: Tip {
    var title: Text {
        Text("Settings")
    }
    var message: Text? {
        Text("Tag writing, deleting, your Bluetooth scale, release notes and the welcome guide.")
    }
    var image: Image? {
        Image(systemName: "gearshape")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

struct HubInfoTip: Tip {
    var title: Text {
        Text("What These Buttons Do")
    }
    var message: Text? {
        Text("Tap ⓘ next to Spool or Filament to see what each button does.")
    }
    var image: Image? {
        Image(systemName: "info.circle")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

/// Points out the (i) on the spool form, Weigh and Home, once. The Scan Hub
/// has its own `HubInfoTip`.
struct InfoButtonTip: Tip {
    var title: Text {
        Text("What ⓘ Means")
    }
    var message: Text? {
        Text("Tap ⓘ beside a section for how it works.")
    }
    var image: Image? {
        Image(systemName: "info.circle")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}
