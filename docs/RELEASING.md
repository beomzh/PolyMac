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
4. **버전 올리기** — `VERSION` 수정, `CHANGELOG.md`에 릴리즈 항목 추가, 커밋 `chore(release): X.Y.Z`
5. **태그**
   ```bash
   git tag -a vX.Y.Z -m "PolyMac X.Y.Z"
   git push origin main --tags
   ```
6. **빌드 · 서명**
   - 개인용: 고정 자체 서명 인증서로 서명 (TCC 권한이 빌드마다 초기화되지 않게)
   - 공개 배포: Developer ID 서명 + Hardened Runtime + 공증(notarytool) + staple
7. **배포 파일** — `PolyMac-X.Y.Z.zip` + `PolyMac-X.Y.Z.zip.sha256` 를 GitHub Release에 첨부, 릴리즈 노트 작성
8. **(1.0.0 이후)** Homebrew cask 버전·해시 갱신

## 5. 지원 정책

- **최소 macOS**: 14 Sonoma. 올리는 것은 0.x에서는 MINOR, 1.0 이후에는 MAJOR 변경으로만.
- 신기능이 새 OS 전용이면(예: macOS 26 표 인식) `if #available`로 감싸고 구버전에서는 메뉴를 숨긴다.
- 보안 수정은 최신 MINOR에만 반영한다 (구버전 백포트 없음).
