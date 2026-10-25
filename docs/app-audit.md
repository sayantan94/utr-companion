# Audi UTR app audit

Inspected the owner's installed iPhone app through iPhone Mirroring on 2026-10-25. App reports **V2.92**. The recorder was out of range throughout the audit. Values visible in disconnected settings may be cached/default values, not current device state. No settings were applied, no recordings were deleted, and no credentials are recorded here.

## Observed screens

| Screen | Controls and behavior observed | Replacement design |
| --- | --- | --- |
| Home | Connection status, radar and G-shock events, Live, Video Gallery, Car Finder, Settings, DSM Settings, LTE Router; Imprint, Legal, Software | Camera overview, recordings, recorder controls; show optional accessories only when supported |
| Software | Phone app V2.92; disconnected recorder, bootloader, Micom, and front/rear radar versions; region, manual, firmware update, Wi-Fi reset | Device details with explicit last-read time; hardware-changing actions separated from information |
| Connection error | Generic Wi-Fi error and initial setup instructions, Wi-Fi settings button, continue without Wi-Fi | Distinguish network join, recorder reachability, authentication, and ready state; bounded retry and offline access |
| Video Gallery | Separate UTR and Phone pages | Clear On recorder / On iPhone selector with offline saved library |
| Phone gallery | MP4 filenames grouped by date; playback, deletion, sharing, show files folder | Thumbnail grid/list, duration, human labels, event filter, inline playback and reversible library actions |
| Wi-Fi | Recorder AP or vehicle hotspot; SSID/password, copy; 2.4/5 GHz selector; apply/reset | Mask credentials, explain connection types; native joining subject to iOS capabilities |
| Mode | Driving choices visible: Continuous + Shock and Race; parking choices visible: Radar + Shock and Video | Separate driving and parking sections with explanations of device-verified modes |
| Camera configuration | Front only / Front + Rear / 3 channel; rear orientation 0°/180°; optional interior camera black-and-white/colour | Hide unsupported channels; keep orientation beside camera preview |
| Sensors | Distinct Driving G-Sensor, Parking G-Sensor, Radar numeric sensitivity controls | Three separately named controls; ranges and direction of sensitivity must be verified, not guessed |
| System | GPS, MIC, speaker level, security LED, factory reset, SD format | Separate capture settings, notifications, and destructive maintenance actions |
| Video Overlay | Date, time, position, speed; km/h and mph | Preview overlays and offer individual toggles |
| DSM Settings | Bluetooth pairing (`Pair DSM`) and manual | Optional accessory setup; its presence in the app does not prove the owner has the accessory |
| LTE Router | Tutorial: insert micro-SIM, connect UTR/router using SIM PIN and APN, connect optional cloud provider, configure router | Separate optional accessory setup; no account or router configuration was started |
| Car Finder | Enable status, Get carfinder, last position and date/time, front/rear snapshots; blank while disconnected | Preserve last-known data with an explicit timestamp and stale indicator |
| Live | Opening this screen triggers a connection attempt and iOS join prompt while offline | Explain recorder offline immediately; avoid blocking unrelated offline functions |

## Date defects observed

The phone gallery contained a 2026 group and multiple 2031 groups. The filenames also encode 2031 dates. This confirms the displayed dates are inconsistent with the inspection date; it does **not** establish whether the root cause is the camera clock, file naming, metadata parsing, or some combination. The app alone cannot establish the correct capture date.

Replacement date model:

- Preserve the original filename, raw timestamp, timezone provenance, and original video bytes.
- Store the app's import/download timestamp separately from the recording timestamp. Never present a save/import date as a capture date.
- Flag impossible future dates and missing/ambiguous timestamps. A plausible date is not automatically verified.
- Default a library with suspect camera timestamps to `Date saved` when that value is known; offer `Recording date` explicitly. Existing imports without an original save timestamp receive the current import date with that label.
- Let the owner attach a corrected capture date as editable library metadata. Retain the original and the fact that the correction was user supplied; support undo.
- Offer a camera-clock check when connected. Time-sync support and semantics must be verified against this firmware before implementing a write.
- Never silently shift all files by a guessed offset or modify burned-in video overlays.

## Hardware feasibility and evidence

Audi's app listing and privacy documentation describe local Wi-Fi communication with the recorder. Public primary security research describes RTSP, FTP, and command interfaces in earlier UTR software. This is evidence that a replacement client is plausible, not a supported SDK or a verified protocol specification for this particular recorder/firmware.

- https://apps.apple.com/us/app/universal-traffic-recorder/id1182990619
- https://www.audi.de/de/rechtliches/datenschutz/utr-app/privacy-policy/
- https://github.com/geo-chen/Audi/blob/main/README.md
- https://developer.apple.com/documentation/networkextension/nehotspotconfigurationmanager
- https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

The iPhone app should use native network APIs and keep the UI independent from a versioned recorder adapter. No endpoints, credentials, sensor ranges, command IDs, or firmware mappings should be invented. Do not implement access by exploiting known vulnerabilities.

## Required hardware validation

1. Read exact model and firmware from the existing app when the owner is near the powered recorder.
2. Observe the owner's authenticated app/device traffic or obtain legitimate vendor protocol documentation. Determine discovery, authentication, command framing, and media access.
3. Validate read-only identity/status, settings retrieval, and file listing first.
4. Implement each setting using the observed supported range; perform an owner-selected reversible change and read it back before displaying it as applied.
5. Verify clip downloads, playback, front/rear tracks, disconnect/reconnect, partial transfer recovery, and timestamp interpretation.
6. Keep optional DSM/LTE features capability-gated. Defer firmware flashing, reset, and formatting until the protocol and recovery behavior are established.

As of this audit, the existing HTML concept is a UI simulation. It does not control hardware, read the camera, alter phone recordings, or fix their dates.

## APK inspection, 2026-10-25

The owner supplied an Android APK. It was copied to `research/input/audi-utr-reference.apk` and inspected statically with JADX 1.5.6; it was not installed or executed. Manifest: `com.audi.universaltrafficrecorderapp`, version **V2.02**, build **195**. SHA-256: `05ad0694228c6acdda390ea3d686cb1c844be9b383867dc4e0ce692c4abd75ec`. This is older than the owner's iPhone app V2.92. Certificate metadata claims Audi AG, but this inspection does not independently establish distribution authenticity. Decompiled source and APK remain ignored research inputs.

JADX reported 15 errors. The findings below refer to readable recovered methods; obfuscated source names are not a stable public API. All source paths below are relative to `research/decompiled/sources/`. No network requests were sent to a recorder.

| Finding | Evidence |
| --- | --- |
| Two different hardware paths: UTR 1.0 (ID 1094863153) and UTR 2.0 (1094863410) | `com/audi/universaltrafficrecorderapp/l/a.java:28` and `:39` |
| UTR 1.0 uses an iCatch SDK/JNI path; property IDs alone are insufficient to implement its wire transport | `com/audi/universaltrafficrecorderapp/j/b.java`; packaged `libicatch_wificam_sdk.so` |
| UDP discovery sends `$discovery$` to port 6201; replies listened for on local port 6202 | `com/audi/universaltrafficrecorderapp/service/DeviceDiscoveryService.java:43` and `:100` |
| Discovery broadcast address is computed as local IPv4 prefix + `.255`; fallback `255.255.255.255` | `com/audi/universaltrafficrecorderapp/j/e.java:136`; this assumes a /24 network, not a general subnet calculation |
| UTR 2.0 HTTP endpoints `req-get.cgi`, `req-set.cgi`, `req-cmd.cgi` | `d/a/a/b/a.java:2119` |
| Important framing detail: most CGI requests are HTTP POST, with the query-like string in a **Params header**, rather than a normal URL query | `d/a/a/b/e.java:93`, `:210`, `:294` |
| Settings read uses POST `/req-get.cgi`, `Params: ?settings`; parses JSON | `d/a/a/b/a.java:202`, `:2261` |
| Separate sensor keys `rec_gsensor_lv_driving`, `rec_gsensor_lv_parking`, `rec_radar_lv` | `d/a/a/b/a.java:2195` |
| Recording modes, camera channel and rear rotation have explicit UI-to-wire remapping | `d/a/a/b/a.java:2143`; do not equate a picker index with a hardware enum |
| Older UI exposes G-sensor Off/1–5 and radar Off/1–3, with regional branches | `com/audi/universaltrafficrecorderapp/fragment/ModeFragment.java:555`; does not establish ranges or sensitivity direction for the owner's firmware |
| UTR 1.0 SDK property IDs: driving G-sensor 55048, parking G-sensor 55050, radar 55051, clock 20497 | `com/audi/universaltrafficrecorderapp/j/b.java:553`, `:962`, `:1026`, `:1060` |
| UTR 2.0 live URL template uses RTSP H264, W=640, H=360, FPS=30, BR=1000000, V=selected camera | `com/audi/universaltrafficrecorderapp/fragment/LiveFragmentV2.java:327` |
| File listing command exists as `?filelist=<value>`; Car Finder snapshots use HTTP `/sd/carfind_cam_0.jpg` and `_1.jpg` | `d/a/a/b/a.java:2344`; `com/audi/universaltrafficrecorderapp/j/c.java:223` |
| Clock configuration has a separate GET route on port 8082, `/req-set.cgi?lang=&datetime=<value>&userAgent=android` | `d/a/a/b/a.java:2366`; callsite `com/audi/universaltrafficrecorderapp/j/b.java:553` formats local time with `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'Z`; exact semantics require device validation |
| In this old app's UTR 2.0 path, the method named `getDateTime` returns phone time rather than reading the recorder clock | `com/audi/universaltrafficrecorderapp/j/b.java:1045` |
| Downloaded gallery sorts filename strings and groups by `yyyyMMdd_HHmmss` parsed from the filename | `com/audi/universaltrafficrecorderapp/fragment/GalleryDownloadedFragment.java:159`, `:172`; parser `com/audi/universaltrafficrecorderapp/g/d.java:10` |

The gallery parser uses `SimpleDateFormat` without an explicit timezone, strictness setting, or future-date validation. This explains how a future-dated filename can create a future gallery group in this Android version. It does not prove the cause in iPhone V2.92, recover a real capture date, or establish which physical recorder generation the owner has.

Remaining protocol work: confirm physical model and firmware, current authentication/pairing, response and error schemas, file list/download conventions, settings save/read-back ordering, RTSP session handling, native UTR 1.0 transport if needed, and optional DSM/LTE capability checks. The recovered interface makes a replacement client plausible; hardware support remains unverified.

## Gallery preview delivered

`output/utr-gallery.html` is the inline editable mockup; `output/utr-app-preview.html` is the standalone HTML export. It opens on the iPhone library and includes grid/list layouts, saved-date vs recording-date sorting, future-date review, reversible library date correction preserving the raw filename and timestamp, offline recorder guidance, and separate sensor controls. Clips, thumbnails, save times and setting values are demonstration data.

Browser verification covered JavaScript parsing, gallery rendering at 320px, date correction and undo, grouping by recording date, list/grid switching, and a sensor-setting preview. These checks exercise the mockup only; no video was played, real file metadata edited, or recorder contacted.

## Accepted direction and native build

The owner selected https://www.formula1.com/en/teams/audi as the visual reference. Browser inspection found a vivid `#ff2d00` hero accent, dark surfaces, Formula1 headings, Titillium Web body text, and angled stripes. `output/audi-utr.html` now holds the current themed prototype; the standalone export remains `output/utr-app-preview.html`.

Front and rear are independently selectable in the sample library and live view. Paired sample playback has a shared position. Actual dual live streams and real recording alignment have not been established. Native demo footage is illustrative.

The owner explicitly requested **fully automatic device-clock synchronization**, with no sync button or manual time/timezone controls. The native app uses `Date()` and `TimeZone.current` after the recorder is identified, and observes significant clock/timezone changes. Existing files retain their original dates. A legacy HTTP acknowledgement is not treated as a verified recorder-clock reading.

The owner also requested remembered Wi-Fi and a Git repository with ongoing comments. The native app stores the exact SSID/address in app preferences and the password in a device-only Keychain item. No actual network credentials have been seeded into this project; setup requires the owner's exact SSID and password once. Automatic joining remains subject to iOS permission and app lifecycle constraints.

The first SwiftUI build is in `ios/`. It includes a local Files importer, AVPlayer playback, persistent clip metadata, an identity-checked legacy UTR 2.0 adapter, automatic clock requests, and sensor write/save/read-back. Real RTSP decoding and recorder downloads are not integrated yet. Unit tests cover recovered request framing, clock offset formatting, device/address rejection, strict filename dates and independent corrections. Simulator build and UI checks are separate from real hardware validation.
