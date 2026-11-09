# Roadmap

**English** · [한국어](ROADMAP.ko.md)

Each stage is done when "one existing app can be deleted".
For version numbering see [RELEASING.md](RELEASING.md) — each stage below maps to one MINOR version.

## 0.1.0 — Skeleton + window layout (replaces Spectacle)
- [x] Menu bar app (SwiftPM), Settings window (features, language, shortcuts, permissions), launch at login
- [x] PolyMacCore: ModuleRegistry, HotkeyCenter (conflict detection), permission guidance
- [x] WindowModule: ½ · ⅓ · ⅔, maximize, center, next display, undo
- [x] Edge-drag snapping: ½ · maximize · ¼ (off by default — overlaps with macOS window tiling)
- [x] Spectacle default shortcut preset (zero migration cost)
- [x] ¼ layout shortcuts (none by default — set them in Settings)

## 0.2.0 — Capture · pin · markup (replaces Snipaste)
- [x] Area selection overlay, automatic window detection, magnifier, color picker
- [x] Pins: zoom, opacity, show on all Spaces
- [x] Markup: rectangle, arrow, pen, text, mosaic, number stamp, **re-editable as vector layers**
- [x] Save/copy
- [x] Click-through pins, drag to export, recent capture history

## 0.3.0 — OCR automation (replaces TRex)
- [x] Capture → OCR → clipboard shortcut, result toast
- [x] Line break cleanup (keep / join into paragraphs / one line)
- [x] Small text boost (2x upscale) and symbol cleanup — decided by measurement (docs/OCR-BENCH.md)
- [x] Whitespace preservation: leading indentation (code, YAML, lists, measured in docs/OCR-BENCH.md) — language priority and a custom word list were measured to have no effect or make things worse, so they are not done
- [x] QR codes and barcodes
- [x] URL detection (open button in the notification, only on click), live text selection on pins
- [x] macOS 26+: table recognition → TSV/Markdown
- [x] `polymac://ocr` · `ocr-table` URL scheme (Shortcuts X-Callback, works only when allowed)
- [x] Actions listed in the Shortcuts app (App Intents — image and screen text, tables, Korean joining. Xcode builds only)
- [x] Korean OCR accuracy sample set + measurement script (`scripts/ocr-bench.sh`)

## 0.4.0 — Clipboard history (replaces Maccy)
- [x] changeCount polling + storage (JSON, images and large text in separate files), text, images, files
- [x] Popup, search, pinning
- [x] Ignore Concealed/Transient types, per-app exclusions, pause
- [x] Show source app
- [x] Encryption at rest (AES-GCM, key in the keychain)
- [x] RTF, paste without formatting, source tags (OCR, capture, path copy, color)
- [x] Jump to the capture pin

## 0.5.0 — Finder tools + Korean filename fix
- [x] `⌘X` / `⌘V` cut (inside Finder only)
- [x] Send to a chosen folder (move/copy)
- [x] Right-click (Services menu): open terminal (Terminal/iTerm2/Ghostty/Warp), copy path
- [x] Open in editor (`⌃⌥E`, right-click, editor app choice)
- [x] Cut pending indicator (count, cancel button, only while Finder is in front)
- [x] Automatic NFD → NFC conversion in watched folders (iCloud excluded)
- [x] Right-click "Fix Korean filenames" (after confirmation, including subfolders, bundles and .git excluded), "Compress for Windows"
- [x] Joining decomposed Korean in copied text (Korean letters only, passwords and file copies excluded)

## 0.6.0 — Downloads auto-organize (replaces Hazel)
- [x] Rule engine: conditions (extension, kind, name pattern, website, size, age, unopened, duplicate, NOT) × AND/OR × actions (move, copy, rename, tag, trash, notify)
- [x] On/off per module / watched folder / rule
- [x] Rule editor (reorder, add/remove conditions and actions, pick folders)
- [x] Drag to reorder
- [x] Template token autocomplete (example preview, typo marking)
- [x] Preview mode (dry-run), wait for downloads to finish, name conflict handling
- [x] History + undo, notifications
- [x] 5 presets
- [x] Rule JSON export/import (imported rules start off, files from newer versions rejected)

## 0.7.0 — Uninstaller (replaces AppCleaner)
- [x] UninstallerCore scanner + confidence rules + unit tests (fake Library tree)
- [x] Uninstall window (created only when opened): grouped by kind, sizes, descriptions, drag and drop apps
- [x] Move to Trash through Finder (Put Back and administrator password handled by Finder), quit running apps, unload background items
- [x] Scan for leftovers of apps already deleted (excluding existing executables and helpers in use)
- [x] Clean up install receipts (`pkgutil --forget`), export the list before deleting

## 1.0.0 — Release
- [x] Sparkle automatic updates (EdDSA signatures, works without notarization, off by default) + personal Homebrew tap (moved up to 0.2.0)
- [x] Permission dashboard (4 states, relaunch, clear permission records, alert when a permission is revoked), welcome guide
- [ ] Resource budget regression tests (CI)

## Later candidates
Keep awake · scrolling capture · GIF recording · moving between Spaces (private API, opt-in)
