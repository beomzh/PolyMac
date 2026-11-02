# 개인 Homebrew tap(beomzh/homebrew-tap)의 Casks/polymac.rb 원본.
# 릴리즈할 때 version·sha256을 바꿔 tap 저장소에 올린다 — docs/RELEASING.md 4-8.
#   brew tap beomzh/tap && brew trust --cask beomzh/tap/polymac && brew install --cask beomzh/tap/polymac
cask "polymac" do
  version "0.2.0"
  sha256 "19e7858c87858ca8c78cb4584b370d56004828f93843f0053b8f3fd20bab9878"

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

  uninstall quit: "dev.polymac.app"

  zap trash: [
    "~/Library/Application Support/PolyMac",
    "~/Library/Caches/dev.polymac.app",
    "~/Library/HTTPStorages/dev.polymac.app",
    "~/Library/Preferences/dev.polymac.app.plist",
  ]

  caveats <<~EOS
    PolyMac is not notarized by Apple. On first launch macOS may block it:
    open System Settings > Privacy & Security and click "Open Anyway".
  EOS
end
