# 기여 가이드

## 개발 환경

- macOS 14 이상, Apple Silicon 권장
- **Xcode 16 이상** — 앱 번들·Finder 확장 빌드와 `swift test` 실행에 필요
  (Command Line Tools만 있으면 `swift build`만 됨)

```bash
git clone <저장소 주소> PolyMac
```

```bash
cd PolyMac && swift build
```

```bash
swift test
```

## 코드 위치

- 로직은 전부 `Sources/<모듈>/` (SwiftPM) — UI 없는 부분은 순수 함수로 두고 `Tests/`에 테스트
- 앱 번들·확장·서명만 `App/` (Xcode 프로젝트, 예정)
- 새 모듈은 `PolyMacModule` 프로토콜을 따르고 `Package.swift`의 `modules` 배열에 추가

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
