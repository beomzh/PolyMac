# CHANGELOG

개발 이력 (커밋 단위). 사용자용 변경 요약은 GitHub Releases를 본다 — 규칙은 docs/RELEASING.md.

[2026-10-27 14:13]
- [Added] - README.md, docs/*.md: 프로젝트 컨셉·아키텍처·로드맵·보안·릴리즈 규칙·참고자료 문서 작성
- [Added] - Package.swift, Sources/PolyMacCore: 모듈 계약(PolyMacModule)과 lazy 활성화 레지스트리
- [Added] - Sources/NormalizeModule/HangulNormalizer.swift: NFD → NFC 파일명 변환 (POSIX rename, APFS 2단계 변경)
- [Added] - Sources/OrganizeModule: 다운로드 자동 정리 규칙 모델·엔진·프리셋, 경로 탈출 방지
- [Added] - Sources/ClipboardModule/ClipboardItem.swift: 클립보드 항목 모델과 저장 제외 규칙
- [Added] - Sources/{Window,Capture,OCR,Finder}Module, Sources/UninstallerCore: 모듈 골격
- [Added] - Tests/: 레지스트리·NFC 변환·규칙 엔진 테스트
- [Added] - LICENSE, CONTRIBUTING.md, THIRD_PARTY_NOTICES.md, VERSION(0.0.1): MIT 라이선스와 기여·고지 문서

