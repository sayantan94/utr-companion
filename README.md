# UTR Companion

A native iPhone companion for the owner's Audi Universal Traffic Recorder, with an Audi F1-inspired interface. This is an independent local prototype, not an official Audi app.

## Run

- Open `ios/UTRCompanion.xcodeproj` in Xcode and run the `UTRCompanion` scheme on an iPhone simulator. The app starts in **Demo mode**.
- For a physical iPhone, choose your signing team. The target requires Hotspot Configuration and Access Wi-Fi Information capabilities, plus iOS local-network permission.
- Use **DEMO / WI-FI** for one-time recorder network setup. Enter the exact recorder SSID and password. The SSID/address are remembered in app preferences; the password goes into the device-only iOS Keychain. No real credentials are embedded in the project.
- The app uses the remembered network on foreground/reconnection. iOS controls network joining and may request user permission. It cannot silently force Wi-Fi changes or run continuously after termination.

The standalone browser preview is `output/utr-app-preview.html`. Its editable inline source is `output/audi-utr.html`. Earlier visual drafts are retained in `output/`.

## Current implementation

- Audi F1-inspired dark interface, orange-red accents, front/rear live-view selection and offline states.
- Local movie import from Files, AVPlayer playback, camera filters, saved-date sorting, and optional recording-date sorting.
- Original filenames and timestamps are retained. Date corrections live in an undoable app catalog; raw video is never retimed or rewritten. Unknown timezone and camera identity are not guessed.
- Remembered Wi-Fi with Keychain credential storage and a bounded, identity-checked UTR 2.0 connection path.
- Automatic phone date/time/timezone request after a supported recorder is identified, and on significant device clock/timezone changes. **No manual sync button.** Accepted requests are labeled as verification pending until hardware behavior is checked.
- Legacy UTR 2.0 settings read and three sensor writes, followed by settings save and read-back.
- A standalone Swift package with protocol/date tests.

## Not yet verified or implemented

- The car is unavailable. No connection, clock write, or settings write has been tested against the owner's hardware. The reference APK is Android V2.02; the installed iPhone app is V2.92. Model, firmware and current authentication still need validation.
- Real RTSP live playback needs a decoder integration. The native app explicitly displays this limitation in hardware mode; demo images are illustrations.
- Recorder file-list parsing, downloading clips over Wi-Fi, verified front/rear pairing and synchronized real playback remain to be implemented. Files import and local playback are available now.
- UTR 1.0's native iCatch transport, newer sensitivity ranges, optional DSM/LTE accessories, and firmware updates are not supported by this first adapter. Unknown device IDs are rejected before writes.
- This build has not been signed or installed on the owner's physical iPhone.

## Development

```sh
cd ios/UTRCore
swift test
```

```sh
cd ios
xcodegen generate
xcodebuild -project UTRCompanion.xcodeproj -scheme UTRCompanion \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

XcodeGen is only needed when changing `ios/project.yml`; the generated project is committed. Tests cover header-based CGI framing, device clock offsets including daylight saving, rejecting unsupported devices/addresses, strict filename date parsing, and independent corrections without changing original metadata.

## Evidence and working conventions

See [the app audit](docs/app-audit.md) for recovered commands, source references, observed iPhone behavior and protocol limitations. Private APK/decompiled files, build outputs, logs and signing state are excluded from Git. Commit working milestones with descriptive messages; comment non-obvious protocol decisions and security boundaries rather than narrating every line.

Visual reference: [Audi's team page on Formula 1](https://www.formula1.com/en/teams/audi). Platform references: [Apple's Wi-Fi configuration API](https://developer.apple.com/documentation/networkextension/nehotspotconfigurationmanager) and [local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
