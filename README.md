# SpoolKid

SpoolKid is an iOS companion app for [Spoolman](https://github.com/Donkie/Spoolman), a self-hosted filament manager for 3D printers. It lets you manage your filament inventory, write filament data to NFC tags, and keep your physical spools in sync with your Spoolman database.

I originally built this project to simplify my own filament management workflow on the Snapmaker U1 using [paxx's Extended Firmware](https://github.com/paxx12/SnapmakerU1-Extended-Firmware), especially its OpenSpool NFC support. SpoolKid now aims to be compatible with as many NFC tag formats as possible, support other printers as well, and be an excellent [Spoolman](https://github.com/Donkie/Spoolman) management app.

## Support the Project

SpoolKid is free and open-source (MIT License), but keeping it running has recurring costs. If SpoolKid saves you time or makes your 3D printing workflow smoother, please consider helping cover these costs. Even a small contribution goes a long way toward keeping the app alive and actively developed.

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub-%23EA4AAA?logo=github)](https://github.com/sponsors/marko-p)
[![Ko-fi](https://img.shields.io/badge/Donate-Ko--fi-%23FF5E5B?logo=ko-fi)](https://ko-fi.com/spoolkid)

Thank you!

## Install

**TestFlight (Recommended):**

Join the public beta: [TestFlight](https://testflight.apple.com/join/Y4BmejQk)

**Build from Source:**

Requires Xcode 16+, iOS 18.0+ and Apple Developer subscription.

1. Clone the repository.
2. Copy `Development.xcconfig.template` to `Development.xcconfig` and set your Apple Developer Team ID.
3. Open `SpoolKid.xcodeproj` in Xcode.
4. Build and run on a physical device (NFC does not work in the Simulator).

## Features

### NFC Tag Formats

SpoolKid reads and writes NFC tags (NTAG213/215/216) in four formats. Reading auto-detects the format; writing uses whichever format you select.

| Format | Notes |
|---|---|
| **OpenSpool** | JSON-based NDEF. Default format. |
| **OpenTag3D** | NDEF with `application/opentag3d` MIME type. |
| **ELEGOO** | Raw page format for ELEGOO RFID tags. |
| **Anycubic ACE** | Raw page format (non-NDEF) for ACE Pro spool holder compatibility. |

**Note:** I primarily use OpenSpool. If you can test other formats, please help validate SpoolKid’s implementation and share your findings.

### Encrypted or Unknown Tags

SpoolKid detects encrypted MIFARE Classic tags and other unsupported formats. Because iOS CoreNFC cannot authenticate MIFARE Classic sectors, the tag payload cannot be read. However, SpoolKid captures the tag's hardware UID, which can be linked to a Spoolman spool for automatic identification on future scans.

### Spoolman Integration

- Browse and manage **Spools**, **Filaments**, and **Vendors** directly from your Spoolman instance.
- Import filament definitions from the global [SpoolmanDB](https://github.com/Donkie/SpoolmanDB) catalog, automatically creating the vendor and filament in your local Spoolman.
- Create a spool and write its NFC tag in a single step with **Save and Write NFC Tag**.
- **Tag UID slots**: link up to two physical tag UIDs to each spool (compatible with [Snapmaker U1 Extended Firmware PR #364](https://github.com/paxx12/SnapmakerU1-Extended-Firmware/pull/364)). Stored in `lot_nr` as `card_uid:UID[,card_uid:UID2]`. Assign UIDs by scanning directly from the spool edit form.
- Pull-to-refresh on all management lists.

### Spoolman Auto Register

After every successful scan of NFC's UID (regardless of tag format), SpoolKid tries to intelligently identify the scanned spool:

1. **Authoritative match** — if the tag embeds a Spoolman `spool_id`, the matching spool is shown immediately.
2. **UID lookup** — if the tag's hardware UID is already linked to a Spoolman spool (via `lot_nr`), that spool is shown.
3. **Heuristic match** — filament data on the tag (material, brand, color, temperatures) is scored against your Spoolman library and ranked candidates are shown for confirmation.
4. **Unsupported tag** — UID-only card with manual linking to Spoolman spool (via `lot_nr`).

From the Scan Result Hub you can confirm the match, choose a different spool, write a new NFC tag, or save the scan to Recent Tags.

**Note:** You must first enable this feature in preferences to use it.

### Recent Tags

Recently written tags are saved for quick re-use. The number of remembered tags is configurable (5 / 10 / 20 / 50 / 100; default 20).

### Configuration

All settings live in the iOS **Settings** app (Settings > SpoolKid), not inside the app itself:

- **NFC Tag Options** -- write format, spool ID writing, recent tags limit.
- **Printer Compatibility** -- Snapmaker U1 material validation.
- **Tag - Spoolman Mapping** -- write spool ID to tags and persist scanned tag IDs to Spoolman `lot_nr`.
- **Spoolman Connection** -- server URL, certificate trust.
- **Authentication** -- None, Basic Auth, or API Key / Bearer Token.
- **Spoolman Management** -- remember last spool/filament data, confirm before deleting.
- **Reset** -- wipe all app data on next launch.

### Other

- Guided first-launch setup (format selection, Spoolman connection).
- Offline NFC reading/writing without a Spoolman connection.

## Code Structure

| Directory | Contents |
|---|---|
| `Models/` | Data structures for NFC tags (`FilamentTagData`), Spoolman API objects (`SpoolmanSpool`, etc.), and scan output (`ScanResult`). |
| `Services/` | Networking (`SpoolmanService`), external DB (`SpoolmanDBService`), recent tags (`RecentTagManager`), heuristic matching (`FilamentMatchService`), UID slot management (`SpoolMappingService`), config (`AppConfig`). |
| `NFC/` | `NFCManager` -- CoreNFC read/write logic and format encoding. |
| `Views/` | SwiftUI views for the entire UI. |
| `Settings.bundle/` | iOS Settings app preferences. |

## Acknowledgments

- [Lucio](https://github.com/unlucio/) for testing, feedback, and pushing the Snapmaker U1 community toward Spoolman integration.
- [Donkie](https://github.com/Donkie) for creating Spoolman and SpoolmanDB.
- [paxx12](https://github.com/paxx12) for the Snapmaker U1 Extended Firmware, which inspired this project.
