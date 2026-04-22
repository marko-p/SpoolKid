# SpoolKid

SpoolKid is an iOS companion app for [Spoolman](https://github.com/Donkie/Spoolman), a self-hosted filament manager for 3D printers. It lets you manage your filament inventory, write filament data to NFC tags, and keep your physical spools in sync with your Spoolman database.

The project was originally created for the Snapmaker U1 running [paxx's Extended Firmware](https://github.com/paxx12/SnapmakerU1-Extended-Firmware), which adds OpenSpool NFC tag support to the U1. SpoolKid has since grown into a general-purpose NFC filament tagging tool that works with multiple tag formats and printers.

## Support the Project

SpoolKid is free and open-source (MIT License), but keeping it running has real recurring costs:

**Apple Developer Program** — $100/year, required to distribute on the App Store and TestFlight. Without it, NFC functionality cannot be used on a real device at all (CoreNFC requires an entitlement that only Apple can grant through a paid membership).

If SpoolKid saves you time or makes your 3D printing workflow smoother, please consider helping cover these costs. Even a small contribution goes a long way toward keeping the app alive and actively developed.

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub-%23EA4AAA?logo=github)](https://github.com/sponsors/marko-p)
[![Ko-fi](https://img.shields.io/badge/Donate-Ko--fi-%23FF5E5B?logo=ko-fi)](https://ko-fi.com/spoolkid)

Thank you — it genuinely makes a difference.

## Install

**TestFlight (Recommended):**

Join the public beta: [TestFlight](https://testflight.apple.com/join/Y4BmejQk)

**Build from Source:**

1. Clone the repository.
2. Copy `Development.xcconfig.template` to `Development.xcconfig` and set your Apple Developer Team ID.
3. Open `SpoolKid.xcodeproj` in Xcode.
4. Build and run on a physical device (NFC does not work in the Simulator).

Requires Xcode 16+ and iOS 18.0+.

## Features

### NFC Tag Formats

SpoolKid reads and writes NFC tags (NTAG213/215/216) in four formats. Reading auto-detects the format; writing uses whichever format you select in Settings.

| Format | Notes |
|---|---|
| **OpenSpool** | JSON-based NDEF. Default format. |
| **OpenPrintTag** | NDEF with `application/vnd.openprinttag` MIME type. |
| **OpenTag3D** | NDEF with `application/opentag3d` MIME type. |
| **Anycubic ACE** | Raw page writes (non-NDEF) for ACE Pro spool holder compatibility. |

### Spoolman Integration

- Browse and manage **Spools**, **Filaments**, and **Vendors** directly from your Spoolman instance.
- Import filament definitions from the global [SpoolmanDB](https://github.com/Donkie/SpoolmanDB) catalog, automatically creating the vendor and filament in your local Spoolman.
- Create a spool and write its NFC tag in a single step with **Save and Write NFC Tag**.
- Pull-to-refresh on all management lists.

### Recent Tags

Recently written tags are saved for quick re-use. The number of remembered tags is configurable (5 / 10 / 20 / 50 / 100; default 20).

### Printer Compatibility

- **Snapmaker U1 mode**: Validates and auto-maps material types to the U1's supported list before writing. Only applies to OpenSpool format.

### Configuration

All settings live in the iOS **Settings** app (Settings > SpoolKid), not inside the app itself:

- **NFC Tag Options** -- write format, spool ID writing, recent tags limit.
- **Printer Compatibility** -- Snapmaker U1 material validation.
- **Spoolman Connection** -- server URL, certificate trust.
- **Authentication** -- None, Basic Auth, or API Key / Bearer Token.
- **Spoolman Management** -- remember last spool/filament data, confirm before deleting.
- **Reset** -- wipe all app data on next launch.

### Other

- Guided first-launch setup (format selection, Spoolman connection).
- Offline NFC reading/writing without a Spoolman connection.
- About page with app info and a link to jump straight to iOS Settings.

## Code Structure

| Directory | Contents |
|---|---|
| `Models/` | Data structures for NFC tags (`FilamentTagData`) and Spoolman API objects (`SpoolmanSpool`, etc.). |
| `Services/` | Networking (`SpoolmanService`), external DB (`SpoolmanDBService`), recent tags (`RecentTagManager`), config (`AppConfig`). |
| `NFC/` | `NFCManager` -- CoreNFC read/write logic and format encoding. |
| `Views/` | SwiftUI views for the entire UI. |
| `Settings.bundle/` | iOS Settings app preferences. |

## Acknowledgments

- [Lucio](https://github.com/unlucio/) for testing, feedback, and pushing the Snapmaker U1 community toward Spoolman integration.
- [Donkie](https://github.com/Donkie) for creating Spoolman and SpoolmanDB.
- [paxx12](https://github.com/paxx12) for the Snapmaker U1 Extended Firmware, which inspired this project.
