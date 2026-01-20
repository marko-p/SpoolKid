# SpoolKid

> **Alpha notice:** NFC read/write is experimental and requires CoreNFC entitlements from Apple. This project is in early ALPHA and currently awaiting Apple Developer Program approval; until entitlements are granted NFC capabilities are limited. You can still create and export tag payloads in the app and write them using a general NFC writer app as a workaround.

SpoolKid is an iOS companion application for [Spoolman](https://github.com/Donkie/Spoolman), a self-hosted filament manager for 3D printers. SpoolKid allows you to easily manage your filament inventory and write filament data to NFC tags (NTAG213/215/216) for quick identification and usage tracking.

This project was created to make it easy to use the Snapmaker U1 enhanced with paxx's extended firmware (https://github.com/paxx12/SnapmakerU1-Extended-Firmware). That firmware adds support for OpenSpool NFC tags to the U1 3D printer; SpoolKid was developed to streamline creating and writing those tags and integrating them with a Spoolman instance.

## Features

*   **_[[ALPHA - Not Functional]]_ NFC Integration**: Read and write filament data to NFC tags.
*   **Spoolman Sync**: Connects directly to your Spoolman instance to manage Spools, Filaments, and Vendors.
*   **External Database**: Integrated with [SpoolmanDB](https://github.com/Donkie/SpoolmanDB) to easily import filament definitions from a global catalog.
*   **_[[ALPHA - Not Functional]]_ Smart Tagging**: Write essential printing parameters (temps, material, brand) and link specific Spoolman IDs to physical tags.
*   **_[[ALPHA - Not Functional]]_ Offline Capable**: Basic NFC reading/writing works without a Spoolman connection (though main purpose of this app is exactly Spoolman integration).

## Getting Started

### Prerequisites

*   Mac with Xcode 15.0 or later.
*   iPhone with NFC capability (iPhone 7 or newer).
*   iOS 15.0 or later.
*   (_Preferably_) A running instance of [Spoolman](https://github.com/Donkie/Spoolman).
*   (_Optional_) Snapmaker U1 running paxx's Extended Firmware for OpenSpool NFC tag support if you intend to use tags with a U1 printer.

### Installation

1.  Clone the repository
2.  Open `SpoolKid.xcodeproj` in Xcode.
3.  Change the Bundle Identifier and Team in the "Signing & Capabilities" tab to your own Apple Developer account.
4.  Build and run on your physical device (NFC does not work in the Simulator).

## Configuration

1.  Open the app and navigate to the **Settings** tab.
2.  Enter your Spoolman URL (e.g., `http://192.168.1.50:7912`).
3.  Test the connection to ensure the app can communicate with your server.
4.  (Optional) Toggle "Write Spool ID to Tag" if you want to link physical tags to specific database entries.

### Code Structure

*   **Models**: Data structures for NFC tags (`FilamentTagData`) and Spoolman API objects (`SpoolManSpool`, etc.).
*   **Services**: Handles networking (`SpoolManService`), external DB fetching (`SpoolmanDBService`), and app configuration (`AppConfig`).
*   **NFC**: Contains `NFCManager`, the core logic for CoreNFC interactions.
*   **Views**: SwiftUI views for the user interface.

## License & Support

This project is open-source and designed for iOS devices. Providing native NFC functionality and the convenience of installing directly from the App Store requires maintenance of an Apple Developer Program membership ($100/year). If you find this app useful, please consider supporting the development to help cover these overhead costs.ss

[Link to Donation/Sponsorship Page]

## Acknowledgments

*   [Donkie](https://github.com/Donkie) for creating Spoolman and SpoolmanDB.
*   [paxx12](https://github.com/paxx12) for the Snapmaker U1 Extended Firmware, which adds OpenSpool NFC tag support to the U1 printer and inspired this project's workflow.
*   [Lucio](https://github.com/unlucio/) for enabling the Snapmaker U1 to properly read tagged spools and apply them in the Monraker/Spoolman integration.
