# Contributing

**English** · [한국어](CONTRIBUTING.ko.md)

## Development environment

- macOS 14 or later, Apple Silicon recommended
- **Xcode 16 or later** — needed to run the tests and to build the Finder extension
  (with only the Command Line Tools, `swift build` and `scripts/build-app.sh` still build and install the app)
- Xcodes.app (a version manager) alone is not enough; install Xcode itself from it

```bash
git clone https://github.com/beomzh/PolyMac.git
```

```bash
cd PolyMac && swift build
```

```bash
scripts/test.sh
```

Bundle, install and run the app (works with only the Command Line Tools):

```bash
scripts/build-app.sh --install
```

## Where the code lives

- All logic lives in `Sources/<module>/` (SwiftPM). Keep the parts without UI as pure functions and test them in `Tests/`
- The app entry point and menu bar are in `Sources/PolyMacApp/`, bundle settings (Info.plist, entitlements) in `App/`, bundle assembly and signing in `scripts/build-app.sh`
- A new module follows the `PolyMacModule` protocol and is added to the `modules` array in `Package.swift`

## Workflow — branch + pull request

Never push directly to `main`. Every change is made on a branch and merged through a pull request (PR).

1. **Create a branch**
   - Outside contributors: fork the repository and branch in the fork
   - Maintainers: branch in this repository
   - Names: `feat/<module>-<description>`, `fix/<description>`, `docs/<description>`, `chore/<description>` (e.g. `fix/finder-cut-paste`)
2. **Work and commit** — follow the commit message rules below, with a `CHANGELOG.md` entry for each commit
3. **Open a PR** — against `main`. In the description, write
   - what changed and why, and how you checked it
   - any **new permissions** it needs (Accessibility, Screen Recording, …)
   - whether there is a migration, **if the settings format changes** ([docs/RELEASING.md](docs/RELEASING.md) 1)
   - screenshots if the UI changes
4. **Checklist** (same as the PR template)
   - [ ] `scripts/test.sh` passes
   - [ ] `swift build -c release` has no warnings
   - [ ] No violation of [docs/SECURITY.md](docs/SECURITY.md) (no network calls, stored key presses, permanent deletion or overwriting)
   - [ ] [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) updated if third-party code was added
5. **Review** — approval from at least one maintainer
6. **Merge** — squash merge. The squashed commit title is the PR title (`type(scope): title` format)
7. Delete the branch after merging

Repository settings (maintainers): protect the `main` branch — PR required, one approval, no force pushes. Once there is CI, require the tests to pass too.

## Commit messages

Commit messages, PR titles and PR descriptions are written in **English** (since 2026-11-09; earlier commits are in Korean). `CHANGELOG.md` entries are also in English from 0.2.15 on; older entries stay in Korean.

```
<type>(<scope>): <English title>

- <file>: <one-line change>
- <file>: <one-line change>

Date: YYYY-MM-DD HH:MM
```

| type | When |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code cleanup without behavior changes |
| `test` | Adding or changing tests |
| `chore` | Settings, build, release (`chore(release): 0.2.0`) |
| `del` | Removing files or code |

`scope` is a module id or area: `window` `capture` `ocr` `clipboard` `finder` `normalize` `organize` `uninstaller` `core` `docs` `release`

Example: `feat(organize): add source website condition`

- Add files by name instead of `git add -A` / `git add .` (so secrets and certificates don't slip in)
- Add an entry at the top of [CHANGELOG.md](CHANGELOG.md) with every commit (format in [docs/RELEASING.md](docs/RELEASING.md))

## Documents in two languages

- Every Markdown document comes in two files: `NAME.md` in English (the default) and `NAME.ko.md` in Korean. They say the same thing in different languages. This covers `README`, `CONTRIBUTING`, `THIRD_PARTY_NOTICES`, `App/README` and everything in `docs/`.
- Exceptions: `CHANGELOG.md` (one file; English from 0.2.15 on) and the PR template (English only).
- When you change one, change **the other in the same PR** — features, shortcuts, menu names, version numbers and links all count.
- Each file starts with a language switch line under the title. Links in a Korean document point to the Korean version of other documents (`SECURITY.ko.md`), links in an English one to the English version.
- Menu and button names in English documents match the app's English text (the second argument of `L("한국어", "English")`, `App/en.lproj`).
- `scripts/check-docs.sh` checks that each pair has the same heading structure, the same bash commands, links to the same files and the language switch line, and that the two READMEs show the same current version. `scripts/test.sh` runs it first, so changing only one side fails the tests. It can't compare the sentences themselves, so line up the paragraphs you changed by hand.

## Must follow

- [docs/SECURITY.md](docs/SECURITY.md) — no new network calls, no storing key presses, no permanent deletion, no overwriting
- The attribution policy in [docs/REFERENCES.md](docs/REFERENCES.md) — no copying GPL or Commons Clause code; record any third-party code you bring in in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- Features that need a new permission must say so in the PR description and under "Permission changes" in the release notes
