import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PolyMacCore
import os

/// ⌘X 잘라내기용 키 이벤트 탭 (⌘X → ⌘C, 대기 중 ⌘V → ⌘⌥V).
///
/// 활성 이벤트 탭은 Mac 전체의 키 입력이 콜백을 거쳐 가므로, 콜백이 막히면 시스템 키 입력이 멈춘다.
/// 그래서 메인 스레드(AppleScript·메뉴·모달로 잠깐씩 막힐 수 있음)가 아닌 전용 스레드에서 돌리고,
/// 콜백 안의 손쉬운 사용 API 호출에는 짧은 타임아웃을 건다. 키 입력은 판단에만 쓰고 저장하지 않는다 (docs/SECURITY.md 2).
final class FinderKeyTap: @unchecked Sendable {
    private struct State {
        var finderIsFrontmost = false
        var cutPending = false
        var cut: KeyCombo? = KeyCombo(kVK_ANSI_X, [.command])
        var paste: KeyCombo? = KeyCombo(kVK_ANSI_V, [.command])
        var tap: CFMachPort?
        var runLoop: CFRunLoop?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let systemWide = AXUIElementCreateSystemWide()
    private let onCut: @Sendable () -> Void
    private let logger = Logger(subsystem: "dev.polymac", category: "finder")

    init(onCut: @escaping @Sendable () -> Void) {
        self.onCut = onCut
        // Finder가 응답하지 않아도 키 입력을 0.1초 넘게 붙잡지 않는다 (기본값은 6초)
        AXUIElementSetMessagingTimeout(systemWide, 0.1)
    }

    var isRunning: Bool { state.withLock { $0.tap != nil } }

    func setFinderFrontmost(_ value: Bool) {
        state.withLock {
            $0.finderIsFrontmost = value
            if !value { $0.cutPending = false }
        }
    }

    /// 단축키 설정에서 바꾼 잘라내기·붙여넣기 조합 (nil = 사용 안 함)
    func setShortcuts(cut: KeyCombo?, paste: KeyCombo?) {
        state.withLock {
            $0.cut = cut
            $0.paste = paste
            $0.cutPending = false
        }
    }

    /// 손쉬운 사용 권한이 없으면 false
    func start() -> Bool {
        guard !isRunning else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: finderKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [state] in
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            state.withLock { $0.runLoop = runLoop }
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "PolyMac.FinderKeyTap"
        thread.qualityOfService = .userInteractive
        state.withLock { $0.tap = tap }
        thread.start()
        ready.wait()
        logger.notice("event tap started on dedicated thread")
        return true
    }

    func stop() {
        let (tap, runLoop) = state.withLock { s -> (CFMachPort?, CFRunLoop?) in
            defer { s.tap = nil; s.runLoop = nil; s.cutPending = false }
            return (s.tap, s.runLoop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = state.withLock({ $0.tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            logger.error("event tap was disabled by the system (\(type.rawValue)) — re-enabled")
            return pass
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != SyntheticEvent.marker
        else { return pass }

        let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let mods = event.flags.intersection(modifierMask)
        guard !mods.isEmpty else { return pass }
        let (finderFront, cut, paste) = state.withLock { ($0.finderIsFrontmost, $0.cut, $0.paste) }
        guard finderFront else { return pass }

        let pressed = KeyCombo(Int(event.getIntegerValueField(.keyboardEventKeycode)), Self.modifiers(mods))
        let isCopy = pressed == KeyCombo(kVK_ANSI_C, [.command])
        guard pressed == cut || pressed == paste || isCopy, !isEditingText() else { return pass }

        let base = event.flags.subtracting(modifierMask)
        if pressed == cut {
            // Finder의 "복사"(⌘C)로 바꾸고, 다음 붙여넣기를 "이동"으로 바꿀 준비
            rewrite(event, keyCode: kVK_ANSI_C, character: 0x63, flags: base.union(.maskCommand))
            state.withLock { $0.cutPending = true }
            onCut()
        } else if pressed == paste {
            let pending = state.withLock { s -> Bool in
                defer { s.cutPending = false }
                return s.cutPending
            }
            // 잘라내기 대기 중이면 Finder의 "여기로 항목 이동"(⌥⌘V)
            if pending { rewrite(event, keyCode: kVK_ANSI_V, character: 0x76, flags: base.union([.maskCommand, .maskAlternate])) }
        } else {
            state.withLock { $0.cutPending = false } // 그냥 복사하면 잘라내기 취소
        }
        return pass
    }

    private func rewrite(_ event: CGEvent, keyCode: Int, character: UniChar, flags: CGEventFlags) {
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
        var c = character
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        event.flags = flags
    }

    private static func modifiers(_ flags: CGEventFlags) -> KeyCombo.Modifiers {
        var m: KeyCombo.Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        return m
    }

    /// 파일 이름 편집·검색창 입력 중이면 ⌘X/⌘V를 그대로 둔다. 응답이 없으면(타임아웃) 건드리지 않는 쪽으로.
    private func isEditingText() -> Bool {
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return result == .cannotComplete // 타임아웃 등 확인 불가 → 텍스트 편집 중으로 간주해 통과
        }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let name = role as? String
        return name == kAXTextFieldRole || name == kAXTextAreaRole || name == "AXSearchField" || name == kAXComboBoxRole
    }
}

private func finderKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<FinderKeyTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
