# SpoolKid

SpoolKid is an iOS companion app for [Spoolman](https://github.com/Donkie/Spoolman), a self-hosted filament manager for 3D printers. It lets you manage your filament inventory, read and write NFC tags on your spools, scan filament labels with the camera, and keep your physical spools in sync with your Spoolman database.

I originally built this project to simplify my own filament management workflow on the Snapmaker U1 using [paxx's Extended Firmware](https://github.com/paxx12/SnapmakerU1-Extended-Firmware), especially its OpenSpool NFC support. SpoolKid now aims to be compatible with as many NFC tag formats as possible, support other printers as well, and be an excellent [Spoolman](https://github.com/Donkie/Spoolman) management app.

## Install

Join the public beta on [TestFlight](https://testflight.apple.com/join/Y4BmejQk). Requires iOS 18 or later, and a device with NFC.

## Features

### NFC tag formats

SpoolKid reads and writes NFC tags (NTAG213/215/216) in five formats. Reading auto-detects the format; writing uses whichever format you select.

| Format | Notes |
|---|---|
| **OpenSpool** | JSON-based NDEF. Default format. |
| **OpenPrintTag** | NDEF with `application/vnd.openprinttag` MIME type. |
| **OpenTag3D** | NDEF with `application/opentag3d` MIME type. |
| **Anycubic ACE** | Raw page format (non-NDEF) for ACE Pro spool holder compatibility. |
| **ELEGOO** | Raw page format for ELEGOO RFID tags. |

**Note:** I primarily use OpenSpool and OpenPrintTag. If you can test the other formats, please help validate SpoolKid's implementation and share your findings.

### Scanning

Beyond NFC, SpoolKid scans filament labels with the camera in a single session that handles both QR codes and printed text (OCR) — useful for spools that have no tag yet, and for vendor labels and product pages.

Every scan, whichever way it arrives, lands in the **Scan Result Hub**, which works out what you scanned: an embedded Spoolman spool ID is used directly, a known tag UID resolves to its spool, and otherwise the filament data on the tag or label is scored against your library and the best candidates are offered for confirmation. From there you can accept the match, pick a different spool, write a new tag, or create the spool.

### Spoolman integration

- Browse and manage **spools**, **filaments**, **vendors** and **locations** directly from your Spoolman instance.
- Import filament definitions from the global [SpoolmanDB](https://github.com/Donkie/SpoolmanDB) catalog, creating the vendor and filament in your Spoolman automatically.
- Create a spool and write its NFC tag in one step with **Save and Write NFC Tag**.

### SpoolLink tag mapping

Tag-to-spool mappings are stored in Spoolman's `card_uids` extra field — uppercase hex, comma-separated, with no limit on how many tags a spool can carry. This matches the [Snapmaker U1 Extended Firmware](https://github.com/paxx12/SnapmakerU1-Extended-Firmware) convention, so your printer recognises spools by tag.

Mappings still stored the old way (`card_uid:` tokens in `lot_nr`) are read as a fallback and migrated the first time SpoolKid encounters them, so nothing needs re-tagging by hand. The whole feature sits behind a **SpoolLink** toggle in the app's Spoolman settings: switching it on provisions the field on your Spoolman instance, switching it off removes it again.

### Home dashboard

A read-only inventory overview: spool fill levels bucketed from full to empty, a breakdown by material, how much of your inventory is tagged, which filaments you are likely to run out of soonest, and total inventory value. Every card drills through to the matching filtered spool list.

### Colour filter

Manage Spools can be filtered by colour using a spectrum map, with harmony modes for finding complements and near-matches rather than only exact ones. Active filters appear as a row of chips above the list, each individually clearable.

### Using SpoolKid without a server

SpoolKid works without Spoolman: a small on-device library lets you try the app and manage a handful of spools with no server at all. Connect a Spoolman instance later and SpoolKid offers to migrate what you created on device, letting you resolve any duplicates it finds against what is already on the server.

### Configuration

Settings are split by how you use them. Things that are part of a workflow or need live validation — your Spoolman connection, dashboard layout, which fields appear on forms — live **in the app**. Rarely touched utility and recovery toggles — recent-tags limit, diagnostics, reset all data — live in the **iOS Settings app** under Settings › SpoolKid.

## Bugs and feature requests

[Open an issue](https://github.com/marko-p/SpoolKid/issues) — this is the right place for both, and I read every one. Bug reports are most useful with your iOS version, the tag format involved, and whether you are connected to Spoolman.

## Support the project

SpoolKid is free to use, and keeping it running has real costs — subscriptions and services, an Apple Developer account, test hardware, and the tags themselves. If SpoolKid saves you time at the bench, a contribution helps keep it going.

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub-%23EA4AAA?logo=github)](https://github.com/sponsors/marko-p)
[![Ko-fi](https://img.shields.io/badge/Donate-Ko--fi-%23FF5E5B?logo=ko-fi)](https://ko-fi.com/spoolkid)

Thank you!

## Source availability

The code in this repository is the v0.9 snapshot from May 2026. It stays here, and it stays MIT-licensed — that doesn't change, and anyone who wants to fork it, learn from it, or build it still can.

Development has continued privately since then. Publishing a codebase is its own ongoing commitment — keeping it reviewable, explaining decisions, keeping it in a state someone else could pick up — and SpoolKid outgrew what I can carry alongside actually building the app. So new work isn't published here.

What hasn't changed: SpoolKid is still actively developed, still free to everyone on TestFlight, and this issue tracker is still the right place for bugs and feature requests. I read every one.

**Building the snapshot:** Xcode 16+, iOS 18+, an Apple Developer account. Copy `Development.xcconfig.template` to `Development.xcconfig`, set your Team ID, open `SpoolKid.xcodeproj`, and run on a physical device — NFC does not work in the Simulator.

## Acknowledgments

- [Lucio](https://github.com/unlucio/) for testing, feedback, and pushing the Snapmaker U1 community toward Spoolman integration.
- [Donkie](https://github.com/Donkie) for creating Spoolman and SpoolmanDB.
- [paxx12](https://github.com/paxx12) for the Snapmaker U1 Extended Firmware, which inspired this project.
