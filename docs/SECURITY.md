# Security principles

**English** · [한국어](SECURITY.ko.md)

This app assumes it **works only inside your own Mac**. It gathers powerful features in one place — Accessibility, Screen Recording, the clipboard, moving files — so a single hole would do a lot of damage. The principles below take priority over features.

## 1. Network: none by default
- OCR (Vision), translation (Translation), file organizing and the clipboard are **all on-device**, with no calls to outside servers.
- Text to translate never leaves the device. The first time, if the language model is missing, macOS asks whether to download it, and a system service does the download (PolyMac does not connect itself). Logs keep only the languages, character count and time taken, never the text.
- **No** telemetry, analytics or crash uploads.
- Exception: automatic updates (Sparkle 2.10.0) — **off by default.** Only when you click "Check for Updates…" in the menu or turn on automatic checks (once a day) in Settings does it read
  `https://github.com/beomzh/PolyMac/releases/latest/download/appcast.xml`.
  - Sending device info (`SUEnableSystemProfiling`) is off, automatic install (`SUAutomaticallyUpdate`) is off — it always asks before installing.
  - A downloaded zip is extracted only if its EdDSA signature matches `SUPublicEDKey` in Info.plist (`SUVerifyUpdateBeforeExtraction`). The private key exists only in the publisher's keychain.
  - Builds without the public key (`App/sparkle-public-key.txt`), i.e. your own builds, don't start the update feature.
- Check: before a release, confirm zero outside connections with `nettop`/Little Snitch while idle and while using features.

## 2. Input monitoring (event taps)
- Key presses are **used in memory only to match shortcuts** and are never written to disk or logs (so it can't become a key logger).
- Except for the Finder `⌘X` remapping, it uses **listen-only taps** that can't modify events.
- The event tap only does meaningful work when Finder is frontmost and passes everything else through at once.
- **An active event tap sits in the path of every key press on the Mac**, so if its callback blocks, system typing stops. Therefore
  - the tap runs on a **dedicated thread**, not the main thread (the main thread can briefly block on AppleScript, menus and modals).
  - Accessibility calls inside the callback that ask another app get a **0.1-second timeout** (default 6 seconds). If it can't confirm, it passes the event through untouched.
  - the callback never waits on the main thread (the frontmost app is tracked in advance from activation notifications).
  - key events PolyMac sends itself are marked so its own tap doesn't intercept them again.

- The global key monitor (`Esc` to cancel a capture or close a pin) is installed **only while capturing or while a pin is open**, and ignores every key except `Esc`.

## 2-1. Windows that cover the screen
- A **window that covers the whole screen, like capture area selection, must always be escapable**: `Esc` regardless of focus, right-click, automatic cancel when the screen layout changes, and automatic cancel after 60 seconds.
- Work that synchronously asks other apps or Finder (AppleScript and the like) is never done on the main thread.

## 3. Clipboard history
- `ConcealedType`/`TransientType` items and password manager apps are not recorded (default).
- Stored in `~/Library/Application Support/PolyMac/` — directory `0700`, files `0600`. Images are stored separately as PNG in `clipboard-images/` (`0600`).
- **Encryption at rest**: the list (`clipboard.json`), images and long text files are sealed with AES-GCM (256-bit) (`SealedFiles`, file header `PMS1`). File permissions alone don't stop programs running as the same user, so the key lives in the **keychain** (generic password item, `dev.polymac` / `clipboard-history`, this device only) and no plaintext key is kept on disk. Only an app with the same signature as the one that created the item can read it without asking.
  - If the key can't be read (keychain locked or access denied), it **does not create a new key** — that would make the old history unreadable forever. For that run nothing is written to disk; history stays in memory only (never written in plaintext either).
  - The key is read in the background. Even while the keychain shows its prompt and waits for an answer, app launch and other features don't stall. Anything copied while waiting stays in memory only (no disk writes — so the saved history isn't overwritten by a short list), and once the key arrives the saved history is opened and the new items are added on top.
  - A list that can't be opened is not deleted but moved to `clipboard.unreadable-<time>.json`.
  - Plaintext files from before encryption are sealed and rewritten once on first run. On APFS/SSD old blocks may remain, so disk-level protection is left to FileVault.
- **Kept for 7 days by default** plus a limit on the number of items (pinned items excluded). When an item is deleted, its separately stored image or text file is deleted right away too.
- Size limit per item: text 20 MB (over 64 KB goes to a separate file), images 30 MB.
- "Pause recording" and "Clear history (except pinned)" menu items are provided.
- **The clipboard is rewritten in only one place** — when Korean filename fix (Normalize) joins decomposed Korean letters back into composed syllables. It only changes how letters are combined (not a full NFC pass), and leaves concealed or transient items and Finder file copies alone. If another app copied something new in the meantime, it doesn't overwrite it. The contents are never stored or logged.
- The Finder cut pending indicator only looks at the clipboard change count and the **number** of files (it doesn't read names).

## 4. File operations (Korean filename fix · auto-organize · cut · app uninstall)
- **No permanent deletion** — every delete goes to the Trash (`FileManager.trashItem`).
- **No overwriting** — on a name conflict, `name (2)`.
- File name and domain values inserted into templates have `/`, `:` and `..` replaced, so **paths can't escape** (RuleEngine.render).
- The result of a rename action must be a **single-level file name**, and the executor resolves the move destination with `realpath` and checks that it is under the user's home.
- **Symbolic links pointing outside the watched folder are not followed**.
- Every operation leaves a record (log + undo list).

## 5. Administrator privileges (Uninstaller)
- **No resident privilege escalation helper (PrivilegedHelperTool / SMJobBless) is installed.** Full Disk Access is not required either.
- PolyMac doesn't delete files itself; it **asks Finder to move them to the Trash** — so "Put Back" works, and for items under `/Library` Finder asks for the administrator password only then.
- Paths are **passed as arguments**, not spliced into AppleScript strings (so file names containing quotes, `&` and the like can't tamper with the script — verified).
- It only searches a fixed set of Library folders, and excludes macOS's own apps (`com.apple.*`, `/System`) and PolyMac itself.
- "Leftovers of apps already deleted" excludes background services whose executables still exist and files used by registered services, so things like security software installed without an app aren't broken.

## 6. Private APIs · other processes
- **No feature requires disabling SIP** (no code injection into other processes like yabai's scripting addition).
- Private APIs are called through `dlsym`, mostly read-only; on failure the feature is disabled.
- No code injection into other apps, no `DYLD_INSERT_LIBRARIES`, no debugger attach.

## 7. Ways to call the app from outside
- The URL scheme (`<app>://`) and Shortcuts actions expose **only read/create operations** (e.g. run OCR, start a capture).
  - Shortcuts app actions (App Intents) can only be called from shortcuts the user made or from Spotlight, not from web pages, so they don't need a separate opt-in. Results are returned only to the shortcut, the clipboard is left alone, and they refuse if the feature is turned off.
  Moving or deleting files and changing settings can't be done through outside calls — this stops web pages from driving the app through links.
- Imported settings or rule JSON is validated and applied **only in preview mode**.
- Web addresses found in recognized text (OCR, QR) are **never opened automatically.** The notification only shows a button with the host that would actually open, and it opens only when the user clicks (http and https only, up to 3).

## 8. Build · signing
- Hardened Runtime on, no unnecessary entitlements.
- `com.apple.security.cs.disable-library-validation` — on since 0.2.0 (decided 2026-11-02). It's needed to load the Sparkle.framework inside the app:
  library validation only loads code "signed with the same team ID", and a self-signed certificate has no team ID, so it's blocked even when signed with the same certificate.
  - Effect: libraries inside the app bundle (in `/Applications`, writable only by administrators) are loaded without a team ID check.
  - Unchanged: injection through environment variables like `DYLD_INSERT_LIBRARIES` is still blocked (no `allow-dyld-environment-variables`), runtime code modification is blocked, and app and framework signatures are checked.
  - If the project joins the Apple Developer Program and signs with a team ID, this entitlement will be removed.
- First launch on another Mac: the receiving Mac doesn't trust a self-signed certificate, so Gatekeeper blocks the app as "damaged" (the signature itself is valid — `codesign --verify`).
  - Downloaded zip: the user checks the sha256 and opens it themselves with `xattr -dr com.apple.quarantine`.
  - Homebrew cask: the post-install step (`postflight_steps`) removes the download flag (decided 2026-11-02). This applies only to people who trusted this cask with `brew trust`, and only to the app installed from the zip whose sha256 Homebrew checked against the cask. It skips macOS's first-launch check to that extent.
  - Sparkle updates: Sparkle removes the flag after checking the EdDSA signature.
- Release builds don't keep rpaths pointing outside the app (the Xcode toolchain path of the build Mac) — `build-app.sh` removes them.
- Personal builds are signed with a **fixed self-signed certificate** — ad-hoc signatures change with every build, which resets TCC permissions (Accessibility and others) every time, and training people to re-grant permissions is itself a risk.
- Keep external dependencies to a minimum (currently 1: Sparkle). Version and checksum pinned (`scripts/fetch-sparkle.sh`) plus `dependency-audit`.
- `secret-scan` before committing.

## 9. Only the permissions needed
- When a module is turned on for the first time, request only the permissions that module needs. When a module is turned off, explain how to revoke its permissions.
- Full Disk Access only for the separate Uninstaller app — never requested by the main app.
