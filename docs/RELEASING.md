# Versioning & release rules

**English** · [한국어](RELEASING.ko.md)

## 1. Version numbers — Semantic Versioning

Format: `MAJOR.MINOR.PATCH` (e.g. `0.3.1`), pre-releases `0.3.0-beta.1`

The current version comes from one file, [`VERSION`](../VERSION) at the repository root (single source of truth). Once there is an Xcode project, `MARKETING_VERSION` reads it from this file.

### Before 1.0.0 (now)

| Bump | When | Example |
|---|---|---|
| MINOR (`0.x.0`) | A [ROADMAP](ROADMAP.md) stage is finished, a new module is added, the settings format changes | `0.2.0` capture and pins added |
| PATCH (`0.x.y`) | Bug fixes, docs, performance (same behavior and settings format) | `0.2.1` multi-monitor coordinate fix |

- In 0.x the settings format may change. When it does, **always add an automatic migration** and note it under "Compatibility" in the release notes.

### After 1.0.0

| Bump | When |
|---|---|
| MAJOR | Settings or rule JSON compatibility breaks, **minimum macOS version goes up**, a module is removed, large changes to default shortcuts |
| MINOR | Features or modules added, a feature that needs a new permission (backward compatible) |
| PATCH | Bug and security fixes, docs |

### Build number
`CURRENT_PROJECT_VERSION` = `git rev-list --count HEAD` (an ever-increasing integer). macOS uses the build number to decide on updates even when the version string is the same.

### Settings file version
User data (rule JSON, the clipboard store, etc.) carries a `schemaVersion` integer separate from the app version. When the format changes, add 1 and keep code that reads and converts the previous version. If an imported JSON has a `schemaVersion` higher than the app's, it is not applied and the user is told to update.

## 2. Branches · tags

| Name | Purpose |
|---|---|
| `main` | Always builds. Release tags only from here |
| `feat/<module>-<description>` | Feature work (`feat/capture-pin`) |
| `fix/<description>` | Bug fixes |
| `docs/<description>` | Docs only |
| tag `vX.Y.Z` | Releases. **Annotated tags** only (`git tag -a`); a published tag is never moved or deleted |

- Urgent fixes branch off `main` as `fix/`, then ship as a PATCH release.
- Commit message rules are in [CONTRIBUTING.md](../CONTRIBUTING.md).

## 3. Change records — keep two kinds apart

| File | Audience | Content | When |
|---|---|---|---|
| [`CHANGELOG.md`](../CHANGELOG.md) | Developers | Detailed per-commit history (by file and function) | Added at the top with every commit |
| GitHub Release notes | Users | A few lines on "what got better" plus compatibility and permission changes | When creating a tag |

CHANGELOG entry format (in English from 0.2.15 on; older entries are in Korean):

```
[YYYY-MM-DD HH:MM]
- [Added|Changed|Fixed|Removed|Security] - <file path>: <what and why>
```

Release notes template:

```markdown
## PolyMac X.Y.Z

### New features
- ...

### Improvements · fixes
- ...

### Compatibility      ← settings format, minimum macOS, default shortcut changes ("None" if none)
### Permission changes ← newly requested permissions ("None" if none)
### Security           ← security fixes (omit if none)
```

## 3-1. Finding what changed in each version

The same information is available at three levels of detail.

| What you want to see | Where |
|---|---|
| What changed for users in this version (a few lines) | That version's notes in GitHub Releases |
| Every development change in this version (by file) | That version's section in `CHANGELOG.md` |
| The code difference between two versions | `git log v0.1.0..v0.2.0`, GitHub's `compare/v0.1.0...v0.2.0` |

**CHANGELOG version section rule** — entries pile up at the top with every commit, so at release time put a version line **above** the entries collected since the last release.

```
## 0.2.0 (2026-11-10) — from this line down to the 0.1.0 line is what went into 0.2.0
[2026-11-09 18:20]
- [Fixed] - ...
...
## 0.1.0 (2026-10-30)
...
```

Entries above the topmost version line are changes that haven't been released yet.

## 4. Release steps (checklist)

1. **Check the scope** — the ROADMAP stage's checkboxes are done; move unfinished items to the next version
2. **Verify**
   - [ ] `swift build && swift test` pass (needs Xcode)
   - [ ] Manual check after building the app: that version's modules work, guidance shows when permissions are missing
   - [ ] Resource budget: idle memory < 40 MB, idle CPU 0% (Activity Monitor)
3. **Security** — per [SECURITY.md](SECURITY.md)
   - [ ] Zero outside network connections while idle and while using features (`nettop -p PolyMac`)
   - [ ] `secret-scan` passes (no hardcoded paths or keys)
   - [ ] When adding a dependency, `dependency-audit` + update [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)
4. **Bump the version** — edit `VERSION`, add the version line at the top of `CHANGELOG.md` (3-1), update the current version line in both READMEs (`README.md` and `README.ko.md`), merge as a PR `chore(release): X.Y.Z`
5. **Tag**
   ```bash
   git tag -a vX.Y.Z -m "PolyMac X.Y.Z"
   git push origin main --tags
   ```
6. **Build · sign · package** — on the tagged main
   ```bash
   scripts/package-release.sh
   ```
   - Signs with the fixed certificate (a self-signed certificate whose name starts with `PolyMac `). It must be the same certificate every time so that users' macOS permissions (Accessibility, Screen Recording) survive updates. Choose one with `POLYMAC_SIGN_IDENTITY`.
   - The release certificate is `PolyMac Beomzh` (self-signed, 10 years, backup at `~/Documents/PolyMac-signing.p12`), made with `scripts/make-signing-cert.sh`. `Apple Development` is not used: its signature reveals an email, real name and team ID (`codesign -dvv`), it expires every year, and without a timestamp it can look invalid to new downloaders after it expires.
   - A self-signed certificate **can't be recreated if it is lost** — updates signed with a new certificate are treated as a different app, and every user has to grant permissions again. Keep the `.p12` backup somewhere safe outside the repository.
   - **No notarization** (not in the Apple Developer Program). The Hardened Runtime stays on. The receiving Mac doesn't know a self-signed certificate, so Gatekeeper blocks the app as "damaged" (with no Open Anyway). Downloaders need `xattr -dr com.apple.quarantine` once — README "If macOS blocks the first launch" — and the Homebrew cask does this for them in its post-install step (`postflight_steps`).
   - The script only packages when VERSION is not a pre-release (`-alpha` etc.), the working tree is clean, and the `vX.Y.Z` tag is on HEAD.
   - The zip carries no extended attributes (`ditto --norsrc --noextattr`). With them, `._` files appear inside the app and break the signature for people who unpack with `unzip`. After packaging, the script unpacks with `unzip` and checks the signature again.
7. **Release files** — `build/release/PolyMac-X.Y.Z.zip` + `.zip.sha256`
   ```bash
   gh release create vX.Y.Z build/release/PolyMac-X.Y.Z.zip build/release/PolyMac-X.Y.Z.zip.sha256 --title "PolyMac X.Y.Z" --notes-file notes.md
   ```
   - Upload `appcast.xml` too — the app reads `releases/latest/download/appcast.xml`, so it must be attached to **the most recent release**.
8. **Homebrew** — change `version` and `sha256` (printed by the script) in `packaging/homebrew/polymac.rb` and commit, then push the same file (without the description comment at the top) to `Casks/polymac.rb` in the personal tap repository [`beomzh/homebrew-tap`](https://github.com/beomzh/homebrew-tap). Since Homebrew 7, users need `brew trust --cask beomzh/tap/polymac` before installing (explained in the README). The official cask repository doesn't accept apps that aren't notarized.

### Update signing key (Sparkle EdDSA)

Create it once, by hand, on the Mac that publishes releases (the private key goes into the login keychain):

```bash
scripts/fetch-sparkle.sh && Vendor/Sparkle/bin/generate_keys
```

Put the printed public key in `App/sparkle-public-key.txt` and commit it. The update feature is only built in when this file exists.

- If the private key is lost, updates can no longer be sent to apps already released — export it with `generate_keys -x <file>` and keep it somewhere safe outside the repository.
- `package-release.sh` checks that the key in the keychain matches `App/sparkle-public-key.txt` before signing the zip.

### Bumping versions (since 0.2.0)

- Every task (PR) bumps `VERSION` by one PATCH step (0.2.1, 0.2.2, …). No tags are made along the way.
- A version is tagged and released only when it is shipped to users. Versions without a tag and release get no Sparkle or Homebrew update.
- Release notes cover the changes of every version since the last release.

## 5. Support policy

- **Minimum macOS**: 14 Sonoma. Raising it is only done as a MINOR change in 0.x and a MAJOR change after 1.0.
- If a new feature needs a newer OS (e.g. macOS 26 table recognition), wrap it in `if #available` and hide the menu item on older versions.
- Security fixes go only into the latest MINOR (no backports to older versions).
