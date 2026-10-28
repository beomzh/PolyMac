# 기여 가이드

## 개발 환경

- macOS 14 이상, Apple Silicon 권장
- **Xcode 16 이상** — 테스트 실행과 Finder 확장 빌드에 필요
  (Command Line Tools만 있어도 `swift build`와 `scripts/build-app.sh`로 앱 설치까지는 됨)
- Xcodes.app(버전 관리 도구)만으로는 안 되고, 그 안에서 Xcode 자체를 설치해야 함

```bash
git clone https://github.com/beomzh/PolyMac.git
```

```bash
cd PolyMac && swift build
```

```bash
scripts/test.sh
```

앱으로 묶어 설치·실행 (Command Line Tools만으로 가능):

```bash
scripts/build-app.sh --install
```

## 코드 위치

- 로직은 전부 `Sources/<모듈>/` (SwiftPM) — UI 없는 부분은 순수 함수로 두고 `Tests/`에 테스트
- 앱 진입점·메뉴바는 `Sources/PolyMacApp/`, 번들 설정(Info.plist·entitlements)은 `App/`, 번들 조립·서명은 `scripts/build-app.sh`
- 새 모듈은 `PolyMacModule` 프로토콜을 따르고 `Package.swift`의 `modules` 배열에 추가

## 작업 흐름 — 브랜치 + Pull Request

`main`에는 직접 push하지 않는다. 모든 변경은 브랜치에서 작업하고 Pull Request(PR)로 합친다.

1. **브랜치 만들기**
   - 외부 기여자: 저장소를 fork → fork에서 브랜치
   - 메인테이너: 이 저장소에서 바로 브랜치
   - 이름: `feat/<모듈>-<설명>`, `fix/<설명>`, `docs/<설명>`, `chore/<설명>` (예: `fix/finder-cut-paste`)
2. **작업·커밋** — 아래 커밋 메시지 규칙, 커밋마다 `CHANGELOG.md` 항목
3. **PR 열기** — 대상은 `main`. 설명에 다음을 적는다
   - 무엇을 왜 바꿨는지, 어떻게 확인했는지
   - **새로 요구하는 권한**이 있으면 명시 (손쉬운 사용·화면 녹음 등)
   - **설정 형식이 바뀌면** 마이그레이션 여부 ([docs/RELEASING.md](docs/RELEASING.md) 1)
   - 화면이 바뀌면 스크린샷
4. **체크리스트** (PR 템플릿과 같음)
   - [ ] `scripts/test.sh` 통과
   - [ ] `swift build -c release` 경고 0
   - [ ] [docs/SECURITY.md](docs/SECURITY.md) 원칙 위반 없음 (네트워크 호출·키 입력 저장·영구 삭제·덮어쓰기 없음)
   - [ ] 외부 코드를 가져왔으면 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 갱신
5. **리뷰** — 메인테이너 1명 이상 승인
6. **머지** — Squash merge. 합쳐진 커밋 제목은 PR 제목(`type(scope): 제목` 형식)
7. 머지 후 브랜치 삭제

저장소 설정(메인테이너): `main` 브랜치 보호 — PR 필수, 승인 1명, 강제 push 금지. CI가 생기면 테스트 통과도 필수로.

## 커밋 메시지

```
<type>(<scope>): <한글 제목>

- <파일명>: <변경 내용 한 줄>
- <파일명>: <변경 내용 한 줄>

작업일시: yyyy년 mm월 dd일 hh시 mm분
```

| type | 언제 |
|---|---|
| `feat` | 새 기능 |
| `fix` | 버그 수정 |
| `docs` | 문서만 |
| `refactor` | 동작 변화 없는 코드 정리 |
| `test` | 테스트 추가·수정 |
| `chore` | 설정·빌드·릴리즈 (`chore(release): 0.2.0`) |
| `del` | 파일·코드 삭제 |

`scope`는 모듈 id 또는 영역: `window` `capture` `ocr` `clipboard` `finder` `normalize` `organize` `uninstaller` `core` `docs` `release`

예: `feat(organize): 받은 사이트 조건 추가`

- `git add -A` / `git add .` 대신 파일을 명시해서 추가 (시크릿·인증서 섞임 방지)
- 커밋할 때마다 [CHANGELOG.md](CHANGELOG.md) 맨 위에 항목 추가 (형식은 [docs/RELEASING.md](docs/RELEASING.md))

## 꼭 지킬 것

- [docs/SECURITY.md](docs/SECURITY.md) — 네트워크 호출 추가, 키 입력 저장, 영구 삭제, 덮어쓰기 금지
- [docs/REFERENCES.md](docs/REFERENCES.md)의 출처 표기 정책 — GPL·Commons Clause 코드 복사 금지, 외부 코드를 가져오면 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 기록
- 새 권한이 필요한 기능은 PR 설명과 릴리즈 노트 "권한 변경"에 명시
