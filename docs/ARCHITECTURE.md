# PolyMac architecture

**English** · [한국어](ARCHITECTURE.ko.md)

## 1. Overall structure

```
┌─────────────────────── PolyMac.app (menu bar, LSUIElement) ────────────────────────┐
│  PolyMacCore                                                                       │
│   ├─ ModuleRegistry   : registers and enables modules (lazy init per settings)     │
│   ├─ HotkeyCenter     : global shortcuts + conflict check (RegisterEventHotKey)    │
│   ├─ EventTapHub      : one CGEventTap shared by all modules (more taps add lag)   │
│   ├─ PermissionCenter : Accessibility / Screen Recording / Automation / Full Disk  │
│   └─ Settings / Log   : UserDefaults + os.Logger (per subsystem)                   │
│                                                                                    │
│  Resident modules (in-process, created only when turned on)                        │
│   ├─ WindowModule    : moves and resizes windows via AXUIElement                   │
│   ├─ CaptureModule   : overlay, pins, markup ──→ OCRModule (loaded on first use)   │
│   ├─ FinderModule    : ⌘X remapping, send to folder                                │
│   ├─ ClipboardModule : history, search, pins (encrypted JSON + image files)        │
│   ├─ NormalizeModule : FSEvents → NFD file names to NFC, clipboard cleanup         │
│   └─ OrganizeModule  : same FSEvents events → user rules → move / tag / trash      │
└────────────────────────────────────────────────────────────────────────────────────┘
        │ App Group (shared settings)   │ runs only when opened (NSWorkspace.open)
        ▼                               ▼
┌─ PolyMacFinderSync.appex ───┐         ┌─ PolyMacUninstaller.app ────────────┐
│ Finder toolbar / right-click│         │ separate process, quits on close    │
│ (open terminal, copy path)  │         │ scanner + results UI; admin work    │
│ process managed by Finder   │         │ via a one-time auth dialog          │
└─────────────────────────────┘         └─────────────────────────────────────┘
```

## 2. Module design

### 2.1 Why not "dynamically loaded plugins (.bundle)"

A plugin structure that loads `.bundle`s at runtime is possible on macOS, but:
- under the Hardened Runtime (library validation), loading bundles with a different signature is blocked (`library validation`) or needs an exception entitlement → weaker security
- a Mach-O that has been loaded effectively can't be unloaded → "zero memory when off" can't be reached

So PolyMac **mixes two approaches**:

| Approach | Used for | When off |
|---|---|---|
| **Compiled in + lazy activation** | Frequently used, lightweight modules (Window, Capture, Finder, OCR) | No objects created; code pages stay on disk and barely load into memory |
| **Short-lived worker process** | Work that loads large models: OCR text and table recognition (`OCRWorker`) | The worker exits 60 s after its last request, and the model memory goes back to the system |
| **Separate process (on demand)** | Heavy, rarely used modules (Uninstaller, later recording, etc.) | No process at all = truly zero |

### 2.2 Module contract

```swift
public protocol PolyMacModule: AnyObject {
    static var descriptor: ModuleDescriptor { get }   // id, name, required permissions, residency
    init(context: ModuleContext)                      // shared services (shortcuts, event tap, log) injected
    func activate() throws
    func deactivate()
}
```

- Modules don't reference each other directly. Where one needs another, like Capture → OCR, they connect by looking up a service in `ModuleContext` (if OCR is off, only the OCR button is hidden).
- Each module is a separate Swift Package target → per-module unit tests and clear build boundaries.

## 3. Resource budget

| Item | Target | How |
|---|---|---|
| Idle memory | < 40 MB | SwiftUI only in the Settings window; menu bar and overlays in AppKit. Capture buffers freed as soon as the pin closes |
| Idle CPU | 0% | No timer polling. Only shortcuts, event taps and NSWorkspace notifications |
| Event tap latency | < 1 ms | The tap callback only compares key codes; heavy work goes to the main queue asynchronously |
| OCR | < 500 ms | Vision requests on a background queue, `.accurate` by default / `.fast` as an option |
| Clipboard history | Negligible watching cost, storage capped at 200 MB by default | Checking `NSPasteboard.changeCount` is unavoidably periodic (0.5s) → the only exception to the no-polling rule. Popup UI created only when opened, only thumbnails of images in memory |
| Filename normalization | 0% idle | FSEvents callbacks (batched with a 1s delay), watched folders only |
| Auto-organize | 0% idle | Shares the FSEvents stream with Normalize. Rule evaluation reads only file metadata; duplicate checks (hashes) only among files of the same size |

Measurement plan: watch for regressions with `Instruments` (Allocations, Energy Log) and a memory snapshot script in CI.

### Measured (2026-11-04, Apple M3, 16 GB, macOS 26.6.2)

The table above lists targets. Memory is phys_footprint (the "Memory" column in Activity Monitor); OCR is `scripts/ocr-bench.sh --budget`.

| Item | Target | Measured | Result |
|---|---|---|---|
| Idle memory after a fresh launch (2 min) | < 40 MB | 23 MB | Pass |
| Idle CPU (1-minute average) | 0% | 0.0% | Pass |
| Idle outside connections | 0 | 0 | Pass |
| OCR time (17 samples × 3, five 2560×1600 × 3) | < 500 ms | median 110–117 ms, max 406 ms, first run (model loading) 256–355 ms | Pass |
| Idle memory after real use | < 40 MB | 66 MB 5 minutes after launch, 191 MB after 22 hours (peak 386 MB) | **Over** |
| Memory after using OCR (separate process) | - | 6 MB → 174 MB, 80–119 MB after 30 seconds | The OCR model stays loaded |

**OCR worker (0.2.16).** Vision keeps its recognition model in the process that used it until that process ends — about +65 MB after one OCR and +154 MB after three, and freeing the heap (`malloc_zone_pressure_relief`) gives nothing back. So OCR text and table recognition now run in a worker: the app starts its own executable with `--ocr-worker`, passes the image as raw pixels over a pipe (never written to disk), and gets the text back. The worker stays for 60 seconds after its last request so repeated OCR doesn't reload the model, then exits. Measured with `ko-long` three times (2026-11-09, same Mac): the calling process grows 10 → 15 MB with the worker versus → 164 MB in-process; the worker itself is 152 MB until it exits. Live Text on pins (VisionKit `ImageAnalyzer`) already runs outside the app (+7 MB) and stays as is. Translation models live in the system service `translationd`.

Translation (en → ko, after the model is installed, separate process): 100 characters 165 ms, 500 characters 225 ms, 2,000 characters 702 ms. The calling process grows by +3 MB; the model is held by the system service `translationd` (199 MB, not counted in PolyMac's memory). The first run before the model is downloaded was not measured.

OCR time excludes area selection and writing to the clipboard. Event tap latency was not measured.

## 4. Permission map

| Permission | Modules that need it | Without it |
|---|---|---|
| Accessibility | Window, Finder (⌘X) | That feature is disabled + guidance |
| Screen Recording | Capture, OCR | No capture |
| Automation (Apple Events → Finder) | Finder (send to folder) | Only sending is disabled |
| Files and Folders (Downloads, Desktop, Documents) | Normalize, Organize | Those folders can't be watched → only other folders the user picks |
| Paste / clipboard access (future macOS policy) | Clipboard | History recording stops + guidance |
| Full Disk Access | Uninstaller | Some locations like `Containers` can't be scanned → shown as "locations not checked" |
| Administrator authentication (one-time) | Uninstaller (`/Library/LaunchDaemons` etc.) | Only those items are skipped |

**Principle**: request a permission when a module is first turned on, never all at once on the app's first launch.

## 5. Technology choices

| Area | Choice | Why |
|---|---|---|
| Language | Swift 6 (strict concurrency) | Access to system APIs, low resource use |
| UI | AppKit (overlays, pins, menu bar) + SwiftUI (Settings, Uninstaller) | AppKit is better for overlay latency and memory |
| Capture | ScreenCaptureKit | The old API is deprecated |
| OCR | Vision (+ VisionKit live text) | On-device, Korean, free |
| Shortcuts | Carbon `RegisterEventHotKey` | No permission needed, lightest option (KeyboardShortcuts library considered) |
| Automatic updates | Sparkle 2 | The standard for open-source apps |
| Distribution | Fixed-certificate signature + Hardened Runtime + GitHub Releases (zip, sha256), no notarization | No App Store (sandbox), not in the paid developer program — a downloaded zip needs its download flag removed once with `xattr` (self-signed, so it is blocked as "damaged"); the Homebrew cask does it automatically |
| Minimum OS | macOS 14 | ScreenCaptureKit screenshot API. Table recognition etc. behind `if #available(macOS 26, *)` |

## 5-1. Technology per module

No external libraries are used for features (Sparkle is the only dependency, for updates). Everything is an Apple framework that ships with macOS.

| Module | Core technology | What it does |
|---|---|---|
| Core | Carbon `RegisterEventHotKey`, AppKit `NSPanel`, FSEvents, `os.Logger`, ServiceManagement | Global shortcuts, toasts, folder watching, logging, launch at login |
| Window | Accessibility (`AXUIElement`) | Read and change the front window's position and size |
| Capture | ScreenCaptureKit (`SCScreenshotManager`), Core Graphics, `CGWindowListCopyWindowInfo` | Screen capture, window positions (automatic window detection), drawing the magnifier and marks |
| OCR | **Vision** `VNRecognizeTextRequest` + `VNDetectBarcodesRequest` | Text and QR recognition (below) |
| Clipboard | `NSPasteboard`, CryptoKit (SHA-256), ImageIO, SwiftUI, `NSTextView` | History, duplicate detection, thumbnails, window, long text preview |
| Finder | Quartz Event Tap (`CGEvent.tapCreate`), Accessibility, `osascript` (AppleScript) | ⌘X cut, Finder's current folder and selection |
| Normalize | Foundation (`precomposedStringWithCanonicalMapping`), POSIX `rename(2)`, FSEvents | Decomposed Korean (NFD) → NFC |
| Organize | UniformTypeIdentifiers, Spotlight `MDItem` (source website, last used), POSIX `rename` and `copyfile` | Evaluating and running rules |
| Uninstaller | Security (code signing team ID), `MDItem`, `libproc` (`proc_pidpath`), `lsof`, `launchctl`, Finder AppleScript, `NSWorkspace.recycle` | Finding leftovers, checking what's in use, moving to the Trash |

**OCR in detail** — it uses `VNRecognizeTextRequest` from Apple's **Vision** framework.
- A neural text recognition model built into macOS that runs **only on the device** (no network, no extra downloads). It's the same family as "Live Text" in Photos.
- Settings: recognition level `.accurate` (accuracy first), languages `["ko-KR", "en-US"]` (Korean first), language correction on
- `VNDetectBarcodesRequest` runs on the same image and QR and barcode contents go first
- Results are joined line by line, normalized to NFC and put on the clipboard
- Other macOS OCR apps like TRex use the same Vision engine. The difference is the capture flow and post-processing, not the engine
- Performance: about 0.9 seconds on the first run for a typical screen area (including model loading), faster afterwards

## 6. Repository layout

```
polymac/
├─ Package.swift              # module core (SwiftPM) — swift build / swift test
├─ Sources/
│  ├─ PolyMacL10n/            # picks the UI language L("한국어", "English") — no dependencies
│  ├─ PolyMacCore/              # module contract, registry, shared services
│  ├─ WindowModule/
│  ├─ CaptureModule/
│  ├─ OCRModule/
│  ├─ FinderModule/
│  ├─ ClipboardModule/
│  ├─ NormalizeModule/        # NFD → NFC logic (pure functions + renaming)
│  ├─ OrganizeModule/         # rule model (Codable), rule engine (pure functions), presets
│  └─ UninstallerCore/        # scanner logic (pure logic without UI → easy to test)
├─ Tests/
├─ App/                       # (planned) Xcode project: PolyMac.app, PolyMacFinderSync.appex, PolyMacUninstaller.app
└─ docs/
```

The Xcode project only handles **app bundles, extensions and signing**; all logic lives in the SwiftPM package. → Logic can be built and tested from the command line too.

## 6-1. UI language

- Text is written in both languages where it is used: `L("저장했습니다", "Saved")`. There is no separate translation key file, so no translations go missing, and `\(n)` interpolation works as usual.
- The language setting (`app.language`: system / ko / en) is changed in Settings › Language. "System" means Korean only when macOS's first language is Korean, English otherwise.
- When it changes, the enabled features are restarted (deactivate → activate) so shortcut names, menu items and windows are built in the new language. That's why text is never kept in a `static let` (it would stay stuck in the first language).
- The text macOS shows when asking for permissions (Info.plist) is in `App/en.lproj/InfoPlist.strings`. Only this follows the macOS language.
- When building a new feature: write every user-visible string with `L(…)`. Logs (`logger`) are not translated.

## 7. Logging

`os.Logger(subsystem: "dev.polymac", category: <module id>)`. Permission denials, event tap deactivation (when the system turns it off on a timeout) and private API load failures must always be logged at `error`/`fault`.

```bash
log stream --predicate 'subsystem == "dev.polymac"'
```
