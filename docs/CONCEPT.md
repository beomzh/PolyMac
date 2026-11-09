# PolyMac concept & goals

**English** · [한국어](CONCEPT.ko.md)

## 1. One-line concept

**"The small macOS utilities you reach for every day, in one lightweight menu bar app."**
Poly (many) + Mac. Many tools in one app, split into modules — and the modules you don't use never load.

## 2. Core principles

1. **One entry point** — one menu bar icon, one Settings window, one place to manage shortcuts (with automatic conflict detection).
2. **Zero when unused** — disabled modules don't load their code, and rarely used modules run as a separate process only when opened.
3. **An unbroken flow** — capture → pin → markup → OCR → clipboard continues on one screen. This used to mean juggling three apps.
4. **Make it visible** — always show what is going on, like files waiting to be cut or files left behind after uninstalling an app.
5. **Make it undoable** — deletes go to the Trash, moves are done in a way Finder's undo (`⌘Z`) works with.
6. **Never leave your Mac** — no network or telemetry, no recorded key presses, no disabling SIP or code injection. Detailed rules in [SECURITY.md](SECURITY.md).
7. **Public APIs first, private APIs opt-in** — private APIs sit behind feature flags, and the app must not crash if they disappear.

## 3. Goals / non-goals

### Goals
- Good enough to replace Spectacle, TRex, Snipaste (core features), AppCleaner, OpenInTerminal and Maccy
- Korean file names sent from a Mac don't break on other OSes (no decomposed Korean)
- Idle memory < 40 MB, idle CPU 0%, battery impact "Low"
- Korean OCR quality good enough for real use (Apple Vision on-device, no network)
- Distributed through GitHub Releases, ready to use (checksums provided, not notarized — not in the paid developer program), later a personal Homebrew tap

### Non-goals (won't do)
- Mac App Store distribution — inside the sandbox, the Accessibility API, event taps and organizing other apps' files are practically impossible
- A tiling window manager (automatic layouts like yabai/Aerospace) — a different product
- A launcher/command palette like Raycast — possible, but it would blur the focus (to be reconsidered after v1)
- Cloud upload/sync — everything is processed locally

## 4. Feasibility by feature

Legend: [Feasible] public APIs are enough · [Caution] possible but with pitfalls · [Experimental] private/experimental APIs · [Not feasible] not realistic

### 4.1 Window layout (replaces Spectacle) — Feasible

- **How**: change the focused window's position and size through the Accessibility API (`AXUIElement`). **Rectangle (MIT)**, Spectacle's successor, works the same way, so its structure can be studied directly.
- **Pitfall**: some apps (Electron, terminals) "bounce" after resizing → correct it the way Rectangle does, applying in two steps (size → position → size).
- **Reality check**: macOS 15 added built-in window tiling, but it lacks custom shortcuts, ⅓ splits and moving to the next display → still worth it.
- **Private API (opt-in)**: "send a window to the next desktop (Space)" with the `CGSSpace*` family. Only what works without disabling SIP.

### 4.2 Capture + pin + markup (replaces Snipaste) — Feasible / Caution

- **Capture**: `SCScreenshotManager` from `ScreenCaptureKit` (macOS 14+). The old `CGWindowListCreateImage` API is deprecated in macOS 15 and not used.
- **Area selection UI**: a transparent full-screen `NSPanel` overlay per display + automatic window edge detection (Snipaste's "auto window snap"), magnifier, pixel coordinates and color display.
- **Pins**: borderless `NSPanel`s at `.floating` level, with an option to show on all Spaces. Scroll to zoom, adjustable opacity, click-through mode.
- **Keeping markup editable (core requirement)**: markup is not burned into the bitmap but **stored as vector layers (shapes, text, arrows, mosaic)**. Reopening a pin lets you edit the markup. The storage format is a bundle of `original PNG + annotations.json`.
- **Pitfall**: since macOS 15, apps with Screen Recording permission get **periodic re-approval prompts**. There's no way around it with public APIs; the system `SCContentSharingPicker` reduces the prompts but doesn't fit the "capture an area instantly" UX → handled with first-launch documentation.
- **Later (stretch)**: scrolling capture (stitching long pages), GIF recording.

### 4.3 OCR automation (replaces TRex) — Feasible

- **Engine**: Apple Vision `RecognizeTextRequest` (Swift API, macOS 15+) / `VNRecognizeTextRequest`. Supports Korean, on-device, no extra model downloads. TRex uses the same engine.
- **macOS 26 and later**: `RecognizeDocumentsRequest` recognizes **table and paragraph structure** → tables can be copied as TSV/Markdown.
- **Automation rules** (the key to "working well"):
  - OCR right after capture → clipboard (a toast previews the result; click to edit)
  - Line break options: join paragraphs / keep the original lines
  - An open button if the result is a URL; extract the contents of QR codes and barcodes (`DetectBarcodesRequest`)
  - Whitespace preservation mode when it looks like a code block
  - Language priority (ko → en), a custom word list (`customWords`) to improve proper nouns
  - Select text by dragging on a pin (VisionKit `ImageAnalysisOverlayView` = Live Text)
  - Optional: on-device translation (`Translation` framework, macOS 15+)
  - Exposed to Shortcuts and a URL scheme → callable from other automation
- **Reality check**: handwriting, low resolution and small text lower the quality → offer an option to upscale the capture 2x before recognizing.

### 4.4 Finder cut — Feasible / Caution

macOS today: `⌘C` then `⌘⌥V` does "move", but ① you can't see what was cut, ② `⌘X` doesn't work, and ③ there's no way to send files straight to a folder of your choice.

- **Approach A — key remapping (recommended)**: with a `CGEventTap`, only while Finder is frontmost
  - `⌘X` → send `⌘C` instead, record the "cut pending" state + show the pending files in a HUD
  - `⌘V` while pending → send `⌘⌥V` instead
  - **Advantage**: Finder does the actual move, so **Finder's `⌘Z` undo, conflict dialogs and progress display all keep working**.
- **Pitfall**: `⌘X` must not be touched while a file name is being edited (a text field has focus) → check through AX whether the focused element's role is `AXTextField` and pass it through.
- **"Send to folder"**: register a list of favorite folders → move or copy the selected files instantly with a shortcut or menu. The selection is fetched through Apple Events (`tell application "Finder" to get selection`) → needs the **Automation (Apple Events) permission**.

### 4.5 Finder: open terminal / copy path — Feasible

- **How**: a **Finder Sync Extension** → a Finder toolbar button + right-click menu ("Open Terminal Here", "Copy Path", "Open in VS Code").
- Terminal choice: Terminal / iTerm2 / Ghostty / Warp. Reference: **OpenInTerminal (MIT)**.
- Path formats: absolute / `~` shortened / quoted and escaped / one per line for several.
- **Note**: macOS already has `⌥⌘C` (copy path) — still worthwhile if menu integration and format choice are needed. The docs mention the built-in shortcut too.
- **Pitfall**: the user has to turn on Finder Sync extensions in System Settings > General > Login Items & Extensions.

### 4.6 Complete app uninstall (replaces AppCleaner) — Feasible / Caution

The common complaint about AppCleaner is that you can't tell what is left behind, or where. So **grouping leftovers and showing the reason for each** is what sets this apart.

- **Search locations**: `~/Library/{Application Support, Caches, Preferences, Containers, Group Containers, Saved Application State, HTTPStorages, WebKit, Logs, LaunchAgents, Application Scripts}`, `/Library/{LaunchAgents, LaunchDaemons, PrivilegedHelperTools, Application Support}`, `pkgutil --pkgs` install receipts, login items/background items.
- **Confidence shown per matching reason**:
  - **Certain** — exact Bundle ID match (`com.foo.App`)
  - **Likely** — Team ID match, recorded in a pkg receipt
  - **Possible** — similar app name match → unchecked by default
- **UI**: a treemap/grouped list showing **size per kind**, like "Preferences 2 KB / Caches 1.2 GB / 1 background daemon running". A one-line "what is this" for every item.
- **Safeguards**: **move to Trash** instead of permanent deletion, system apps and running apps protected, export the list before deleting. Scanning for leftovers of apps already deleted (orphan files) is supported too.
- **Pitfall**: `Containers` and the like need **Full Disk Access**, and removing `/Library/LaunchDaemons` needs administrator rights (authentication dialog).
- **Module approach**: split into a separate app/process (`PolyMacUninstaller.app`) → runs only when opened from the menu, zero memory when closed.

### 4.7 Clipboard history (replaces Maccy) — Feasible / Caution

- **Watching**: compare `NSPasteboard.general.changeCount` every 0.5 seconds. macOS has no clipboard change notification, so every clipboard app, Maccy included, does this. It's a single integer comparison, so the CPU impact is too small to measure → the only polling PolyMac allows.
- **Storage**: SQLite (metadata and text) + images as separate files (original + thumbnail). Count and size limits, automatic cleanup of old items. All local, no network.
- **Features (Maccy level)**:
  - Global shortcut (default `⇧⌘V`) for a popup → type to search (fuzzy matching) → `Enter` to paste, `⌥Enter` to paste without formatting
  - **Pin** items — often-used text is exempt from cleanup, with number shortcuts
  - Text, RTF, images and file references, image previews
  - Per-app exclusion rules + pause recording for a while
- **Benefits of being inside PolyMac**:
  - **Source tags** on items: "OCR (capture #12)", "Path copy", "Capture image" → jump back to the capture pin
  - Text normalized to NFC when stored (4.8) → no decomposed Korean when pasting
- **Privacy (defaults matter)**:
  - Items marked `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType` are not stored (1Password, Bitwarden and others mark password copies this way)
  - Keychain Access and password manager apps are on the default exclusion list
- **Pitfalls**:
  - macOS 26 Spotlight added a built-in clipboard history → pins, exclusion rules and source links must be the difference.
  - Apple is moving toward **privacy alerts on programmatic clipboard reads** (user approval when reading what another app copied). Check the latest documentation for the exact timing and scope before implementing, and explain it in the permission dashboard.

### 4.8 Fixing decomposed Korean (NFD) — Feasible / Caution

**Cause**: macOS often creates file names in Unicode **NFD** (jamo spelled out separately, `ㅎ+ㅏ+ㄴ`), while Windows and most of the web expect **NFC** (the composed syllable `한`). So names of files sent, zipped or uploaded from a Mac show up as `ㅎㅏㄴㄱㅡㄹ` elsewhere. Finder shows both the same, so it's hard to notice.

The fix is to convert names to NFC before they leave the Mac, at every point where files come in:

| Path | How |
|---|---|
| New files | Watch chosen folders (default: Downloads, Desktop, the screenshot location) with **FSEvents** → rename NFD file names to NFC automatically. Event-based, so zero idle cost |
| Existing files | Finder right-click "Fix Korean Filenames" → convert a folder recursively, with a preview before changing |
| Archives | Finder right-click "Compress for Windows" → write file names inside the zip as NFC with the UTF-8 flag (macOS's built-in compression stores NFD) |
| Clipboard | Normalize copied text and paths to NFC (file names copied from Finder are often NFD) |
| Files PolyMac creates | Capture file names and the like are NFC from the start |

- **Implementation notes**:
  - Swift `String`'s `==` **treats NFD and NFC as equal** → whether something is NFD must be checked by comparing Unicode scalars.
  - APFS is a normalization-insensitive file system, so renaming `한.txt` (NFD) → `한.txt` (NFC) directly can fail with "already exists" → **rename in two steps through a temporary name**.
  - **Measured (macOS 26.6, APFS)**: `FileManager` and `URL` **decompose names back to NFD** when passing paths. Giving `FileManager.createFile` an NFC name still creates NFD on disk, and naming an NFC target with `moveItem` still leaves NFD → renaming must pass UTF-8 bytes directly to POSIX `rename(2)`.
  - `URL.lastPathComponent` also returns NFD → judge the real on-disk form only from the strings of `contentsOfDirectory(atPath:)`. Otherwise files that are already NFC keep getting renamed, which loops forever together with FSEvents.
- **Pitfalls**:
  - **HFS+ volumes** (old external disks, etc.) force NFD at the file system level → renaming is pointless. Detect and skip them, and point to "convert when compressing".
  - Inside `.app` bundles, git working folders and `~/Library`, renaming can break things → excluded by default. For git, suggest the `core.precomposeunicode` setting.
  - Changes in iCloud Drive/Dropbox folders spread through sync → excluded by default, only when the user explicitly turns them on.
  - Access to Downloads, Desktop and Documents triggers macOS's "Files and Folders" permission prompt.

### 4.9 Downloads auto-organize (replaces Hazel) — Feasible

Everyone organizes files differently, so this is **a rule engine you assemble yourself, not a fixed scheme**.

**Turning it on and off (3 levels)**
1. The whole module on/off — off stops watching and unloads it from memory
2. Per watched folder on/off — just Downloads, or Desktop too
3. Per rule on/off — rules can be paused without deleting them

**Rule = conditions + actions**

| Condition | Example |
|---|---|
| Extension | `pdf`, `hwp`, `docx` |
| File kind | image / video / audio / document / archive / installer / code (by UTType) |
| Name pattern | `*invoice*` (wildcard) or a regular expression |
| Source website | `github.com`, `*.go.kr` — the download source macOS records (`kMDItemWhereFroms`) |
| Size | over 100 MB / under 1 MB |
| N days since downloaded | 7 days after download |
| Not opened for N days | 30 days since last opened |
| Duplicate | a file with the same contents already exists in the same folder |
| NOT | invert one of the conditions above |

- Combining conditions: **all match (AND)** / **any matches (OR)**
- Rules are checked in order; each rule chooses "stop here / check the next rule too"

| Action | Example |
|---|---|
| Move / copy | `~/Documents/Received/{yyyy}-{MM}` |
| Rename | `{yyyy}{MM}{dd}_{name}` |
| Move to Trash | Permanent deletion is not supported |
| Finder tag | `Red`, `Work` |
| Notify only | Add to a "cleanup candidates" list without touching it |

Path and name template tokens: `{name}` `{ext}` `{kind}` `{domain}` `{yyyy}` `{MM}` `{dd}`

**Safeguards**
- When first turned on, **preview mode (dry-run)**: nothing is moved, only a list of "what would be organized" is shown
- Files still downloading (`.crdownload` `.download` `.part`) are ignored, and files are processed after a **wait** (default 10 seconds) once the download finishes
- No overwriting on name conflicts; `name (2).pdf` instead
- Every action is recorded with **undo**, and a notification says "where it was moved"
- Shares the FSEvents watch with the Korean filename module; the order is **NFC conversion → organize rules**

**Presets** (all shipped off, turn on the ones you want): installers to Trash after 7 days · documents into monthly folders · images into the Pictures folder · per-website folders · notify about files not opened for 30 days

Rules are stored as JSON and can be **exported/imported** to share with another Mac or other people.

### 4.10 Scope of "reverse engineering / private APIs" — Experimental

Only where it is actually worth it:

| Target | Use | Risk |
|---|---|---|
| `CGSSpace*` / SkyLight | Move windows to another Space, current Space info | Medium — can break with any OS update |
| `_AXUIElementGetWindow` | AX window ↔ CGWindowID mapping (useful for automatic window detection in capture) | Low — used by Rectangle and many others |
| Finder internal state | Current folder, selection | Public Apple Events are enough → no private API needed |

- Existing open source is studied for **architecture**, not "copied" (Rectangle's window math, Maccy's clipboard watching, Pearcleaner's leftover search rules, etc.). For licenses see [REFERENCES.md](REFERENCES.md).
- Closed-source apps like Snipaste, AppCleaner and Hazel are referenced **for UX only** (clean room); no decompiling or binary analysis. GPL and Commons Clause code is not copied either (the attribution policy in REFERENCES.md).
- Every private API call is loaded dynamically with `dlsym` and the feature is disabled on failure. The app must never crash.

## 5. Extra features worth adding

Not part of the original list, but they pay off well in an app that brings tools together:

| Feature | Why | Cost |
|---|---|---|
| **Unified shortcut manager** | The real benefit of merging tools. Conflict detection + warnings about clashes with system shortcuts | Low (part of the core) |
| **Screen color picker** | A popular Snipaste feature; the capture overlay already has the pixel data | Nearly zero |
| **Permission dashboard** | Accessibility/Screen Recording/Automation/Full Disk Access status at a glance, and why each feature needs it | Low |
| **Keep-awake toggle** | A few lines of `IOPMAssertion`. One less separate app (Amphetamine, etc.) | Nearly zero |

## 6. Success criteria (1.0.0)

- **Uninstall** Spectacle, TRex, Snipaste, AppCleaner and Maccy **and not miss them for two weeks**
- 100% of NFD file names arriving in Downloads converted to NFC, Korean file names correct in zips opened on Windows
- Idle memory 40 MB or less (Activity Monitor), energy impact "Low"
- Korean screenshot OCR accuracy: 95%+ on typical UI text (measured with our own sample set)
- From installing with the Homebrew cask to finishing permission setup in under 5 minutes
