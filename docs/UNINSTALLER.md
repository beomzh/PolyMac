# 앱 완전 삭제 — 판단 기준

이 문서는 PolyMac이 어떤 파일을 "이 앱의 것"으로 보고, 무엇을 절대 건드리지 않는지를 코드와 같은 수준으로 적는다.
규칙의 실제 구현은 `Sources/UninstallerCore/LeftoverScanner.swift`, 테스트는 `Tests/UninstallerCoreTests/`.

## 1. 원칙

1. **지우는 것보다 남기는 쪽이 안전하다.** 애매하면 "추정"으로 표시하고 미리 선택하지 않는다.
2. **영구 삭제는 하지 않는다.** 모든 삭제는 휴지통으로 가며, Finder의 "되돌려 놓기"로 복구할 수 있다.
3. **실행 중인 것은 건드리지 않는다.** 실행 파일이 그 안에 있거나 파일을 열어 둔 프로그램이 있으면 선택할 수 없다.
4. **macOS 자체는 대상이 아니다.** `com.apple.*`, `/System` 아래, macOS가 만드는 폴더는 제외한다.
5. **판단 근거를 항목마다 보여 준다.** 사용자가 이유를 보고 결정할 수 있어야 한다.

## 2. 찾는 위치

| 종류 | 사용자 (`~/Library/…`) | 시스템 (`/Library/…`, 암호 필요) |
|---|---|---|
| 앱 데이터 | `Application Support` | `Application Support` |
| 캐시 | `Caches`, `/var/folders/…/C` | `Caches` |
| 임시 파일 | `/var/folders/…/T` | |
| 설정 | `Preferences`, `Preferences/ByHost` | `Preferences` |
| 샌드박스 데이터 | `Containers` | |
| 공유 데이터 | `Group Containers` | |
| 창 상태 | `Saved Application State` | |
| 웹 데이터 | `HTTPStorages`, `WebKit`, `Cookies` | |
| 로그 | `Logs` | `Logs` |
| 충돌 기록 | `Logs/DiagnosticReports`, `Application Support/CrashReporter` | `Logs/DiagnosticReports` |
| 기타 | `Application Scripts` | |
| 백그라운드 항목 | `LaunchAgents` | `LaunchAgents`, `LaunchDaemons`, `PrivilegedHelperTools` |
| 플러그인·확장 | `Internet Plug-Ins`, `PreferencePanes`, `Services`, `QuickLook`, `Spotlight`, `Screen Savers`, `Input Methods`, `Audio/Plug-Ins/{Components,VST,VST3,HAL}` | 같은 폴더들 |
| 공유 폴더 | `/Users/Shared` | |
| 설치 기록 | | `/var/db/receipts` (pkg) |
| 앱이 든 폴더 | `/Applications/<폴더>/`, `~/Applications/<폴더>/` | |

각 위치는 **바로 아래 항목만** 본다 (하위 폴더를 재귀로 뒤지지 않는다). 찾은 항목은 폴더째 지운다.

## 3. 설치된 앱의 잔여물 — 등급

이름 비교 전에 확장자(`.plist`, `.savedState`, `.binarycookies`, `.lockfile`)를 떼고, 이름 비교는 대소문자를 무시한다.

| 등급 | 조건 | 기본 선택 |
|---|---|---|
| 확실 | 이름이 앱 ID와 같거나 `앱ID.`으로 시작 (`com.foo.App`, `com.foo.App.helper.plist`) | 예 |
| 확실 | `팀ID.앱ID` 형태 — 팀 ID는 대문자·숫자 10자리 (`ABCDE12345.com.foo.App`) | 예 |
| 확실 | 플러그인 번들의 ID가 앱 ID와 같거나 `앱ID.`으로 시작 | 예 |
| 유력 | 이름이 `앱의 팀ID.`으로 시작 (같은 개발사 데이터) | 예 |
| 유력 | 백그라운드 항목 plist의 실행 경로가 앱 번들 안을 가리킴 | 예 |
| 유력 | 충돌 기록 파일 이름의 앞부분(`-`·`_` 앞)이 앱 실행 파일 이름과 같음 | 예 |
| 유력 | 정규화한 이름이 정규화한 앱 이름과 같음 (3자 이상) | 예 |
| 유력 | pkg 설치 기록 ID가 앱 ID와 같거나 그 하위 | 예 |
| 유력 | 앱이 든 폴더 — 앱이 `/Applications` 바로 아래가 아니고, 그 폴더(두 단계까지)에 다른 `.app`이 없음 | 예 |
| 추정 | 정규화한 이름에 앱 이름이 들어 있음 (앱 이름 5자 이상) | 아니요 |
| 추정 | 플러그인 번들의 회사(앱 ID 앞 두 부분)가 앱과 같음 | 아니요 |

**정규화**: 한글 자모 합치기(NFC) → 소문자 → 글자·숫자만 남김. 예: `Riot Client` → `riotclient`, `riot-client-ux` → `riotclientux`.

## 4. 이미 지운 앱의 흔적 — 등급

### 4-1. 앱 ID 형태 이름

이름이 앱 ID처럼 생긴 항목만 후보로 본다.

- 점으로 나눈 부분이 3~6개이고, 각 부분이 글자·숫자·`-`·`_`로만 되어 있으며
- 첫 부분이 `com, org, net, io, dev, app, co, de, jp, kr, us, me` 중 하나
- 끝의 컴퓨터 UUID(ByHost 설정)는 떼고 본다

다음 중 하나라도 해당하면 **제외**한다.

| 제외 조건 | 이유 |
|---|---|
| `com.apple.`으로 시작 | macOS 자체 |
| 설치된 앱의 ID이거나 그 하위 (`com.foo.App.ShipIt`) | 설치된 앱의 업데이터·도우미 |
| 상위 ID(`com.foo.App`)의 앱이 이 Mac에 있음 (LaunchServices 기준, 휴지통 제외) | 같음 |
| 백그라운드 항목인데 실행할 프로그램이 아직 있음 | 앱 없이 설치되는 서비스(보안 프로그램 등) |
| 지금 등록된 백그라운드 항목이 실행하는 파일 | 관리자 도우미처럼 쓰이는 중 |

남은 것의 등급:

| 등급 | 조건 |
|---|---|
| 유력 | 그 회사(ID 앞 두 부분)의 앱이 하나도 설치돼 있지 않음 |
| 유력 | 백그라운드 항목이고 실행할 프로그램이 지워졌음 |
| 추정 | 같은 회사의 다른 앱이 설치돼 있음 — 공용 구성요소일 수 있음 |

### 4-2. 사람이 읽는 이름의 폴더 ("Riot Games")

**이름 열쇠**: 지운 앱 ID에서 첫 부분을 빼고 나머지 부분을 정규화한 것 중 4자 이상이고 흔한 단어가 아닌 것.
예: `com.riotgames.RiotGames.RiotClient` → `riotgames`, `riotclient`.

흔한 단어(열쇠로 쓰지 않음): `app, apps, mac, macos, osx, desktop, helper, agent, service, launcher, updater, shipit, plugin, plugins, client, studio, pro`

**비슷함**: 두 정규화 이름 `a`, `b`가 같거나, 한쪽이 5자 이상인 다른 쪽으로 시작하면 비슷하다고 본다.
예: `riotclientux` ~ `riotclient`, `blizzardentertainment` ~ `blizzard`.

| 위치 | 규칙 | 등급 |
|---|---|---|
| `/Users/Shared`, `Application Support`, `Caches`, `Logs` | 지운 앱의 이름 열쇠와 비슷 → 그 앱 묶음에 넣음 | 유력 |
| `/Users/Shared` | 어느 열쇠와도 안 맞고 설치된 앱과도 관계없음 → 그 폴더 이름으로 새 묶음 | 추정 |
| `Application Support`, `Caches`, `Logs` | 위 `/Users/Shared` 묶음과 비슷 → 그 묶음에 넣음 (새 묶음은 만들지 않음) | 추정 |
| `/Users/Shared`의 `Relocated Items`, `Previously Relocated Items*` | macOS 업데이트가 옮겨 둔 예전 설정 | 추정 |

**설치된 앱과 관계있으면 항상 제외** (흔적 쪽보다 넓게 본다): 폴더 이름이 설치된 앱 이름이나 설치된 앱 ID의 각 부분(4자 이상)과 같거나, 한쪽이 다른 쪽으로 시작하면 제외.
예: 설치된 `zoom.us`(ID `us.zoom.xos`) → `Zoom Data` 제외.

`/Users/Shared`에 원래 있는 `SC Info`, `adi`, `Library`, `Shared Items`는 제외.

## 5. 지울 때

1. 실행 중인 앱이면 정상 종료를 요청하고 5초까지 기다린다. 끝나지 않으면 지우지 않는다.
2. **사용 중 확인** — 지울 항목 안에
   - 실행 파일이 있는 프로그램 (`proc_pidpath`), 또는
   - 파일을 열어 둔 프로그램 (`lsof`, 내 계정 프로세스)
   이 있으면 그 항목은 선택할 수 없고 "사용 중 (프로그램 이름)"으로 표시한다. 지우려는 앱 자신의 프로그램은 1번에서 종료하므로 제외한다.
3. 사용자 백그라운드 항목은 `launchctl bootout`으로 먼저 내린다.
4. 폴더와 그 안의 항목을 함께 골랐으면 폴더만 넘긴다.
5. **Finder에게 휴지통으로 옮기게** 한다 (AppleScript, 경로는 인수로 — 파일 이름으로 스크립트가 조작되지 않게). `/Library` 아래 항목은 Finder가 관리자 암호를 묻는다.
6. Finder가 못 옮긴 항목(다른 앱의 샌드박스 데이터 등 macOS 보호 항목)은 `NSWorkspace.recycle`로 다시 시도한다. 이때 macOS가 "다른 앱의 데이터 접근" 허용을 물을 수 있다.
7. 그래도 남은 항목은 이유와 함께 보여 주고, 기록을 `~/Library/Application Support/PolyMac/uninstall-log.txt`에 남긴다.

## 6. 화면에 보여 주는 정보

- 항목마다: 경로, 판단 근거, 등급, 크기, **안쪽 파일까지 포함한 마지막 수정일**, 암호 필요 여부, 사용 중 여부
- 앱: **마지막 사용일** (Spotlight 기록 `kMDItemLastUsedDate`, 없으면 "기록 없음")

## 7. 알려진 한계

- `lsof`는 내 계정의 프로세스만 본다. 관리자 권한으로 도는 서비스가 연 파일은 "사용 중"으로 잡히지 않을 수 있다 (그런 항목은 대부분 `/Library` 아래라 지울 때 암호를 묻는다).
- 이름 규칙은 휴리스틱이다. 회사 이름이 아주 짧거나(4자 미만) 흔한 단어면 찾지 못한다.
- 각 위치의 바로 아래 항목만 본다. `Application Support/회사/앱`처럼 깊이 숨은 것은 회사 폴더 단위로만 찾는다.

규칙을 바꾸는 PR은 이 문서와 `Tests/UninstallerCoreTests`를 함께 고친다.
