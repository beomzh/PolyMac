# App

앱 번들 설정 파일. 번들 조립과 서명은 `scripts/build-app.sh`가 한다.

- `Info.plist` — 번들 정보 템플릿 (`__VERSION__` 등은 빌드 때 `VERSION` 파일로 채움), 메뉴바 전용(LSUIElement), 권한 요청 문구
- `PolyMac.entitlements` — Hardened Runtime에서 Finder에 Apple Events를 보내기 위한 권한

Finder 우클릭 메뉴(Finder Sync 확장)는 앱 확장 빌드가 필요해 Xcode 프로젝트가 생기면 여기에 추가한다.
