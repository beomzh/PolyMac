# Complete app uninstall — decision rules

**English** · [한국어](UNINSTALLER.ko.md)

This document describes, at the same level of detail as the code, which files PolyMac treats as "belonging to this app" and what it never touches.
The rules are implemented in `Sources/UninstallerCore/LeftoverScanner.swift`, with tests in `Tests/UninstallerCoreTests/`.

## 1. Principles

1. **Leaving something behind is safer than deleting it.** When in doubt, mark it "Possible" and don't preselect it.
2. **No permanent deletion.** Everything goes to the Trash and can be restored with Finder's "Put Back".
3. **Nothing in use is touched.** An item can't be selected if a running program's executable is inside it or a program has a file in it open.
4. **macOS itself is not a target.** `com.apple.*`, anything under `/System` and folders macOS creates are excluded.
5. **Show the reason for every item.** The user must be able to see why and decide.

## 2. Where it looks

| Kind | User (`~/Library/…`) | System (`/Library/…`, needs password) |
|---|---|---|
| App data | `Application Support` | `Application Support` |
| Caches | `Caches`, `/var/folders/…/C` | `Caches` |
| Temporary files | `/var/folders/…/T` | |
| Preferences | `Preferences`, `Preferences/ByHost` | `Preferences` |
| Sandbox data | `Containers` | |
| Shared data | `Group Containers` | |
| Window state | `Saved Application State` | |
| Web data | `HTTPStorages`, `WebKit`, `Cookies` | |
| Logs | `Logs` | `Logs` |
| Crash reports | `Logs/DiagnosticReports`, `Application Support/CrashReporter` | `Logs/DiagnosticReports` |
| Other | `Application Scripts` | |
| Background items | `LaunchAgents` | `LaunchAgents`, `LaunchDaemons`, `PrivilegedHelperTools` |
| Plug-ins and extensions | `Internet Plug-Ins`, `PreferencePanes`, `Services`, `QuickLook`, `Spotlight`, `Screen Savers`, `Input Methods`, `Audio/Plug-Ins/{Components,VST,VST3,HAL}` | The same folders |
| Shared folder | `/Users/Shared` | |
| Install receipts | | `/var/db/receipts` (pkg) — `pkgutil --forget <id>` instead of the Trash (administrator password); IDs may only contain letters, digits and `.-_` |
| Folder containing the app | `/Applications/<folder>/`, `~/Applications/<folder>/` | |

Only the **items directly inside** each location are checked (subfolders are not searched recursively). A found item is deleted as a whole folder.

## 3. Leftovers of an installed app — grades

Before comparing names, extensions (`.plist`, `.savedState`, `.binarycookies`, `.lockfile`) are removed, and names are compared case-insensitively.

| Grade | Condition | Preselected |
|---|---|---|
| Certain | The name equals the app ID or starts with `appID.` (`com.foo.App`, `com.foo.App.helper.plist`) | Yes |
| Certain | `teamID.appID` form — the team ID is 10 uppercase letters and digits (`ABCDE12345.com.foo.App`) | Yes |
| Certain | A plug-in bundle's ID equals the app ID or starts with `appID.` | Yes |
| Likely | The name starts with `the app's teamID.` (data from the same developer) | Yes |
| Likely | A background item plist's program path points inside the app bundle | Yes |
| Likely | The first part of a crash report file name (before `-` or `_`) equals the app's executable name | Yes |
| Likely | The normalized name equals the normalized app name (3 or more characters) | Yes |
| Likely | A pkg receipt ID equals the app ID or is under it | Yes |
| Likely | The folder containing the app — the app is not directly in `/Applications`, and that folder (up to two levels) has no other `.app` | Yes |
| Possible | The normalized name contains the app name (app name 5 or more characters) | No |
| Possible | A plug-in bundle's company (the first two parts of the app ID) matches the app's | No |

**Normalization**: compose Korean letters (NFC) → lowercase → keep only letters and digits. Example: `Riot Client` → `riotclient`, `riot-client-ux` → `riotclientux`.

## 4. Leftovers of apps already deleted — grades

### 4-0. What counts as "installed apps"

The "installed apps" used to judge leftovers are all of the following combined. **Leftover search doesn't start until this whole list has been read, and stops if it can't be read** (judging against an empty list would pick data of apps in use as leftovers).

- `/Applications`, `~/Applications` (down to folders two levels deep)
- Every app on this Mac that Spotlight knows (`kMDItemContentType == com.apple.application-bundle`, excluding the Trash and `/System`) — including apps in other places like Downloads, and apps hidden inside apps (e.g. `~/Library/Application Support/discord/…/Discord.app`)
- Apps running right now

### 4-1. Names shaped like app IDs

Only items whose names look like app IDs are candidates.

- 3 to 6 dot-separated parts, each made only of letters, digits, `-` and `_`
- The first part is one of `com, org, net, io, dev, app, co, de, jp, kr, us, me`
- A trailing computer UUID (ByHost preferences) is removed first

Anything matching one of these is **excluded**.

| Excluded when | Why |
|---|---|
| Starts with `com.apple.`, `org.cups.`, `org.swift.` | macOS itself (including the printing system and Swift tools) |
| Starts with `org.sparkle-project.`, `org.jcef.`, `org.chromium.`, `com.github.electron` | Components shared by many apps (automatic updates, web views inside apps) |
| The name inside the ID (the name keys in 4-2) relates to an installed app's name or ID | It may belong to that app even with a different ID — e.g. Discord's app is `com.hnc.Discord` and its updater `com.discord.discord.ShipIt` |
| It is an installed app's ID or under it (`com.foo.App.ShipIt`) | An installed app's updater or helper |
| The app of the parent ID (`com.foo.App`) is on this Mac (per LaunchServices, excluding the Trash) | Same |
| A background item whose program still exists | Services installed without an app (security software and the like) |
| A file run by a currently registered background item | In use, like an administrator helper |

Grades of what remains:

| Grade | Condition |
|---|---|
| Likely | No app from that company (first two parts of the ID) is installed |
| Likely | A background item whose program has been deleted |
| Possible | Another app from the same company is installed — it may be a shared component |

### 4-2. Folders with human-readable names ("Riot Games")

**Name keys**: from a deleted app's ID, drop the first part, normalize the remaining parts, and keep those that are 4 or more characters and not common words.
Example: `com.riotgames.RiotGames.RiotClient` → `riotgames`, `riotclient`.

Common words (never used as keys): `app, apps, mac, macos, osx, desktop, helper, agent, service, launcher, updater, shipit, plugin, plugins, client, studio, pro`

**Similar**: two normalized names `a` and `b` are similar if they are equal, or if one starts with the other and the other is 5 or more characters.
Example: `riotclientux` ~ `riotclient`, `blizzardentertainment` ~ `blizzard`.

| Location | Rule | Grade |
|---|---|---|
| `/Users/Shared`, `Application Support`, `Caches`, `Logs` | Similar to a deleted app's name key → added to that app's group | Likely |
| `/Users/Shared` | Matches no key and relates to no installed app → a new group named after the folder | Possible |
| `Application Support`, `Caches`, `Logs` | Similar to one of the `/Users/Shared` groups above → added to that group (no new groups made) | Possible |
| `Relocated Items`, `Previously Relocated Items*` in `/Users/Shared` | Old settings moved aside by a macOS update | Possible |

**Always excluded if related to an installed app** (judged more broadly than leftovers): excluded if the folder name equals an installed app's name or any part (4 or more characters) of an installed app's ID, or if one starts with the other.
Example: installed `zoom.us` (ID `us.zoom.xos`) → `Zoom Data` excluded.

`SC Info`, `adi`, `Library` and `Shared Items`, which normally exist in `/Users/Shared`, are excluded.

## 4-3. How results are grouped on screen

"Leftovers" are shown in one group per app (the first three parts of the app ID, e.g. `com.ameba.TRex`). Helper and widget IDs of the same app (`com.alanyan.BatteryMac.BigSurWidget`) go into that app's group, while different apps from one company (`com.riotgames.RiotGames`, `com.riotgames.LeagueofLegends`) get separate groups. Groups found by name and update leftovers are grouped separately.

The group title is the app name. Since the app is already gone and there is nothing to ask for its real name, it is chosen in this order. The company name and app ID are shown on the description line under the title.

1. If a human-named folder among the leftovers matches the app part of the app ID, that name (`com.nexon.maplestory` → `Application Support/MapleStory` → "MapleStory")
2. Otherwise the app part of the app ID (`com.ameba.TRex` → "TRex"). If it's all lowercase, only the first letter is capitalized
3. If the app part is generic like `app` or `cli`, or 3 characters or fewer, the company name is put in front (`net.battle.app` → "Battle App")

## 5. When deleting

1. If the app is running, ask it to quit normally and wait up to 5 seconds. If it doesn't quit, nothing is deleted.
2. **In-use check** — if an item to delete contains
   - the executable of a running program (`proc_pidpath`), or
   - a file a program has open (`lsof`, processes of the current user)
   that item can't be selected and is shown as "In use (program name)". Programs of the app being deleted are excluded, since step 1 quits them.
3. User background items are unloaded first with `launchctl bootout`.
4. If a folder and items inside it are both selected, only the folder is passed on.
5. **Finder is asked to move items to the Trash** (AppleScript, with paths passed as arguments — so file names can't tamper with the script). For items under `/Library`, Finder asks for the administrator password.
6. Items Finder couldn't move (macOS-protected items such as another app's sandbox data) are retried with `NSWorkspace.recycle`. macOS may then ask to allow "access to data from other apps".
7. Anything still left is shown with the reason, and a record is written to `~/Library/Application Support/PolyMac/uninstall-log.txt`.

## 6. Information shown on screen

- For each item: path, reason, grade, size, **last modified date including the files inside**, whether a password is needed, whether it's in use
- For the app: **last used date** (Spotlight's `kMDItemLastUsedDate`, "unknown" if missing)

## 7. Known limits

- `lsof` only sees the current user's processes. Files opened by services running as administrator may not show as "in use" (such items are mostly under `/Library`, so deleting them asks for a password).
- The name rules are heuristics. Very short (under 4 characters) or common company names aren't found.
- Only items directly inside each location are checked. Something hidden deep, like `Application Support/Company/App`, is found only at the company folder level.

A PR that changes these rules updates this document and `Tests/UninstallerCoreTests` together.
