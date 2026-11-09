import AppKit
import OCRModule

// 글자 인식 일꾼으로 띄워졌으면 앱을 띄우지 않고 인식만 하다 끝난다 (OCRWorker)
if CommandLine.arguments.dropFirst().first == OCRWorker.argument { OCRWorker.serve() }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // 메뉴바 전용 (Dock 아이콘 없음)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
