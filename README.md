# PT-210 Print

PT-210 Print is a privacy-first iPhone app that prepares text, Markdown, HTML/CSS, and images as 384-pixel ESC/POS raster output for the PT-210 thermal Bluetooth printer.

## Current status

This repository contains a feature-complete 1.0 candidate. The iOS 27 device build compiles successfully with Xcode 27. Discovery, connection, automatic reconnect, raster text, photos, calibration output, and paper feed have been verified on a physical PT210L advertising as `PT210L_30E2`. The main app, shared print engine, Share Extension, and three Shortcuts actions use the same rendering and print pipeline.

The following work still needs physical validation or implementation:

- validate Share Sheet and Shortcuts printing across JPEG, PNG, HEIC, and HEIF on the physical device;
- run repeated print, disconnect, low-battery, memory, accessibility, appearance, and localization tests;
- complete and verify the seven required translations before App Store distribution.

Do not treat this build as production-ready until those checks pass on a physical printer.

## Features

- PT-210 discovery over Bluetooth Low Energy using known services, with a name-based fallback scan.
- Saved `CBPeripheral.identifier` and automatic reconnect support.
- Serialized writes with dynamic maximum BLE payload size, backpressure, cancellation, and configurable pacing.
- ESC/POS initialization, heating, and `GS v 0` raster-strip encoding.
- PT210L-compatible paper feed using blank raster rows because this tested firmware ignores `ESC d n`.
- 384-pixel, 1-bit output with threshold, Floyd–Steinberg, Atkinson, and Bayer 4×4 processing.
- Plain text, Unicode, Markdown, and local-only HTML/CSS rendering.
- JPEG, PNG, HEIC, and HEIF selection from Photos or Files with a matching 1-bit thermal preview.
- Image fit-width, actual-size, centered, and square-crop modes with brightness, contrast, gamma, threshold, dithering, and inversion controls.
- Three explicit profiles throughout the app, Share Sheet, and Shortcuts: Text, Image (High quality J06), and Custom.
- A hardware-calibrated High quality photo profile based on the selected J06 result: Atkinson dithering, threshold 0.50, gamma 1.30, local contrast 0.30, heating interval 4, full-image raster transfer to avoid horizontal strip seams, and the full 384-dot print-head width without software margins.
- Automatic use of the J06 High quality profile when a photo is selected, while text, Markdown, and HTML use a separate hard-edge monochrome profile with 3× supersampling for cleaner glyphs. Plain-text lines made entirely from dash characters are normalized to connected rule glyphs. Wrapped Markdown bullets and `[ ]`/`[x]` task items use a hanging indent so continuation lines align with the item text.
- An isolated, labelled three-print image-quality comparison under Settings → Diagnostics. It compares Lanczos-5 resampling, one-percent percentile contrast stretching, and reproducible uniform blue-noise dithering against the same J06 transport and heating baseline without changing a saved profile.
- Automatic background reconnection to the saved printer when the app opens, with manual connection controls still available.
- A repository-owned AppIcon generated from `docs/icons/app-icon.png` and compiled through the iOS asset catalog.
- Shared App Group settings and atomic pending-job storage.
- First-launch PT-210 onboarding, deterministic single-tap prepared-job selection with a visible selected state, long-press and swipe deletion, cancellation, one automatic reconnect retry, a fixed quality test page, and expanded connection/job diagnostics.
- A Share Extension with thermal preview, quality selection, copies, feed, direct printing, and preparation of shared text, HTML, supported files, and images.
- Shortcuts actions for text/Markdown/HTML, images, and detected files, including quality, copies, feed, image scaling, and prepare-for-preview options.
- Light and dark appearance through semantic SwiftUI styling.

All processing is local. The app has no server, account, analytics, cloud sync, or remote HTML resources.

## Supported platform and languages

- iPhone running iOS 27 or later.
- Developed and built with Xcode 27 and Swift 6.4.
- The current hardware-test UI is English only. English, Dutch, French, German, Spanish, Italian, and Brazilian Portuguese are required before 1.0.

## Requirements

- macOS with Xcode 27 or later;
- an iPhone 15 Pro or another iPhone running iOS 27;
- a PT-210 58 mm Bluetooth thermal printer and paper;
- an Apple ID configured in Xcode for on-device development;
- a paid Apple Developer account if App Groups or distribution provisioning requires it.

There are no third-party source dependencies. `PT210PrintCore` is a local Swift package that uses Apple frameworks only.

## Open and configure

1. Open `ios/PT210Print.xcodeproj` in Xcode.
2. Select the **PT210Print** project, then the **PT210Print** target.
3. Under **Signing & Capabilities**, select your development team.
4. Repeat this for **PT210PrintShare**.
5. If the existing identifiers are not available to your team, change all three values together:

   - app: `nl.florisvandesande.pt210print`;
   - extension: `nl.florisvandesande.pt210print.share`;
   - App Group: `group.nl.florisvandesande.pt210print`.

   Update the App Group in both entitlement files and `AppGroup.identifier` in `ios/PT210PrintCore/Sources/PT210PrintCore/Models.swift`.

No secret configuration file is needed. Run `git status --short` and confirm that Xcode did not add personal signing files; `xcuserdata` is ignored.

## First hardware test

1. Turn on the PT-210 and place it near the iPhone.
2. Connect the iPhone to the Mac, trust the Mac, and enable Developer Mode if iOS asks.
3. In Xcode, select the iPhone as destination and press **Run**.
4. Accept the Bluetooth permission prompt.
5. Open **Printer**, tap **Search for PT-210**, and select the printer.
6. Return to the main screen and tap **Print**, or open **Settings → Diagnostics → Print quality test page**.
7. To compare experimental photo processing, tap **Print image quality comparison**. This always uses the bundled squirrel photograph and prints three labelled variants; it does not replace J06 or modify saved settings.

Expected result: the printer initializes, prints a small 384-pixel raster line of text, and feeds three lines using blank raster rows. Stop testing if the printer becomes unusually hot, repeatedly disconnects, or produces continuous paper feed.

Record the values shown under **Settings → Diagnostics** if discovery or connection fails: peripheral UUID, service UUID, write characteristic, and maximum write length. The peripheral UUID is device-local diagnostic data and should not be committed or posted publicly.

## Build and verification

Compile the shared package for iOS:

```bash
cd ios/PT210PrintCore
CLANG_MODULE_CACHE_PATH="$PWD/../../.temporary/clang-cache" \
swift build --disable-sandbox \
  --cache-path "$PWD/../../.temporary/swiftpm-cache" \
  --scratch-path "$PWD/../../.temporary/swift-ios-build" \
  --triple arm64-apple-ios27.0 \
  --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk
```

Build the complete unsigned device product:

```bash
cd ios
xcodebuild \
  -project PT210Print.xcodeproj \
  -scheme PT210Print \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ../.temporary/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

A successful command ends with `** BUILD SUCCEEDED **`. Bluetooth cannot be validated in the simulator, so a successful build is not proof that printing works.

## Project structure

```text
ios/
├── PT210Print.xcodeproj/          Xcode project and shared scheme
├── PT210PrintApp/                 SwiftUI app and App Intents
├── PT210PrintShareExtension/      Share Sheet extension
└── PT210PrintCore/                Shared local Swift package and tests
    ├── Sources/PT210PrintCore/
    └── Tests/PT210PrintCoreTests/
```

The central pipeline is:

```text
content → renderer → grayscale → dithering → 1-bit bitmap
        → ESC/POS raster strips → BLE chunks → PT-210
```

UI code never constructs printer bytes. App, extension, and Shortcuts share the same models, storage, rendering, and executor.

## Tests

Unit tests cover exact ESC/POS bytes, bit order, 384-pixel row width, raster-strip boundaries, inversion, content detection, and pending-job storage. The current environment can compile the package and app for iOS; running the test bundle still requires an available iOS 27 simulator or device.

Required physical release checks include 20 consecutive prints, long raster output, disconnect and reconnect cases, low battery, multiple paper types, Share Sheet flows, and all three Shortcuts flows.

## Troubleshooting

### No printer appears

- Confirm that Bluetooth is enabled and the PT-210 is on and nearby.
- Close any other app that may already be connected to the printer.
- Wait at least five seconds; the app falls back to an unfiltered foreground scan.
- Note the advertised printer name if it is not `PT-210` or `MTP-2`.

### The printer connects but nothing prints

The firmware may use another GATT profile or protocol variant. Copy the non-sensitive diagnostics values from the app and compare them with the known profiles in `PT210GATTProfile.known`.

### Signing or App Group errors

Select the same development team for both targets and ensure both targets use the same App Group. A free personal team may not support every entitlement.

### Partial or shifted output

Do not repeatedly retry a long job. The likely cause is an incorrect write mode, pacing delay, or raster-strip size; record the diagnostic values and test with a short sample first.

## Distribution

There is no distributable release yet. Before TestFlight or App Store submission, add production signing, complete localization and accessibility verification, provide an app icon and screenshots, validate privacy metadata, and pass the physical regression suite.

## License

The source code is available under the [MIT License](LICENSE).

The bundled image-quality test photograph is `richard-sagredo-VKe5EyWv8PA-unsplash.jpg`, photographed by Richard Sagredo and supplied for this project from Unsplash. It remains subject to the Unsplash license rather than the source-code license.
