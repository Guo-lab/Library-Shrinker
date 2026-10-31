# Library Shrinker

Library Shrinker is an iOS utility for finding large videos and screenshots, creating smaller copies, and safely reviewing the result before removing an original.

[![Watch the Library Shrinker demo](Docs/demo-poster.png)](Docs/Library-Shrinker-Demo.mp4)

## Full Simulator Demo

https://github.com/user-attachments/assets/e003c406-0a9b-41bc-b8c1-841053346a79

**[Watch the full simulator demo](Docs/Library-Shrinker-Demo.mp4)**

**[Watch the complete uncut recording](Docs/Library-Shrinker-Demo-Full.mp4)**

## Highlights

- Scan videos and screenshots from the photo library.
- Select one or multiple items for compression or deletion.
- Choose HEVC or H.264 and control the target size by ratio or bitrate.
- Continue an active compression task after leaving the app.
- Automatically show the compressed copy and its verified original relationship.
- Preview results before using guarded deletion actions.
- Export and import scan metadata, compression relationships, and deletion records.

## Demo flow

The demo selects a 6.2 MB test video, compresses it to 1.7 MB with HEVC at a 20% target, briefly leaves the app to demonstrate background continuation, previews the generated copy, cancels a deletion confirmation, and opens Backup & Restore.

The footage was recorded on an iPhone simulator using synthetic test media. No personal photo-library content is included. Long processing time is accelerated in the edited demo. A compressed version of the complete recording is also included; the 85 MB source capture remains local and is excluded from Git.

## Verification

The exercised simulator scenarios and expected results are documented in [Simulator Test Cases](Docs/Simulator-Test-Cases.md).

## macOS status

The repository now includes a native `Library Shrinker Mac` target. The first macOS milestone currently provides:

- Native `NavigationSplitView` library navigation.
- PhotoKit authorization and access to videos and screenshots stored in Mac Photos.
- Native Command/Shift multi-selection.
- HEVC or H.264 video compression with a target-size ratio.
- JPEG screenshot compression with a target-size ratio.
- Safe deletion confirmation and non-destructive compressed-copy creation.

The macOS target builds and launches successfully and has read real PhotoKit video assets. Automated UI interaction tooling does not currently support macOS, so visual interaction and compression output still require manual testing on a Mac Photos library.

Planned macOS parity work:

- Extract the verified iOS/macOS compression, persistence, and metadata logic into a shared layer.
- Add original-file size scanning, bitrate mode, compression profiles, and detailed progress.
- Add preview, original/compressed relationship verification, and backup import/export.
- Add a Mac-appropriate long-running task model and cancellation recovery.
- Observe Photos library and external-library availability changes.
- Optionally scan screenshot folders outside Photos.
