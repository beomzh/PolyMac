# References

**English** · [한국어](REFERENCES.ko.md)

> Licenses are the values **checked directly in each repository on 2026-10-27**. Check again at the time you actually bring in code.

## Attribution policy

This document exists **for transparency, not as a legal obligation**. Making public what was referenced and how prevents misunderstandings about "copying" and gives a record if a problem ever comes up.

| Kind of reference | Allowed | What to do |
|---|---|---|
| Referencing ideas, feature sets, UX flows | Yes | Copyright protects **expression (code, images, text)**, not ideas → no obligation. Just record the source in this document |
| Apple's public documentation and API usage | Yes | No obligation |
| Bringing in part of MIT-licensed code | Yes | Include the original copyright notice and the full license in `THIRD_PARTY_NOTICES.md`, plus a source comment at the top of the file |
| Using an external library as a dependency | Yes | Same as above (`THIRD_PARTY_NOTICES.md`) |
| Copying GPL code (Ice, etc.) | No | Copying would require all of PolyMac to be GPL → look at the structure only and write it yourself |
| Copying Commons Clause code (Pearcleaner) | No | It carries a "no selling" condition → reference only **facts** like the list of search locations, write the code yourself |
| Decompiling or analyzing binaries of closed-source apps | No | Most EULAs forbid it → reference only the behavior visible on screen (UX) |
| Other apps' icons, names, screenshots, text | No | Copyright and trademark issues. Use only what you made |
| Descriptions like "a Snipaste replacement" | Yes | Mentioning a name for comparison is generally fine, as long as it doesn't look affiliated or official |
| Calling macOS private APIs | Caution | Common for use on your own Mac. Don't copy or redistribute Apple code or headers; reference signatures only at the level declared in public open source (yabai, etc.) |

> This follows common open-source practice and is not legal advice. If there are ever plans to commercialize or ship under a company name, get an expert's check at that point.

## Open source studied for architecture

| Project | What to look at | License (checked 2026-10-27) | Bringing in code |
|---|---|---|---|
| Rectangle (rxhanson/Rectangle) | Window position math, AX resize correction, Spectacle shortcut compatibility | MIT | Allowed (attribution needed) |
| Spectacle (eczarny/spectacle) | The original shortcut scheme (archived in 2022) | MIT | Allowed (attribution needed) |
| TRex (amebalabs/TRex) | Vision OCR pipeline, capture → text flow | MIT | Allowed (attribution needed) |
| OpenInTerminal (Ji4n1ng/OpenInTerminal) | Finder Sync extension, how each terminal is launched | MIT | Allowed (attribution needed) |
| Maccy (p0deje/Maccy) | Clipboard polling loop, storage layout, search UI, list of pasteboard types to ignore | MIT | Allowed (attribution needed) |
| KeyboardShortcuts (sindresorhus) | Shortcut registration and recording UI | MIT | Dependency candidate |
| Sparkle | Automatic updates (public release builds only) | MIT family (bundled third-party code has its own licenses) | Dependency candidate |
| Pearcleaner (alienator88/Pearcleaner) | Leftover search locations and matching rules | Apache 2.0 + Commons Clause | Not allowed, ideas only |
| Ice (jordanbaird/Ice) | Menu bar app structure, permission handling UX | GPL-3.0 | Not allowed, ideas only |

## UX reference only (closed source)

- **Snipaste** — automatic window detection, pins, markup toolbar layout
- **CleanShot X** — floating preview after capture, scrolling capture
- **AppCleaner** — drag-and-drop uninstall flow (and a lesson in what not to do: lists without reasons)
- **Hazel** — folder watching plus condition/action rules

## Apple public APIs

- ScreenCaptureKit — `SCScreenshotManager`, `SCShareableContent`
- Vision — `RecognizeTextRequest`, `RecognizeDocumentsRequest` (macOS 26), `DetectBarcodesRequest`
- VisionKit — `ImageAnalyzer`, `ImageAnalysisOverlayView`
- Accessibility — `AXUIElement`, `AXIsProcessTrustedWithOptions`
- Quartz Event Services — `CGEvent.tapCreate`
- FinderSync — `FIFinderSync`
- Translation (macOS 15+)

## Clipboard · Unicode

- nspasteboard.org — conventional types for clipboard managers such as `org.nspasteboard.ConcealedType`
- Unicode UAX #15 (Normalization Forms) — definition of NFC/NFD
- FSEvents (`FSEventStreamCreate`) — watching folders for changes

## Private API notes

- `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, `CGSAddWindowsToSpaces` and others — signatures can be found in the yabai and Amethyst sources
- `_AXUIElementGetWindow` — AX window → `CGWindowID`
- All loaded at runtime with `dlsym`; the feature is disabled on failure. Re-check on every major macOS update.
