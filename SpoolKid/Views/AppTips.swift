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
// Licensed under the MIT License.
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
        Text("Write an NFC Tag")
    }
    var message: Text? {
        Text("Create a filament NFC tag manually by entering material details, or pull data directly from your Spoolman library.")
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
        Text("Scan Existing Tags")
    }
    var message: Text? {
        Text("Hold your phone near an NFC filament tag to read its data. You can then edit and re-write the tag if needed.")
    }
    var image: Image? {
        Image(systemName: "wave.3.right")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

struct SpoolmanManageTip: Tip {
    var title: Text {
        Text("Manage Your Filament Library")
    }
    var message: Text? {
        Text("Browse and manage your spools, filaments, and vendors synced from your Spoolman server.")
    }
    var image: Image? {
        Image(systemName: "server.rack")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}

struct AboutTip: Tip {
    var title: Text {
        Text("About & Preferences")
    }
    var message: Text? {
        Text("View app info, access preferences in iOS Settings, or restart the welcome guide.")
    }
    var image: Image? {
        Image(systemName: "info.circle")
    }
    var rules: [Tips.Rule] {
        #Rule(WelcomeGuideCompleted.event) { $0.donations.count >= 1 }
    }
}
