# PolyMac 아키텍처

## 1. 전체 구조

```
┌──────────────────────── PolyMac.app (메뉴바, LSUIElement) ─────────────────────────┐
│  PolyMacCore                                                                        │
│   ├─ ModuleRegistry   : 모듈 등록·활성화·비활성화 (설정에 따라 lazy init)          │
│   ├─ HotkeyCenter     : 전역 단축키 등록 + 충돌 감지 (Carbon RegisterEventHotKey)  │
│   ├─ EventTapHub      : CGEventTap 1개를 모든 모듈이 공유 (탭 여러 개 = 지연 증가) │
│   ├─ PermissionCenter : 접근성/화면녹화/자동화/전체디스크 상태 조회·안내           │
│   └─ Settings / Log   : UserDefaults + os.Logger (subsystem 단위)                 │
│                                                                                   │
│  상주 모듈 (in-process, 켜져 있을 때만 init)                                       │
│   ├─ WindowModule    : AXUIElement 창 조작                                         │
│   ├─ CaptureModule   : 오버레이·핀·마크업  ──→ OCRModule (첫 호출 시 lazy load)    │
│   ├─ FinderModule    : ⌘X 리매핑, 지정 폴더 보내기                                 │
│   ├─ ClipboardModule : 히스토리 저장·검색·고정 (SQLite + 이미지 파일)              │
│   ├─ NormalizeModule : FSEvents 감시 → NFD 파일명 NFC 변환, 클립보드 정규화        │
│   └─ OrganizeModule  : 같은 FSEvents 이벤트 → 사용자 규칙 엔진 → 이동/태그/휴지통   │
└───────────────────────────────────────────────────────────────────────────────────┘
        │ App Group (공유 설정)                 │ 열 때만 실행 (NSWorkspace.open)
        ▼                                       ▼
┌─ PolyMacFinderSync.appex ─┐          ┌─ PolyMacUninstaller.app ─────────────┐
│ Finder 툴바/우클릭 메뉴  │          │ 별도 프로세스, 창 닫으면 종료        │
│ (터미널 열기, 경로 복사) │          │ 스캐너 + 결과 UI, 관리자 작업은      │
│ Finder가 프로세스 관리   │          │ 인증 대화상자로 1회 권한 상승        │
└─────────────────────────┘          └────────────────────────────────────┘
```

## 2. 모듈 설계

### 2.1 왜 "동적 플러그인(.bundle) 로드"가 아닌가

macOS에서 런타임에 `.bundle`을 로드하는 플러그인 구조도 가능하지만:
- Hardened Runtime + 공증 환경에서 서명이 다른 번들 로드는 막히거나(`library validation`) 예외 entitlement가 필요 → 보안 약화
- 한 번 로드한 Mach-O는 언로드가 사실상 안 됨 → "끄면 메모리 0"을 달성 못함

그래서 **두 가지 방식을 섞는다**:

| 방식 | 대상 | 끄면 |
|---|---|---|
| **컴파일 포함 + lazy 활성화** | 자주 쓰는 경량 모듈 (Window, Capture, Finder, OCR) | 객체 생성 안 됨, 코드 페이지는 디스크에 있고 메모리엔 거의 안 올라옴 |
| **별도 프로세스 (on-demand)** | 무겁고 드물게 쓰는 모듈 (Uninstaller, 향후 녹화 등) | 프로세스 자체가 없음 = 진짜 0 |

### 2.2 모듈 계약

```swift
public protocol PolyMacModule: AnyObject {
    static var descriptor: ModuleDescriptor { get }   // id, 이름, 필요 권한, 상주 방식
    init(context: ModuleContext)                      // 공유 서비스(단축키, 이벤트탭, 로그) 주입
    func activate() throws
    func deactivate()
}
```

- 모듈끼리 직접 참조하지 않는다. Capture → OCR 처럼 필요한 경우 `ModuleContext`의 서비스 조회로 연결 (OCR이 꺼져 있으면 OCR 버튼만 숨김).
- 각 모듈은 Swift Package의 독립 타깃 → 모듈별 단위 테스트, 빌드 경계 명확.

## 3. 자원 예산

| 항목 | 목표 | 방법 |
|---|---|---|
| 유휴 메모리 | < 40 MB | SwiftUI는 설정 창에서만, 메뉴바·오버레이는 AppKit. 캡처 버퍼는 핀 닫으면 즉시 해제 |
| 유휴 CPU | 0% | 타이머 폴링 금지. 단축키·이벤트탭·NSWorkspace 알림만 사용 |
| 이벤트탭 지연 | < 1 ms | 탭 콜백에서 키 코드 비교만, 무거운 일은 메인 큐로 비동기 |
| OCR | < 500 ms | Vision 요청을 백그라운드 큐에서, `.accurate` 기본 / 옵션으로 `.fast` |
| 클립보드 히스토리 | 감시 비용 무시 가능, 저장소 상한 기본 200 MB | `NSPasteboard.changeCount` 확인은 불가피하게 주기적(0.5s) → 폴링 금지 원칙의 유일한 예외. 팝업 UI는 열 때만 생성, 이미지는 썸네일만 메모리에 |
| 파일명 정규화 | 유휴 0% | FSEvents 콜백(지연 1s로 묶어서 처리), 감시 폴더만 |
| 자동 정리 | 유휴 0% | Normalize와 FSEvents 스트림 공유. 규칙 평가는 파일 메타데이터만 읽음, 중복 검사(해시)는 크기가 같은 파일끼리만 |

측정은 `Instruments`(Allocations, Energy Log)와 CI의 메모리 스냅샷 스크립트로 회귀 감시.

## 4. 권한 맵

| 권한 | 필요한 모듈 | 없으면 |
|---|---|---|
| 손쉬운 사용 (Accessibility) | Window, Finder(⌘X) | 해당 기능 비활성 + 안내 |
| 화면 기록 (Screen Recording) | Capture, OCR | 캡처 불가 |
| 자동화 (Apple Events → Finder) | Finder(지정 폴더 보내기) | 보내기 기능만 비활성 |
| 파일 및 폴더 (다운로드·데스크탑·문서) | Normalize, Organize | 해당 폴더 감시 불가 → 사용자가 고른 다른 폴더만 |
| 붙여넣기 / 클립보드 접근 (향후 macOS 정책) | Clipboard | 히스토리 기록 중단 + 안내 |
| 전체 디스크 접근 | Uninstaller | `Containers` 등 일부 위치 스캔 불가 → "검사 못한 위치"로 표시 |
| 관리자 인증 (1회성) | Uninstaller (`/Library/LaunchDaemons` 등) | 해당 항목만 건너뜀 |

**원칙**: 권한은 모듈을 처음 켤 때 요청, 앱 첫 실행 때 한꺼번에 요구하지 않는다.

## 5. 기술 선택

| 영역 | 선택 | 이유 |
|---|---|---|
| 언어 | Swift 6 (strict concurrency) | 시스템 API 접근성, 저자원 |
| UI | AppKit(오버레이·핀·메뉴바) + SwiftUI(설정·Uninstaller) | 오버레이는 AppKit이 지연·메모리 유리 |
| 캡처 | ScreenCaptureKit | 구 API deprecated |
| OCR | Vision (+ VisionKit 라이브 텍스트) | 온디바이스, 한국어, 무료 |
| 단축키 | Carbon `RegisterEventHotKey` | 권한 불필요, 가장 가벼움 (KeyboardShortcuts 라이브러리 검토) |
| 자동 업데이트 | Sparkle 2 | 오픈소스 앱 표준 |
| 배포 | Developer ID 서명 + 공증 + Homebrew cask | App Store 불가(샌드박스) |
| 최소 OS | macOS 14 | ScreenCaptureKit 스크린샷 API. 표 인식 등은 `if #available(macOS 26, *)` |

## 6. 저장소 구조

```
polymac/
├─ Package.swift              # 모듈 코어 (SwiftPM) — swift build / swift test
├─ Sources/
│  ├─ PolyMacCore/              # 모듈 계약, 레지스트리, 공유 서비스
│  ├─ WindowModule/
│  ├─ CaptureModule/
│  ├─ OCRModule/
│  ├─ FinderModule/
│  ├─ ClipboardModule/
│  ├─ NormalizeModule/        # NFD → NFC 변환 로직 (순수 함수 + 이름 변경)
│  ├─ OrganizeModule/         # 규칙 모델(Codable), 규칙 엔진(순수 함수), 프리셋
│  └─ UninstallerCore/        # 스캐너 로직 (UI 없는 순수 로직 → 테스트 용이)
├─ Tests/
├─ App/                       # (예정) Xcode 프로젝트: PolyMac.app, PolyMacFinderSync.appex, PolyMacUninstaller.app
└─ docs/
```

Xcode 프로젝트는 **앱 번들·확장·서명**만 담당하고, 로직은 전부 SwiftPM 패키지에 둔다. → CLI 환경에서도 로직 빌드·테스트 가능.

## 7. 로깅

`os.Logger(subsystem: "dev.polymac", category: <모듈 id>)`. 권한 거부, 이벤트탭 비활성화(시스템이 타임아웃으로 끄는 경우), 비공개 API 로드 실패는 반드시 `error`/`fault`로 남긴다.

```bash
log stream --predicate 'subsystem == "dev.polymac"'
```
