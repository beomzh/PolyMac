# CHANGELOG

개발 이력 (커밋 단위). 사용자용 변경 요약은 GitHub Releases를 본다 — 규칙은 docs/RELEASING.md.

[2026-10-28 15:35]
- [Added] - Sources/OrganizeModule/RuleRows.swift `ConditionRow.TimeUnit`: 기간 조건(받은 지·안 연 지)에 일·개월·년 단위 — 저장은 일 수 그대로(1개월 30일, 1년 365일), 불러올 때 나누어떨어지는 가장 큰 단위로 표시
- [Changed] - Sources/OrganizeModule/OrganizeEditor.swift `ConditionEditor`: 기간 숫자 칸 옆 단위 선택
- [Added] - Tests/OrganizeModuleTests/RuleRowsTests.swift: 단위 변환 테스트
- [Changed] - README.md: 조건 표의 기간 설명

[2026-10-28 15:32]
- [Changed] - feat/normalize-folders: PR #7에 규칙 편집 입력란 수정 push

[2026-10-28 15:32]
- [Fixed] - Sources/OrganizeModule/OrganizeEditor.swift `InputBox`, `ConditionEditor`, `ActionEditor`: 규칙 편집의 조건·동작·이름 입력란이 grouped Form 기본 모양(테두리 없음, 자리표시 글이 왼쪽 이름표로 빠짐)이라 칸으로 보이지 않던 문제 — 테두리 칸 + 칸 안 자리표시 글 + 왼쪽 정렬, 숫자 칸에 MB·일 단위 표시

[2026-10-28 15:28]
- [Changed] - feat/normalize-folders: PR #7에 자동 정리 "모든 파일" 조건 push

[2026-10-28 15:28]
- [Added] - Sources/OrganizeModule/OrganizeRule.swift `Condition.allFiles`, RuleEngine.swift `evaluate`: 자동 정리 조건 "모든 파일" — 감시 폴더의 파일 전체에 동작을 걸 수 있게 (빈 조건 규칙은 여전히 아무 파일과도 맞지 않음, 다운로드 중·폴더 제외)
- [Added] - Sources/OrganizeModule/RuleRows.swift, OrganizeEditor.swift: 편집 화면 조건 목록 맨 위에 "모든 파일"과 주의 설명
- [Added] - Tests/OrganizeModuleTests/RuleRowsTests.swift: 모든 파일·빈 조건·다운로드 중 파일 테스트
- [Changed] - README.md: 조건 표에 모든 파일

[2026-10-28 15:23]
- [Changed] - feat/normalize-folders: PR #7에 자동 정리 규칙 환경 설정 탭 push

[2026-10-28 15:23]
- [Added] - Sources/OrganizeModule/OrganizeStore.swift `OrganizeStore`, `OrganizeRulesPane`: organize.json 읽기·쓰기를 모듈 밖으로 빼 기능이 꺼져 있어도 규칙 편집, 환경 설정에 넣을 자동 정리 탭
- [Changed] - Sources/OrganizeModule/OrganizeEditor.swift `OrganizeEditorView`: 환경 설정에 들어가도록 닫기 버튼 선택·최소 크기 축소, 별도 창(OrganizeEditorWindow) 삭제
- [Changed] - Sources/OrganizeModule/OrganizeModule.swift: 저장 알림을 받으면 다시 불러오기, 메뉴 "규칙 편집…"은 환경 설정 › 자동 정리 탭을 염
- [Added] - Sources/PolyMacCore/PolyMacModule.swift `ModuleContext.openSettings(tab:)`, `SettingsRequest`: 모듈이 환경 설정 탭을 열어 달라고 요청
- [Changed] - Sources/PolyMacApp/Settings.swift, AppDelegate.swift: 자동 정리 탭 추가, 탭 열기 요청 처리, 창 기본 크기 900×620
- [Changed] - README.md: 자동 정리 규칙 편집 위치 안내, 환경 설정 탭 표

[2026-10-28 15:16]
- [Changed] - feat/normalize-folders: push 후 PR #7 생성 (자소분리 검사 폴더 지정)

[2026-10-28 15:15]
- [Added] - Sources/NormalizeModule/NormalizeFolders.swift `NormalizeFolders`: 자소분리 검사 폴더 목록을 변수 normalize.folders(끈 폴더는 normalize.disabledFolders)로 저장, 예전 normalize.extraFolders 이어받기, 홈 폴더 안의 실제 폴더만 허용(홈 전체·~/Library 거부) — 다운로드·데스크탑 고정 + 추가만 되던 것을 전체 지정 가능하게
- [Changed] - Sources/NormalizeModule/NormalizeModule.swift: 새 목록 사용, 목록이 바뀌면 감시 다시 시작, 폴더가 없으면 감시하지 않음
- [Added] - Sources/PolyMacApp/Settings.swift `NormalizePane`: 환경 설정 › 한글 파일명 — 폴더 추가·빼기·켜기/끄기·기본값, 막힌 폴더는 이유 표시
- [Added] - Tests/NormalizeModuleTests/NormalizeFoldersTests.swift: 기본값·이어받기·저장·허용 검사 테스트
- [Changed] - README.md: 검사 폴더 바꾸기 안내(환경 설정·defaults 변수), 환경 설정 탭 표

[2026-10-28 15:10]
- [Changed] - CHANGELOG.md: PR #5 머지 후 main을 feat/toast-style에 합침 — 두 브랜치 기록 모두 유지

[2026-10-28 15:09]
- [Changed] - feat/toast-style: PR #6에 알림 제목·내용 상자 분리 push

[2026-10-28 15:09]
- [Changed] - Sources/PolyMacCore/Toast.swift `Toast.show(_:content:)`: 안내 첫 줄은 가운데·굵게, 다음 줄은 가운데 보조 설명, 추출한 글 같은 내용은 아래 별도 상자(왼쪽 정렬, 6줄) — 안내와 내용이 섞여 보이던 문제
- [Changed] - Sources/OCRModule/TextRecognizer.swift `OCRRunner.recognizeAndCopy`: 미리보기를 내용 상자로 분리, 문구 "텍스트를 클립보드에 복사했습니다"
- [Changed] - Sources/PolyMacApp/Settings.swift `NotificationsPane`: 미리보기에 내용 상자도 함께 표시

[2026-10-28 15:02]
- [Changed] - feat/toast-style: PR #6에 한글 입력 캡처 단축키 수정·알림 위치·시간·끄기 push

[2026-10-28 15:02]
- [Fixed] - Sources/PolyMacCore/KeyInput.swift `NSEvent.latinKey`: 한글 입력 상태에서 캡처 단축키(R·A·P·T·F·C 등)가 "ㄱ" 같은 한글로 들어와 동작하지 않던 문제 — 글자 대신 자판 위치로 판단
- [Fixed] - Sources/PolyMacCore/SelectionView.swift, Sources/CaptureModule/PinPanel.swift, Sources/ClipboardModule/ClipboardPanel.swift: 키 판단을 `latinKey`로
- [Added] - Sources/PolyMacCore/ToastStyle.swift `ToastPosition`, `isEnabled`, `seconds`: 알림 위치 7곳, 표시 시간(1~10초, 오래 뜨는 안내는 같은 비율), 알림 끄기
- [Changed] - Sources/PolyMacCore/Toast.swift `Toast.show`: 꺼져 있으면 띄우지 않고, 위치·시간 적용
- [Added] - Sources/PolyMacApp/Settings.swift `NotificationsPane`: 알림 보이기·위치·표시 시간
- [Added] - Tests/PolyMacCoreTests/ToastStyleTests.swift: 위치·시간·끄기, 한글 입력 키 판단 테스트
- [Changed] - README.md: 알림 탭 설명, 한글 입력에서도 캡처 단축키 동작 안내

[2026-10-28 14:53]
- [Changed] - feat/toast-style: PR #6에 알림 색 견본·직접 고르기 push

[2026-10-28 14:53]
- [Changed] - Sources/PolyMacApp/Settings.swift `NotificationsPane`, `ColorChoiceRow`: 글자색·배경색을 "시스템 설정 따르기" 토글 뒤에 숨기지 않고 [시스템] [견본 6개] [직접 고르기]를 한 줄에 항상 보이게 — 직접 고르기가 없는 것처럼 보이던 문제
- [Changed] - README.md: 알림 탭 설명에 견본·직접 고르기 추가

[2026-10-28 14:47]
- [Changed] - feat/toast-style: push 후 PR #6 생성 (환경 설정 알림 모양)

[2026-10-28 14:46]
- [Added] - Sources/PolyMacCore/ToastStyle.swift `ToastStyle`: 안내 알림의 글자색·배경색(미지정 시 라이트·다크 모드 따름)·글자 크기·최대 너비·여백을 UserDefaults(toast.*)에 저장, 범위 밖 값과 잘못된 색은 보정
- [Changed] - Sources/PolyMacCore/Toast.swift `Toast.show`: 저장된 모양을 적용, 배경색을 직접 정하면 단색 박스, 미리보기용 `show(_:duration:style:)` 추가
- [Added] - Sources/PolyMacApp/Settings.swift `NotificationsPane`: 환경 설정 › 알림 탭 — 색 고르기, 크기 슬라이더, 바꾸면 바로 미리보기, 기본값으로
- [Added] - Tests/PolyMacCoreTests/ToastStyleTests.swift: 색 변환·저장·보정 테스트
- [Changed] - README.md: 환경 설정 탭 표에 알림 탭 추가

[2026-10-28 15:22]
- [Changed] - feat/remaining-features: push 후 PR #5 생성 (캡처 도구, Finder 우클릭, 클립보드 파일, 설치 기록, OCR 줄바꿈, 가장자리 배치, 자동 정리 편집)

[2026-10-28 15:18]
- [Changed] - docs/ROADMAP.md: 체크 항목을 실제 구현 상태로 갱신, 남은 일은 별도 줄로 분리

[2026-10-28 15:10]
- [Added] - Sources/OrganizeModule/OrganizeEditor.swift: 자동 정리 규칙 편집 창 — 규칙 목록(켜기·추가·삭제·순서), 조건·동작 편집, 감시 폴더 추가·끄기, 미리보기 모드·기다릴 시간, 빈 값 검사 후 저장
- [Added] - Sources/OrganizeModule/RuleRows.swift: 조건·동작을 편집용 줄로 바꾸고 되돌리기, 파일 종류 이름, 중복 이름 판정("이름 (1).pdf", "이름 2.pdf")
- [Changed] - Sources/OrganizeModule/OrganizeModule.swift: 메뉴 "규칙 편집…", 저장 시 바로 반영, 중복 판정(번호 뗀 원래 파일과 크기·내용 비교)
- [Added] - Tests/OrganizeModuleTests/RuleRowsTests.swift: 편집 줄 변환·중복 판정 테스트
- [Changed] - README.md: 규칙 편집 화면 안내, 중복 조건 설명, 개발 현황 갱신

[2026-10-28 14:52]
- [Added] - Sources/WindowModule/EdgeSnap.swift: 가장자리 끌기 배치 — 왼쪽·오른쪽 끝 절반, 위 최대화, 모서리 4분의 1, 놓을 자리 미리보기(클릭 통과), 마우스 전역 감시(키 입력은 보지 않음)
- [Added] - Sources/WindowModule/WindowModule.swift: 메뉴 토글(UserDefaults window.edgeSnap, 기본 꺼짐 — macOS 창 타일링과 겹침 방지), 스냅도 ⌥⌘Z로 되돌리기
- [Added] - Package.swift, Tests/WindowModuleTests: 스냅 영역·자리 계산 테스트
- [Changed] - README.md: 가장자리 끌기 안내, 개발 현황 갱신

[2026-10-28 14:40]
- [Added] - Sources/OCRModule/LineJoiner.swift: 텍스트 추출 줄바꿈 정리 — 보이는 줄 그대로 / 문단으로 잇기(줄 간격·들여쓰기·짧은 줄로 문단 판단) / 한 줄로, 영어 줄 끝 하이픈 잇기
- [Changed] - Sources/OCRModule/TextRecognizer.swift: 인식한 줄의 위치를 함께 넘겨 줄바꿈 방법대로 합침
- [Added] - Sources/OCRModule/OCRModule.swift: 메뉴 › 줄바꿈 하위 메뉴 (UserDefaults ocr.lineMode)
- [Added] - Package.swift, Tests/OCRModuleTests: 줄바꿈 정리 테스트
- [Changed] - README.md: OCR 줄바꿈 안내, 개발 현황 표(OCR 줄바꿈·Core 환경설정) 갱신

[2026-10-28 14:34]
- [Added] - Sources/UninstallerCore/LeftoverItem.swift, Sources/UninstallerModule/UninstallerModel.swift: 설치 기록(pkg)은 휴지통 대신 pkgutil --forget(관리자 암호 한 번), 패키지 ID는 영문·숫자·.-_만 허용
- [Added] - Sources/UninstallerModule/UninstallerModel.swift, UninstallerView.swift: "목록 저장…" — 지우기 전 고른 항목(없으면 전체)을 .tsv로
- [Added] - Tests/UninstallerCoreTests: 설치 기록 ID 검사 테스트
- [Changed] - README.md, docs/UNINSTALLER.md: 설치 기록 정리·목록 저장 안내

[2026-10-28 14:32]
- [Added] - Sources/ClipboardModule/ClipboardItem.swift, ClipboardModule.swift, ClipboardPanel.swift: Finder에서 복사한 파일·폴더 기록(경로만, 고르면 다시 파일로 들어가 Finder ⌘V), 목록·미리보기에 파일 표시
- [Added] - Sources/ClipboardModule/ClipboardModule.swift: 기록하지 않을 앱 — 메뉴에서 앞에 있는 앱을 바로 제외·다시 포함
- [Added] - Tests/ClipboardModuleTests: 파일 항목·앱 제외 테스트
- [Changed] - README.md: 클립보드 단축키 표를 실제 동작(↩ 복사, ⇧↩ 붙여넣기, ⌘1~⌘0, ⌘P, ⌘⌫)으로 바로잡음, 파일 기록·앱 제외 안내

[2026-10-28 14:31]
- [Added] - Sources/PolyMacApp/ServicesProvider.swift, App/Info.plist(NSServices), App/en.lproj/ServicesMenu.strings: Finder 우클릭 메뉴(macOS 서비스) — 여기서 터미널 열기, 경로 복사, 폴더로 보내기, 한글 파일명 정리, Windows용으로 압축. Finder 확장·Xcode 없이 동작, 자동화 권한 불필요
- [Added] - Sources/FinderModule/FinderServices.swift: 고른 항목으로 터미널 열기·경로 복사, 지정 폴더로 보내기(이동/복사, 이름 충돌 시 " 2", 마지막 폴더 기억)
- [Added] - Sources/NormalizeModule/NormalizeServices.swift, HangulNormalizer.swift: 하위 폴더까지 NFC 정리(개수 확인 후, 앱·번들·.git·숨김 제외)
- [Added] - Sources/NormalizeModule/WindowsZip.swift: UTF-8 이름 플래그를 켠 zip 작성기(deflate, NFC 이름, .DS_Store·__MACOSX 제외, 4 GB까지) — macOS 기본 압축은 이 표시가 없어 Windows에서 한글이 깨짐
- [Added] - Tests/NormalizeModuleTests: 하위 폴더 정리, zip 플래그·내용 왕복 테스트 (총 32개)
- [Changed] - README.md: 우클릭 메뉴 사용법, 개발 상태

[2026-10-28 11:00]
- [Removed] - README.md: "같은 일을 하는 앱 끄기" 안내 단계
- [Added] - Sources/PolyMacCore/Annotation.swift: 표시 도구 글자(E)·모자이크(M)·번호(N), 글자 입력 칸(↩ 확정·Esc 취소), 모자이크는 원본을 10pt 칸으로 뭉갬
- [Changed] - Sources/PolyMacCore/SelectionView.swift, Sources/CaptureModule/PinPanel.swift: 캡처 화면·핀 표시 편집에서 새 도구 사용, 단축키 안내에 E M N
- [Fixed] - Sources/PolyMacCore/RegionCapture.swift: 글자 입력 중 Esc가 캡처 전체를 취소하지 않게
- [Added] - Tests/PolyMacCoreTests/AnnotationTests.swift: 모자이크·번호·글자 렌더링 테스트

[2026-10-28 10:52]
- [Fixed] - Sources/PolyMacApp/Settings.swift: 환경 설정 사이드바를 접으면 여는 버튼이 툴바 오른쪽 위로 옮겨 가던 문제 — 사이드바를 항상 펼치고 접기 버튼 제거

[2026-10-28 10:46]
- [Changed] - 저장소: 위 변경(커밋 2d016a3)을 push, PR #4 생성

[2026-10-28 10:46]
- [Added] - Sources/PolyMacApp/Settings.swift: 환경 설정 창(⌘,) — 기능 켜기/끄기·로그인 시 자동 실행·데이터 폴더, 언어, 단축키, 권한(허용 상태·쓰는 기능·설정 바로가기) 네 탭
- [Changed] - Sources/PolyMacApp/AppDelegate.swift: 메뉴바 메뉴를 앱 삭제·기능 도구·환경 설정·종료로 줄임, 켜진 기능에 권한이 빠지면 "권한이 필요합니다…" 표시, 언어를 바꾸면 켜진 기능을 다시 올려 새 언어 적용
- [Changed] - Sources/PolyMacApp/ShortcutSettings.swift: 별도 창 대신 환경 설정의 단축키 탭으로
- [Added] - Sources/PolyMacL10n: 언어 설정(시스템/한국어/English)과 L("한국어", "English") 문구 고르기
- [Changed] - Sources/PolyMacCore/PolyMacModule.swift: 기능 이름·한 줄 설명을 두 언어로
- [Changed] - Sources/*: 화면 문구 전체(메뉴·알림·캡처 안내·클립보드·Finder·자동 정리·앱 삭제)에 영어 추가, 언어를 따라야 하는 static let(프리셋·색상표·터미널 목록)을 계산 속성으로
- [Added] - App/en.lproj/InfoPlist.strings, App/Info.plist, scripts/build-app.sh: macOS 권한 안내 문구 영어판
- [Added] - Tests: 기능 이름이 언어를 따르는지, 앱 삭제 문구 테스트는 한국어로 고정
- [Changed] - README.md, docs/ARCHITECTURE.md: 환경 설정 사용법, 화면 언어 규칙(6-1)

[2026-10-28 10:28]
- [Changed] - 저장소: 위 수정(커밋 963d32d)을 PR #3 브랜치에 push

[2026-10-28 10:28]
- [Added] - Sources/UninstallerModule/UninstallerView.swift, UninstallerModel.swift: 휴지통으로 못 옮긴 항목 안내 상자 — "Finder에서 열기"로 그 항목을 골라 둔 채 Finder를 열고 휴지통으로 옮기는 방법 안내, Containers 폴더는 macOS가 폴더 자체를 지킨다는 설명
- [Fixed] - Sources/PolyMacCore/Toast.swift: 알림 문구가 흰 글자 고정이라 라이트 모드에서 잘 안 보이던 문제 — 시스템 모드를 따르는 글자색·박스(popover 재질, 테두리)

[2026-10-28 10:19]
- [Changed] - 저장소: 위 수정(커밋 3611435)을 PR #3 브랜치에 push

[2026-10-28 10:19]
- [Fixed] - Sources/UninstallerModule/UninstallerModel.swift: 남은 흔적에서 하나를 지우면 고르지 않은 다른 묶음까지 목록에서 사라져 "다시 찾기"가 필요하던 문제 — 디스크에 아직 있는 항목은 목록에 그대로 둠 (앱 모드도 같음)
- [Added] - Sources/UninstallerCore/LeftoverScanner.swift: stillPresent(지운 뒤 남은 항목, 링크는 따라가지 않음)
- [Added] - Tests/UninstallerCoreTests/LeftoverScannerTests.swift: 지운 항목만 목록에서 빠지는지 테스트 (총 26개)

[2026-10-28 10:16]
- [Changed] - 저장소: 위 수정(커밋 88d76b8)을 push, PR #3 생성

[2026-10-28 10:16]
- [Fixed] - Sources/UninstallerModule/UninstallerModel.swift: "남은 흔적" 묶음 제목이 앱 이름 대신 회사 이름(TRex → ameba, BatteryMac → alanyan)으로 나오던 문제 — 앱 단위(ID 앞 세 부분)로 묶고 앱 이름을 제목으로, 회사·앱 ID는 설명 줄로
- [Added] - Sources/UninstallerCore/LeftoverScanner.swift: appKey(앱 단위 열쇠), appTitle(남은 폴더의 사람이 지은 이름 → ID의 앱 부분 → 일반 조각이면 회사 이름 붙임)
- [Added] - Tests/UninstallerCoreTests/LeftoverScannerTests.swift: 앱 이름 제목·앱 단위 묶음 테스트 (총 25개)
- [Changed] - docs/UNINSTALLER.md: 4-3 화면에서 묶는 방식, 제목 정하는 순서

[2026-10-28 10:11]
- [Changed] - 저장소: 아래 수정(커밋 02e2b6e)을 PR #2 브랜치에 push

[2026-10-28 10:10]
- [Fixed] - Sources/UninstallerModule/UninstallerModel.swift: 흔적 찾기를 설치된 앱 목록을 다 읽기 전에 시작해, 쓰고 있는 Chrome의 데이터(Application Support/Google 등)를 "유력"으로 고르던 문제 — 목록을 다 읽은 뒤에만 시작, 못 읽으면 멈춤
- [Changed] - Sources/UninstallerModule/UninstallerModel.swift: "설치된 앱"에 Spotlight가 아는 모든 앱과 실행 중인 앱 추가, 앱 ID·이름을 Spotlight 속성으로 받아 29초 → 0.15초
- [Added] - Tests/UninstallerCoreTests: Chrome·Drive가 설치돼 있으면 Google 폴더·업데이터 제외 테스트 (총 24개)
- [Changed] - docs/UNINSTALLER.md: "설치된 앱"의 범위

[2026-10-28 10:05]
- [Changed] - 저장소: 아래 변경(커밋 683394b)을 브랜치 fix/uninstaller-installed-app-names로 push하고 PR #2 생성

[2026-10-28 10:04]
- [Fixed] - Sources/UninstallerCore/LeftoverScanner.swift: 설치된 Discord의 업데이터(com.discord.discord.ShipIt)가 흔적으로 잡히던 문제 — 앱 ID가 달라도(com.hnc.Discord) ID 속 이름이 설치된 앱 이름과 겹치면 제외, macOS·공용 구성요소(org.cups, org.swift, org.sparkle-project, org.jcef, org.chromium, com.github.electron) 제외
- [Added] - Sources/UninstallerModule: 전체 선택·전체 해제·확실·유력만 버튼, 남은 흔적을 회사 단위로 묶어 묶음째 선택(일부 선택 표시), 항목마다 찾은 앱 ID·묶음 최근 수정일
- [Added] - Tests/UninstallerCoreTests: 업데이터 ID가 다른 설치 앱·공용 구성요소 제외 테스트 (총 23개)
- [Changed] - docs/UNINSTALLER.md: 제외 조건·묶는 방식

[2026-10-28 09:47]
- [Changed] - 저장소: 아래 변경(커밋 e5aa717)을 브랜치 fix/uninstaller-finder-clipboard로 push하고 PR #1 생성 — 이번부터 main 직접 push 대신 브랜치+PR

[2026-10-28 09:44]
- [Added] - Sources/UninstallerCore/LeftoverScanner.swift: 찾는 위치 확대 (충돌 기록, /var/folders 캐시·임시, 플러그인·확장 폴더, /Library/Logs), 앱이 든 폴더(다른 앱 없을 때) 폴더째 후보
- [Added] - Sources/UninstallerCore/InUseChecker.swift: 실행 파일이 안에 있거나 파일을 연 프로그램이 있는 항목을 "사용 중"으로 표시·삭제 제외 (proc_pidpath, lsof)
- [Added] - Sources/UninstallerModule: 항목별 마지막 수정일·앱 마지막 사용일 표시, Finder가 못 옮긴 항목(다른 앱 샌드박스 데이터)은 NSWorkspace.recycle로 재시도하고 남은 이유 표시
- [Fixed] - Sources/FinderModule/FinderKeyTap.swift: 다른 앱을 거치면 잘라내기가 풀리던 문제 — 클립보드 변경 번호로 판단, Finder 응답 대기 0.1→0.25초, 통과 단계 로그(키 내용 없음)
- [Fixed] - Sources/ClipboardModule: 창을 열 때마다 새로 만들던 것(약 100 ms)을 한 번 만들어 재사용, 썸네일·앱 아이콘을 미리 준비
- [Added] - docs/UNINSTALLER.md, .github/pull_request_template.md: 앱 삭제 판단 기준 문서, PR 템플릿
- [Changed] - CONTRIBUTING.md, docs/RELEASING.md, docs/ARCHITECTURE.md, README.md, docs/CONCEPT.md, docs/REFERENCES.md: 브랜치+PR 흐름, 버전별 변경 추적 규칙, 모듈별 사용 기술·OCR 설명, 잘라내기 사용 순서, 위치 이동 시 영향, md 이모지 제거
- [Changed] - scripts/build-app.sh: 설치 완료 문구

[2026-10-27 17:17]
- [Added] - Sources/UninstallerCore: /Users/Shared 탐색, 이름형 폴더("Riot Games" 등)를 지운 앱 묶음에 붙이기(유력)·공유 폴더 이름 묶음(추정), macOS 업데이트가 옮겨 둔 Relocated Items(추정), 설치된 앱 이름·회사와 겹치면 제외, 묶음 안 정렬
- [Added] - Tests/UninstallerCoreTests: 이름형 폴더 묶기 테스트 (총 22개)

[2026-10-27 17:06]
- [Changed] - 저장소: 창 닫기 키·⌘Q·캡처 ⌘C 수정(아래 항목)을 커밋 04c948d로 main에 push

[2026-10-27 17:04]
- [Fixed] - Sources/PolyMacApp/AppDelegate.swift: 메뉴바 전용 앱이라 기본 메뉴가 없어 ⌘W로 창이 안 닫히고 검색창 ⌘C/⌘V/⌘A가 안 되던 문제 — 화면에 안 보이는 기본 메뉴(편집·윈도우) 추가, ⌘Q는 PolyMac 창이 있으면 그 창만 닫고 캡처·클립보드 창 앞에서는 무시
- [Added] - Sources/PolyMacCore/SystemSupport.swift: Esc로 닫히는 ClosableWindow — 단축키 설정·앱 삭제 창에 적용
- [Fixed] - Sources/PolyMacCore/SelectionView.swift, Annotation.swift: 캡처 영역 선택 후 ⌘C로 복사하고 닫기 (기본 메뉴의 복사·모두 선택·실행 취소와도 연결)
- [Changed] - Sources/CaptureModule/PinPanel.swift: 클릭한 핀에서 기본 메뉴 ⌘C로도 복사
- [Changed] - README.md: 창 닫기 키, 캡처 ⌘C

[2026-10-27 16:54]
- [Changed] - 저장소: 클립보드 멈춤·버벅임 수정과 앱 완전 삭제 바로가기(아래 두 항목)를 커밋 274a009로 main에 push

[2026-10-27 16:53]
- [Fixed] - Sources/ClipboardModule/ClipboardPanel.swift: 히스토리 창이 버벅이던 원인 제거 — 행마다 전체 목록을 다시 거르던 것(200개면 그릴 때마다 4만 번)을 검색어·항목이 바뀔 때만 계산, 긴 텍스트 미리보기 파일을 그릴 때마다 다시 읽던 것을 캐시, 썸네일을 백그라운드에서 읽기, 줄 수 계산 가볍게
- [Added] - Sources/PolyMacApp/AppDelegate.swift, Sources/UninstallerModule/UninstallerModule.swift: 메뉴바 맨 위에 "앱 완전 삭제…" 바로가기
- [Changed] - README.md: 앱 완전 삭제 여는 위치

[2026-10-27 16:48]
- [Fixed] - Sources/ClipboardModule/ClipboardPanel.swift: 미리보기를 펼치면 앱이 멈추던 문제 — 긴 로그(고정폭 글꼴의 한글)를 SwiftUI Text로 한 번에 배치(200 KB에 82초)하면서 창 크기 애니메이션 프레임마다 반복함. 보이는 부분만 배치하는 NSTextView로 바꿔 0.12초, 창 크기 애니메이션 제거, 목록 한 줄 요약은 앞 300자만 배치

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

