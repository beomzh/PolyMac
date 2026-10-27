# App (예정)

Xcode 프로젝트가 들어갈 자리입니다. 앱 번들·확장·서명만 담당하고 로직은 상위 SwiftPM 패키지를 의존합니다.

- `PolyMac.app` — 메뉴바 앱 (LSUIElement)
- `PolyMacFinderSync.appex` — Finder 툴바/우클릭 메뉴
- `PolyMacUninstaller.app` — 열 때만 실행되는 삭제 도구

빌드하려면 Xcode 16+가 필요합니다 (Command Line Tools만으로는 앱 확장 빌드 불가).
