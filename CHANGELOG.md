# CHANGELOG

개발 이력 (커밋 단위). 사용자용 변경 요약은 GitHub Releases를 본다 — 규칙은 docs/RELEASING.md.

[2026-10-27 16:43]
- [Changed] - 저장소: 0.1.0-alpha.1 작업(아래 항목들)을 커밋 c7d0652로 main에 push — 53개 파일, 테스트 21개 통과

[2026-10-27 16:42]
- [Added] - Sources/UninstallerCore/LeftoverScanner.swift: 앱 잔여물 탐색 규칙 (앱 ID·팀 ID+앱 ID·개발사 데이터·백그라운드 항목·앱 이름·pkg 설치 기록) + 이미 지운 앱의 흔적 (설치된 상위 ID·컴퓨터 UUID·살아 있는 서비스·사용 중 도우미 제외)
- [Changed] - Sources/UninstallerCore/LeftoverItem.swift: 종류별 이름·설명, 판단 근거, 확실/유력/추정 등급, 앱 정보 모델
- [Added] - Sources/UninstallerModule: 앱 삭제 창(설치된 앱 / 남은 흔적, 드래그 앤 드롭, 종류별 그룹·용량·Finder에서 보기), 실행 중 앱 종료, 사용자 백그라운드 항목 내리기, Finder 휴지통 이동(경로는 인수로), 삭제 기록
- [Added] - Tests/UninstallerCoreTests: 잔여물 등급, 팀 ID 접두, 백그라운드 항목, 흔적 규칙 6개
- [Changed] - scripts/make-icon.swift, App/AppIcon.icns, docs/assets/logo.png, Sources/PolyMacApp/AppDelegate.swift: 로고·앱 아이콘·메뉴바 아이콘을 8번 다면체 큐브로 (디자인 6~8 추가)
- [Changed] - README.md, docs/ROADMAP.md, docs/SECURITY.md: 앱 완전 삭제 사용법, 0.7.0 체크, 삭제 안전 원칙

[2026-10-27 16:31]
- [Fixed] - Sources/PolyMacCore/RegionCapture.swift: 캡처 화면이 키 입력을 받지 못해 ⌘A·C·방향키·R/A/P가 안 되던 문제 — 앱 활성화 없이 키를 받는 패널로 (macOS 14+ 활성화 거절 대응)
- [Fixed] - Sources/PolyMacCore/SelectionView.swift: 작은 핸들 점만 잡혀 크기 조절이 안 되던 문제 — 테두리 어디든 잡으면 그 변으로 크기 조절, 다른 모니터 클릭 시 그 화면이 키 입력 받음
- [Added] - Sources/PolyMacCore/Annotation.swift: 색상 동그라미 8개(빨강 기본) + 1~8 키, 색을 고르면 사각형 도구 자동 선택
- [Added] - Sources/ClipboardModule: 보관 기간(기본 7일, 1시간마다 정리) + 개수 제한, 64 KB 넘는 텍스트는 별도 파일로 전체 보관(최대 20 MB), 미리보기 앞 200 KB
- [Changed] - scripts/make-icon.swift: 로고 디자인 5종(육각 다면체·도구 그리드·프리즘·모노그램 P·레이어 스택) + --sheet 비교 이미지
- [Changed] - Sources/PolyMacApp/AppDelegate.swift: 메뉴바 아이콘 육각형
- [Changed] - README.md, docs/SECURITY.md: 보관 기간·긴 텍스트·색상·크기 조절 설명

[2026-10-27 16:18]
- [Added] - Sources/PolyMacCore/SelectionView.swift: 캡처 화면 개편 — 십자선, 돋보기(15×15 픽셀·좌표·RGB/HEX, C 색상 복사), 픽셀 크기 표시, 단계별 단축키 안내, 8방향 핸들 크기 조절·영역 이동·방향키 이동·⌘A 전체
- [Fixed] - Sources/PolyMacCore/SelectionView.swift, RegionCapture.swift: 마우스를 움직일 때마다 전체 화면 이미지를 다시 그리던 것을 배경 레이어 + 바뀐 부분만 다시 그리기로 (고해상도 모니터 CPU 사용 감소)
- [Changed] - Sources/PolyMacCore/Annotation.swift: 도구 막대 버튼·아이콘 크게
- [Added] - Sources/ClipboardModule: 이미지 기록(PNG 0600, SHA-256 중복 제거, 30 MB 제한, 지우면 파일 삭제), 보관 개수 설정(50~1000), ⌘0(10번째)
- [Changed] - Sources/ClipboardModule/ClipboardPanel.swift: 간략 목록 + 옆으로 펼치는 미리보기(⌘→/⌘←, 상태 기억), 이미지 썸네일(ImageIO 축소본), Maccy식 한 줄 요약
- [Fixed] - Sources/ClipboardModule/ClipboardModule.swift: 복사할 때마다 메인 스레드에서 전체 기록을 다시 쓰던 것을 1초 묶음 + 백그라운드 저장으로, 텍스트 항목 제한 1 MB → 512 KB
- [Added] - Tests/ClipboardModuleTests: 이미지 필드 없는 예전 기록 읽기, 이미지 항목 저장·복원, 비밀번호 관리자 항목 제외
- [Changed] - README.md, docs/SECURITY.md: 캡처 화면·히스토리 창·보관 개수 설명, 클립보드 평문 저장 한계와 전역 키 감시 범위 명시

[2026-10-27 16:02]
- [Added] - Sources/PolyMacCore/RegionCapture.swift: 창 자동 감지 (마우스 아래 창 강조, 클릭만 하면 창 크기로 선택), 캡처가 끝나면 쓰던 앱으로 포커스 복귀
- [Added] - Sources/CaptureModule/PinPanel.swift: 핀 닫기 — 마우스 올리고 Esc(전역), 클릭한 핀에서 Esc·⌫·⌦, ⌘C 복사
- [Changed] - Sources/ClipboardModule: 히스토리에서 고르면 클립보드로 복사만 (↩︎·더블클릭·⌘1~9), ⇧↩︎는 바로 붙여넣기
- [Added] - Sources/OCRModule/OCRModule.swift: ⌃⇧5 클립보드 이미지 텍스트 추출 + 메뉴 항목
- [Changed] - README.md: 창 자동 감지, 핀 닫기, 히스토리 복사 동작, ⌃⇧5

[2026-10-27 15:51]
- [Added] - Sources/PolyMacCore/Annotation.swift: 사각형·화살표·펜 표시 모델, 렌더러(합성), 공용 도구 막대
- [Added] - Sources/PolyMacCore/RegionCapture.swift: 캡처 편집 모드 — 영역 선택 후 도구 막대(표시·텍스트 추출·핀·저장·복사), 키보드 단축키, 조작 시 자동 취소 타이머 연장(2분)
- [Changed] - Sources/CaptureModule: ⌃⇧1을 편집 도구로, 핀이 표시를 따로 보관하고 우클릭 › 표시 편집으로 다시 고침, 복사·저장은 합성 이미지 / 텍스트 추출은 원본
- [Added] - Sources/ClipboardModule/ClipboardPanel.swift: 검색·전체 내용 미리보기 창, 출처 앱 아이콘·이름·시각, ↑↓·⌘1~9·⌘P·⌘⌫ (포커스를 빼앗지 않는 패널)
- [Added] - Sources/FinderModule/FinderModule.swift: 터미널 앱 선택 (터미널·iTerm2·Ghostty·Warp·WezTerm·Alacritty·kitty, 설치된 것만)
- [Added] - Sources/PolyMacCore/HotkeyCenter.swift, Sources/FinderModule: Finder 잘라내기·붙여넣기를 "Finder 안에서만" 단축키로 설정 창에서 변경·끄기
- [Changed] - README.md: 캡처 편집·핀 편집·히스토리 창·Finder 잘라내기 설명, 터미널 선택, 모듈 현황

[2026-10-27 15:28]
- [Fixed] - Sources/FinderModule/FinderKeyTap.swift: ⌘X 키 이벤트 탭을 메인 스레드에서 전용 스레드로 옮기고 콜백 내 손쉬운 사용 API에 0.1초 타임아웃 — PolyMac이나 Finder가 잠깐 멈추면 Mac 전체 키 입력이 멈출 수 있던 위험 제거
- [Fixed] - Sources/FinderModule/FinderModule.swift: 터미널 열기·경로 복사 AppleScript를 백그라운드 osascript로 (60초 제한) — Finder 무응답·권한 창 대기 중 앱 멈춤 방지
- [Fixed] - Sources/PolyMacCore/RegionCapture.swift: 캡처 오버레이에 전역 Esc, 화면 구성 변경 시 자동 취소, 60초 자동 취소 — 화면이 멈춘 것처럼 보이는 상황 방지
- [Fixed] - Sources/ClipboardModule/ClipboardModule.swift, Sources/PolyMacCore/SystemSupport.swift: 자동 붙여넣기 ⌘V에 표식을 달아 잘라내기 대기 중 파일이 이동되던 문제 방지
- [Fixed] - Sources/WindowModule/WindowModule.swift: 응답 없는 앱에 손쉬운 사용 호출이 6초씩 묶이지 않게 0.5초 타임아웃
- [Fixed] - Sources/NormalizeModule/HangulNormalizer.swift: 숨김 파일·다운로드 중 파일(.crdownload 등)은 이름을 바꾸지 않음 (+테스트)
- [Changed] - Sources/PolyMacCore/SystemSupport.swift: 손쉬운 사용 권한 요청 창을 10분에 한 번만
- [Changed] - README.md, docs/SECURITY.md: 인증서 중간 인증서(WWDR G3) 문제 해결, 캡처 취소 방법, 이벤트 탭·전체 화면 창 안전 원칙

[2026-10-27 14:55]
- [Fixed] - Sources/FinderModule/FinderModule.swift: 실행 시 손쉬운 사용 권한이 없으면 ⌘X 잘라내기가 영영 꺼져 있던 문제 — 권한이 생길 때까지 2초마다 확인해 자동으로 켬 (시스템 권한 변경 알림이 오지 않는 경우 확인)
- [Added] - Sources/PolyMacCore/HotkeyCenter.swift: 단축키 변경·사용 안 함·기본값 복원·내부 충돌 검사, UserDefaults 저장, 녹화 중 일시 해제
- [Added] - Sources/PolyMacApp/ShortcutSettings.swift: 단축키 변경 창 (메뉴바 › 단축키 › 단축키 변경…)
- [Changed] - Sources/PolyMacCore/PolyMacModule.swift, 각 모듈: 단축키를 동작 id로 등록 (저장 키 hotkey.<모듈>.<동작>)
- [Changed] - Sources/PolyMacApp/AppDelegate.swift: 메뉴를 열 때도 손쉬운 사용 권한 변화 확인
- [Changed] - README.md: 단축키 바꾸기, ⌘X 문제 해결

[2026-10-27 14:41]
- [Added] - scripts/test.sh: 설치된 Xcode를 찾아 DEVELOPER_DIR로 지정해 swift test 실행 (xcode-select 변경·sudo 불필요)
- [Changed] - scripts/build-app.sh: 서명 인증서 자동 선택 (지정값 → PolyMac Local → Apple Development → ad-hoc)
- [Changed] - README.md, CONTRIBUTING.md: Xcode Apple Development 인증서로 권한 유지하는 방법, 테스트 실행 방법

[2026-10-27 14:40]
- [Added] - scripts/make-icon.swift, App/AppIcon.icns, docs/assets/logo.png: 2×2 타일 로고·앱 아이콘 (코드로 그려 모든 크기 생성)
- [Changed] - Sources/PolyMacApp/AppDelegate.swift: 메뉴바 아이콘을 로고와 같은 모양으로, 손쉬운 사용 권한 변경 알림을 받아 해당 모듈 자동 재시작
- [Changed] - App/Info.plist, scripts/build-app.sh: 앱 번들에 아이콘 포함
- [Changed] - README.md: 로고, ad-hoc 서명으로 권한이 예전 빌드를 가리키는 문제와 권한 초기화 방법

[2026-10-27 14:36]
- [Added] - Sources/PolyMacApp: 메뉴바 앱 (모듈 on/off, 단축키·권한 목록, 로그인 시 실행, 데이터 폴더 열기)
- [Added] - Sources/PolyMacCore: 전역 단축키(Carbon), 안내 토스트, 권한 확인, FSEvents 폴더 감시, ScreenCaptureKit 영역 선택 캡처, 0600 데이터 저장
- [Added] - Sources/WindowModule: Spectacle 단축키 호환 창 분할 (½·⅓·⅔ 순환, 디스플레이 이동, 되돌리기)
- [Added] - Sources/CaptureModule: 영역 캡처 → 클립보드 / 화면 고정(핀: 이동·확대·투명도·저장·텍스트 추출)
- [Added] - Sources/OCRModule: Vision 한/영 OCR + QR 인식, NFC 정규화 후 클립보드
- [Added] - Sources/ClipboardModule: 텍스트 히스토리, 고정, 자동 붙여넣기, 비밀번호 관리자 항목 제외
- [Added] - Sources/FinderModule: ⌘X 잘라내기(이벤트 탭, 이름 편집 중 제외), 터미널 열기, 경로 복사
- [Added] - Sources/NormalizeModule: 다운로드·데스크탑 FSEvents 감시로 NFD 파일명 자동 변환 (iCloud 폴더 제외)
- [Added] - Sources/OrganizeModule: 규칙 파일 로드·감시·실행·미리보기·되돌리기, 홈 밖 이동 거부, POSIX 파일 조작(NFC 유지)
- [Changed] - Sources/OrganizeModule/OrganizeRule.swift: 조건·동작 연관값에 이름을 붙여 JSON을 사람이 편집할 수 있게
- [Added] - scripts/build-app.sh, App/Info.plist, App/PolyMac.entitlements: Xcode 없이 .app 조립·서명·설치
- [Changed] - VERSION: 0.1.0-alpha.1
- [Changed] - README.md, CONTRIBUTING.md, App/README.md: 지금 바로 쓰기(빌드·권한·고정 인증서), 동작하는 단축키, 규칙 JSON 형식, 모듈별 현황

[2026-10-27 14:15]
- [Changed] - README.md, CONTRIBUTING.md: clone 주소와 Releases 링크를 실제 저장소(github.com/beomzh/PolyMac)로 교체

[2026-10-27 14:13]
- [Added] - README.md, docs/*.md: 프로젝트 컨셉·아키텍처·로드맵·보안·릴리즈 규칙·참고자료 문서 작성
- [Added] - Package.swift, Sources/PolyMacCore: 모듈 계약(PolyMacModule)과 lazy 활성화 레지스트리
- [Added] - Sources/NormalizeModule/HangulNormalizer.swift: NFD → NFC 파일명 변환 (POSIX rename, APFS 2단계 변경)
- [Added] - Sources/OrganizeModule: 다운로드 자동 정리 규칙 모델·엔진·프리셋, 경로 탈출 방지
- [Added] - Sources/ClipboardModule/ClipboardItem.swift: 클립보드 항목 모델과 저장 제외 규칙
- [Added] - Sources/{Window,Capture,OCR,Finder}Module, Sources/UninstallerCore: 모듈 골격
- [Added] - Tests/: 레지스트리·NFC 변환·규칙 엔진 테스트
- [Added] - LICENSE, CONTRIBUTING.md, THIRD_PARTY_NOTICES.md, VERSION(0.0.1): MIT 라이선스와 기여·고지 문서

