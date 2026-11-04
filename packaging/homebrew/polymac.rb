# 개인 Homebrew tap(beomzh/homebrew-tap)의 Casks/polymac.rb 원본.
# 릴리즈할 때 version·sha256을 바꿔 tap 저장소에 올린다 — docs/RELEASING.md 4-8.
#   brew tap beomzh/tap && brew trust --cask beomzh/tap/polymac && brew install --cask beomzh/tap/polymac
cask "polymac" do
  version "0.2.4"
  sha256 "eb5d4bafad8b797a6c2f463009bc98154cca14073d9420252f2d6a2195acde57"

  url "https://github.com/beomzh/PolyMac/releases/download/v#{version}/PolyMac-#{version}.zip"
  name "PolyMac"
  desc "Menu bar utilities: capture, OCR, clipboard history, Finder tools, window snapping"
  homepage "https://github.com/beomzh/PolyMac"

  livecheck do
    url :url
    strategy :github_latest
  end

  # 앱 안의 Sparkle로도 업데이트할 수 있다 (사용자가 켰을 때만)
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "PolyMac.app"

  # 공증받지 않고 자체 서명 인증서로 서명해, 다른 Mac은 서명을 믿지 못하고 "손상됨"으로 막는다 (그래도 열기 없음).
  # brew trust로 이 cask를 믿은 사람이 설치한 앱에서만 다운로드 표시(quarantine)를 지운다 — docs/SECURITY.md 8
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/PolyMac.app"]
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
