# 개인 Homebrew tap(beomzh/homebrew-tap)의 Casks/polymac.rb 원본.
# 릴리즈할 때 version·sha256을 바꿔 tap 저장소에 올린다 — docs/RELEASING.md 4-8.
#   brew tap beomzh/tap && brew trust --cask beomzh/tap/polymac && brew install --cask beomzh/tap/polymac
cask "polymac" do
  version "1.0.0"
  sha256 "a636d2459a59a82833b283a79f1166de7b3da17fd3a02b1b8cde45b78b6f4bcc"

  url "https://github.com/beomzh/PolyMac/releases/download/v#{version}/PolyMac-#{version}.zip"
  name "PolyMac"
  desc "Menu bar tools: capture, OCR, clipboard history, Finder tools, window snapping"
  homepage "https://github.com/beomzh/PolyMac"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 앱 안의 Sparkle로도 업데이트할 수 있다 (사용자가 켰을 때만)
  auto_updates true
  depends_on macos: :sonoma

  app "PolyMac.app"

  # 공증받지 않고 자체 서명 인증서로 서명해, 다른 Mac은 서명을 믿지 못하고 "손상됨"으로 막는다 (그래도 열기 없음).
  # brew trust로 이 cask를 믿은 사람이 설치한 앱에서만 다운로드 표시(quarantine)를 지운다 — docs/SECURITY.md 8
  # Homebrew 7부터 postflight 블록은 deprecated — 선언형 postflight_steps로 같은 명령을 실행한다
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/PolyMac.app"],
        writable_paths: ["{{appdir}}/PolyMac.app"]
  end

  uninstall quit: "dev.polymac.app"

  zap trash: [
    "~/Library/Application Support/PolyMac",
    "~/Library/Caches/dev.polymac.app",
    "~/Library/HTTPStorages/dev.polymac.app",
    "~/Library/Preferences/dev.polymac.app.plist",
  ]

  caveats <<~EOS
    PolyMac is not notarized by Apple and is signed with its own certificate.
    This cask removes the download quarantine flag so macOS does not report
    the app as damaged. Source and signing details:
      https://github.com/beomzh/PolyMac/blob/main/docs/SECURITY.md
  EOS
end
