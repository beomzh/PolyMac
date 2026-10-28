# 참고 자료

> 라이선스는 **2026-10-27에 각 저장소에서 직접 확인**한 값이다. 실제로 코드를 가져올 때는 그 시점에 다시 확인한다.

## 출처 표기 정책

이 문서는 **법적 의무가 아니라 투명성**을 위한 것이다. 무엇을 어떻게 참고했는지 공개해두면 "베꼈다"는 오해를 막고, 나중에 문제가 생겨도 근거가 된다.

| 참고 방식 | 허용 | 해야 할 것 |
|---|---|---|
| 아이디어·기능 구성·UX 흐름 참고 | 가능 | 저작권은 아이디어가 아니라 **표현(코드·그림·문구)**을 보호 → 의무 없음. 이 문서에 출처만 남김 |
| Apple 공개 문서·API 사용법 | 가능 | 의무 없음 |
| MIT 코드 일부를 가져옴 | 가능 | 원본 저작권 표시 + 라이선스 전문을 `THIRD_PARTY_NOTICES.md`에 포함, 해당 파일 상단에 출처 주석 |
| 외부 라이브러리를 의존성으로 사용 | 가능 | 위와 동일 (`THIRD_PARTY_NOTICES.md`) |
| GPL 코드 복사 (Ice 등) | 금지 | 복사하면 PolyMac 전체가 GPL이 되어야 함 → 구조만 보고 직접 작성 |
| Commons Clause 코드 복사 (Pearcleaner) | 금지 | "판매 금지" 조건이 따라옴 → 탐색 위치 목록 같은 **사실 정보**만 참고, 코드는 직접 작성 |
| 클로즈드 소스 앱 디컴파일·바이너리 분석 | 금지 | 대부분 EULA에서 금지 → 화면에 보이는 동작(UX)만 참고 |
| 다른 앱의 아이콘·이름·스크린샷·문구 | 금지 | 저작권·상표 문제. 직접 만든 것만 사용 |
| "Snipaste 대체" 같은 설명 | 가능 | 비교 목적의 이름 언급은 일반적으로 괜찮음. 단 제휴·공식으로 보이게 하지 않음 |
| macOS 비공개 API 호출 | 주의 | 내 Mac에서 쓰는 건 일반적. Apple 코드·헤더를 복사·재배포하지 않고, 시그니처는 공개 오픈소스(yabai 등)의 선언 수준만 참고 |

> 일반적인 오픈소스 관행 기준이며 법률 자문은 아니다. 상업화하거나 회사 이름으로 배포할 계획이 생기면 그때 전문가 확인을 받는다.

## 아키텍처 분석 대상 오픈소스

| 프로젝트 | 참고할 부분 | 라이선스 (확인일 2026-10-27) | 코드 가져오기 |
|---|---|---|---|
| Rectangle (rxhanson/Rectangle) | 창 위치 계산, AX 크기 변경 보정, Spectacle 단축키 호환 | MIT | 가능 (표기 필요) |
| Spectacle (eczarny/spectacle) | 원조 단축키 체계 (2022년 아카이브됨) | MIT | 가능 (표기 필요) |
| TRex (amebalabs/TRex) | Vision OCR 파이프라인, 캡처 → 텍스트 흐름 | MIT | 가능 (표기 필요) |
| OpenInTerminal (Ji4n1ng/OpenInTerminal) | Finder Sync 확장, 터미널별 실행 방식 | MIT | 가능 (표기 필요) |
| Maccy (p0deje/Maccy) | 클립보드 감시 루프, 저장 구조, 검색 UI, 무시할 pasteboard 타입 목록 | MIT | 가능 (표기 필요) |
| KeyboardShortcuts (sindresorhus) | 단축키 등록·녹화 UI | MIT | 의존성 후보 |
| Sparkle | 자동 업데이트 (공개 배포 빌드만) | MIT 계열 (포함된 외부 코드 라이선스 별도) | 의존성 후보 |
| Pearcleaner (alienator88/Pearcleaner) | 앱 잔여물 탐색 위치·매칭 규칙 | Apache 2.0 + Commons Clause | 금지 아이디어만 |
| Ice (jordanbaird/Ice) | 메뉴바 앱 구조, 권한 처리 UX | GPL-3.0 | 금지 아이디어만 |

## UX만 참고 (클로즈드 소스)

- **Snipaste** — 창 자동 감지, 핀, 마크업 툴바 배치
- **CleanShot X** — 캡처 후 플로팅 미리보기, 스크롤 캡처
- **AppCleaner** — 드래그 앤 드롭 삭제 흐름 (그리고 반면교사: 근거 없는 목록)
- **Hazel** — 폴더 감시 + 조건/동작 규칙 구성 방식

## Apple 공개 API

- ScreenCaptureKit — `SCScreenshotManager`, `SCShareableContent`
- Vision — `RecognizeTextRequest`, `RecognizeDocumentsRequest`(macOS 26), `DetectBarcodesRequest`
- VisionKit — `ImageAnalyzer`, `ImageAnalysisOverlayView`
- Accessibility — `AXUIElement`, `AXIsProcessTrustedWithOptions`
- Quartz Event Services — `CGEvent.tapCreate`
- FinderSync — `FIFinderSync`
- Translation (macOS 15+)

## 클립보드·유니코드

- nspasteboard.org — `org.nspasteboard.ConcealedType` 등 클립보드 관리자용 관례 타입
- Unicode UAX #15 (Normalization Forms) — NFC/NFD 정의
- FSEvents (`FSEventStreamCreate`) — 폴더 변경 감시

## 비공개 API 메모

- `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, `CGSAddWindowsToSpaces` 등 — yabai·Amethyst 소스에서 시그니처 확인 가능
- `_AXUIElementGetWindow` — AX 창 → `CGWindowID`
- 모두 `dlsym`으로 런타임 로드, 실패 시 기능 비활성화. macOS 메이저 업데이트마다 재검증.
