# 버전 관리 & 릴리즈 규칙

## 1. 버전 번호 — Semantic Versioning

형식: `MAJOR.MINOR.PATCH` (예: `0.3.1`), 사전 배포는 `0.3.0-beta.1`

현재 버전은 저장소 루트의 [`VERSION`](../VERSION) 파일 하나가 기준(single source of truth)이다. Xcode 프로젝트가 생기면 `MARKETING_VERSION`은 이 파일에서 읽는다.

### 1.0.0 이전 (지금)

| 올리는 자리 | 언제 | 예 |
|---|---|---|
| MINOR (`0.x.0`) | [ROADMAP](ROADMAP.md)의 한 단계 완료, 새 모듈 추가, 설정 형식 변경 | `0.2.0` 캡처·핀 추가 |
| PATCH (`0.x.y`) | 버그 수정, 문서, 성능 개선 (동작·설정 형식 그대로) | `0.2.1` 멀티 모니터 좌표 수정 |

- 0.x에서는 설정 형식이 바뀔 수 있다. 바뀔 때는 **반드시 자동 마이그레이션**을 넣고 릴리즈 노트의 "호환성" 항목에 적는다.

### 1.0.0 이후

| 올리는 자리 | 언제 |
|---|---|
| MAJOR | 설정·규칙 JSON 호환이 깨짐, **최소 macOS 버전 상향**, 모듈 제거, 단축키 기본값 대규모 변경 |
| MINOR | 기능·모듈 추가, 새 권한이 필요한 기능 추가 (하위 호환 유지) |
| PATCH | 버그·보안 수정, 문서 |

### 빌드 번호
`CURRENT_PROJECT_VERSION` = `git rev-list --count HEAD` (계속 증가하는 정수). macOS는 같은 버전 문자열이라도 빌드 번호로 업데이트 여부를 판단한다.

### 설정 파일 버전
사용자 데이터(규칙 JSON, 클립보드 DB 등)에는 앱 버전과 별개로 `schemaVersion` 정수를 둔다. 형식이 바뀌면 +1 하고 이전 버전을 읽어 변환하는 코드를 남긴다. 가져오기한 JSON의 `schemaVersion`이 앱보다 높으면 적용하지 않고 업데이트를 안내한다.

## 2. 브랜치 · 태그

| 이름 | 용도 |
|---|---|
| `main` | 항상 빌드되는 상태. 릴리즈 태그는 여기서만 |
| `feat/<모듈>-<설명>` | 기능 개발 (`feat/capture-pin`) |
| `fix/<설명>` | 버그 수정 |
| `docs/<설명>` | 문서만 |
| 태그 `vX.Y.Z` | 릴리즈. **annotated 태그**(`git tag -a`)만 사용, 한 번 푼 태그는 옮기거나 지우지 않음 |

- 급한 수정은 `main`에서 `fix/` 브랜치를 따서 고치고 PATCH 릴리즈.
- 커밋 메시지 규칙은 [CONTRIBUTING.md](../CONTRIBUTING.md).

## 3. 변경 기록 — 두 가지를 구분한다

| 파일 | 대상 | 내용 | 언제 |
|---|---|---|---|
| [`CHANGELOG.md`](../CHANGELOG.md) | 개발자 | 커밋 단위 상세 이력 (파일·함수 단위) | 커밋할 때마다 맨 위에 추가 |
| GitHub Release 노트 | 사용자 | "무엇이 좋아졌는지" 몇 줄 + 호환성·권한 변경 | 태그를 만들 때 |

CHANGELOG 항목 형식:

```
[YYYY-MM-DD HH:MM]
- [Added|Changed|Fixed|Removed|Security] - <파일경로>: <무엇을 왜>
```

릴리즈 노트 템플릿:

```markdown
## PolyMac X.Y.Z

### 새 기능
- ...

### 개선 · 수정
- ...

### 호환성      ← 설정 형식·최소 macOS·단축키 기본값 변경 (없으면 "없음")
### 권한 변경   ← 새로 요청하는 권한 (없으면 "없음")
### 보안        ← 보안 관련 수정 (없으면 생략)
```

## 3-1. 버전별로 무엇이 바뀌었는지 찾기

세 군데에서 같은 정보를 다른 깊이로 볼 수 있다.

| 보고 싶은 것 | 어디서 |
|---|---|
| 이번 버전에서 사용자에게 달라진 점 (몇 줄) | GitHub Releases 의 해당 버전 노트 |
| 이번 버전에 들어간 모든 개발 변경 (파일 단위) | `CHANGELOG.md`의 해당 버전 구간 |
| 두 버전 사이의 코드 차이 | `git log v0.1.0..v0.2.0`, GitHub의 `compare/v0.1.0...v0.2.0` |

**CHANGELOG 버전 구간 규칙** — 커밋마다 항목이 맨 위에 쌓이므로, 릴리즈할 때 마지막 릴리즈 이후 쌓인 항목들 **맨 위에** 버전 줄을 넣는다.

```
## 0.2.0 (2026-11-10) — 이 줄부터 아래 0.1.0 줄 전까지가 0.2.0에 들어간 변경
[2026-11-09 18:20]
- [Fixed] - ...
...
## 0.1.0 (2026-10-30)
...
```

버전 줄보다 위에 있는 항목은 아직 릴리즈되지 않은 변경이다.

## 4. 릴리즈 절차 (체크리스트)

1. **범위 확인** — ROADMAP 해당 단계 체크박스 완료, 미완 항목은 다음 버전으로 이동
2. **검증**
   - [ ] `swift build && swift test` 통과 (Xcode 필요)
   - [ ] 앱 빌드 후 수동 확인: 해당 버전 모듈 동작, 권한 없을 때 안내
   - [ ] 자원 예산: 유휴 메모리 < 40 MB, 유휴 CPU 0% (Activity Monitor)
3. **보안** — [SECURITY.md](SECURITY.md) 기준
   - [ ] 유휴·기능 사용 중 외부 네트워크 연결 0건 (`nettop -p PolyMac`)
   - [ ] `secret-scan` 통과 (하드코딩 경로·키 없음)
   - [ ] 의존성 추가 시 `dependency-audit` + [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) 갱신
4. **버전 올리기** — `VERSION` 수정, `CHANGELOG.md` 맨 위에 버전 줄(3-1), PR로 `chore(release): X.Y.Z` 머지
5. **태그**
   ```bash
   git tag -a vX.Y.Z -m "PolyMac X.Y.Z"
   git push origin main --tags
   ```
6. **빌드 · 서명 · 묶기** — 태그를 찍은 main에서
   ```bash
   scripts/package-release.sh
   ```
   - 고정 인증서(이름이 `PolyMac `으로 시작하는 자체 서명 인증서)로 서명한다. 매번 같은 인증서여야 받는 사람의 macOS 권한(손쉬운 사용·화면 녹음)이 업데이트 뒤에도 유지된다. 고를 때는 `POLYMAC_SIGN_IDENTITY`.
   - 배포용 인증서는 `PolyMac Beomzh`(자체 서명, 10년, 백업 `~/Documents/PolyMac-signing.p12`) — `scripts/make-signing-cert.sh`로 만들었다. `Apple Development`는 쓰지 않는다: 서명에 이메일·실명·팀 ID가 드러나고(`codesign -dvv`), 1년마다 만료되며 시각 기록이 없어 만료 뒤 새로 받는 사람에게 무효로 보일 수 있다.
   - 자체 서명 인증서는 **잃어버리면 같은 것을 다시 만들 수 없다** — 새 인증서로 서명한 업데이트는 다른 앱으로 취급돼 모든 사용자가 권한을 다시 줘야 한다. 백업 `.p12`를 저장소 밖 안전한 곳에 보관한다.
   - **공증하지 않는다** (Apple 개발자 프로그램 미가입). Hardened Runtime은 켜 둔다. 받는 사람은 처음 한 번 "그래도 열기"가 필요하다 — README "처음 열 때 막히면".
   - 스크립트는 VERSION이 사전 배포(`-alpha` 등)가 아니고 작업 트리가 깨끗하며 `vX.Y.Z` 태그가 HEAD에 있을 때만 묶는다.
7. **배포 파일** — `build/release/PolyMac-X.Y.Z.zip` + `.zip.sha256`
   ```bash
   gh release create vX.Y.Z build/release/PolyMac-X.Y.Z.zip build/release/PolyMac-X.Y.Z.zip.sha256 --title "PolyMac X.Y.Z" --notes-file <노트 파일>
   ```
8. **(1.0.0 이후)** 개인 Homebrew tap(`beomzh/homebrew-tap`) cask 버전·해시 갱신. 공식 cask 저장소는 공증 안 된 앱을 받지 않는다.

## 5. 지원 정책

- **최소 macOS**: 14 Sonoma. 올리는 것은 0.x에서는 MINOR, 1.0 이후에는 MAJOR 변경으로만.
- 신기능이 새 OS 전용이면(예: macOS 26 표 인식) `if #available`로 감싸고 구버전에서는 메뉴를 숨긴다.
- 보안 수정은 최신 MINOR에만 반영한다 (구버전 백포트 없음).
