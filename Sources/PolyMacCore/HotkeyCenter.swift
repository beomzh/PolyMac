import AppKit
import Carbon.HIToolbox
import os

/// 전역 단축키 조합. modifiers는 Carbon 값.
public struct KeyCombo: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: UInt32(cmdKey))
        public static let shift = Modifiers(rawValue: UInt32(shiftKey))
        public static let option = Modifiers(rawValue: UInt32(optionKey))
        public static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers

    public init(_ keyCode: Int, _ modifiers: Modifiers) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
    }

    /// 키 입력 이벤트에서 조합을 만든다 (단축키 녹화용).
    public init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        self.init(Int(event.keyCode), m)
    }

    /// 글자 키만 단독으로 가로채면 타이핑이 막히므로 ⌘·⌃·⌥ 중 하나가 있거나 F키여야 한다.
    public var isUsableAsGlobalHotkey: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty || Self.functionKeys.contains(Int(keyCode))
    }

    /// "⌃⌥⌘←" 형식
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (Self.keyNames[Int(keyCode)] ?? "#\(keyCode)")
    }

    /// UserDefaults 저장 형식 "keyCode:modifiers"
    var storageString: String { "\(keyCode):\(modifiers.rawValue)" }

    init?(storageString: String) {
        let parts = storageString.split(separator: ":").compactMap { UInt32($0) }
        guard parts.count == 2 else { return nil }
        self.keyCode = parts[0]
        self.modifiers = Modifiers(rawValue: parts[1])
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
    ]

    private static let keyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"),
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"), (kVK_ANSI_4, "4"),
            (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        ]
        letters.forEach { names[$0.0] = $0.1 }
        for (i, code) in functionKeys.sorted().enumerated() { names[code] = "F\(i + 1)" }
        return names
    }()
}

/// Carbon RegisterEventHotKey 기반 전역 단축키. 권한이 필요 없고 가장 가볍다.
/// 사용자가 바꾼 조합은 UserDefaults `hotkey.<모듈>.<동작>`에 저장된다 ("none" = 사용 안 함).
@MainActor
public final class HotkeyCenter {
    public static let shared = HotkeyCenter()

    public struct Registration: Sendable, Identifiable {
        /// "window.left" 처럼 모듈 id + 동작 id
        public let key: String
        public var id: String { key }
        public let name: String
        public let owner: String
        /// nil = 기본으로 꺼 둔 단축키 (사용자가 직접 지정해야 동작)
        public let defaultCombo: KeyCombo?
        /// nil = 사용자가 끈 단축키
        public let combo: KeyCombo?
        /// combo가 있는데 false면 다른 앱이 이미 같은 조합을 쓰고 있다.
        public let isRegistered: Bool
        /// 전역 단축키가 아닌 경우 설명 (예: "Finder 안에서만")
        public let note: String?
    }

    private struct Entry {
        let key: String
        let name: String
        let owner: String
        let defaultCombo: KeyCombo?
        let handler: @MainActor () -> Void
        /// 전역 등록 없이 조합만 관리하는 단축키 (Finder 잘라내기처럼 특정 앱 안에서 직접 처리)
        var onLocalChange: (@MainActor (KeyCombo?) -> Void)?
        var note: String?
        var combo: KeyCombo?
        var ref: EventHotKeyRef?
        var hotKeyID: UInt32 = 0
    }

    private var order: [String] = []
    private var entries: [String: Entry] = [:]
    private var keyForID: [UInt32: String] = [:]
    private var nextID: UInt32 = 1
    private var isSuspended = false
    private var handlerInstalled = false
    private let logger = Logger(subsystem: "dev.polymac", category: "hotkey")

    private init() {}

    public var registrations: [Registration] {
        order.compactMap { entries[$0] }.map {
            Registration(key: $0.key, name: $0.name, owner: $0.owner, defaultCombo: $0.defaultCombo,
                         combo: $0.combo, isRegistered: $0.onLocalChange != nil ? $0.combo != nil : $0.ref != nil,
                         note: $0.note)
        }
    }

    public func register(key: String, defaultCombo: KeyCombo?, name: String, owner: String, handler: @escaping @MainActor () -> Void) {
        installHandlerIfNeeded()
        if entries[key] == nil { order.append(key) }
        unregisterRef(key)
        entries[key] = Entry(key: key, name: name, owner: owner, defaultCombo: defaultCombo, handler: handler,
                             combo: storedCombo(for: key, default: defaultCombo))
        apply(key)
    }

    /// 전역으로 등록하지 않고 사용자가 바꾼 조합만 알려 주는 단축키.
    /// 녹화 중(suspend)에는 nil을 알려 잠시 끈다.
    public func registerLocal(key: String, defaultCombo: KeyCombo, name: String, owner: String, note: String,
                              onChange: @escaping @MainActor (KeyCombo?) -> Void) {
        if entries[key] == nil { order.append(key) }
        unregisterRef(key)
        entries[key] = Entry(key: key, name: name, owner: owner, defaultCombo: defaultCombo, handler: {},
                             onLocalChange: onChange, note: note,
                             combo: storedCombo(for: key, default: defaultCombo))
        apply(key)
    }

    public func unregister(owner: String) {
        for key in order where entries[key]?.owner == owner {
            unregisterRef(key)
            entries[key] = nil
        }
        order.removeAll { entries[$0] == nil }
    }

    // MARK: - 사용자 변경

    /// nil이면 사용 안 함. 기본값과 같으면 저장값을 지운다.
    public func setCombo(_ combo: KeyCombo?, for key: String) {
        guard var entry = entries[key] else { return }
        let defaultsKey = "hotkey.\(key)"
        if combo == entry.defaultCombo {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(combo?.storageString ?? "none", forKey: defaultsKey)
        }
        entry.combo = combo
        entries[key] = entry
        apply(key)
        logger.notice("hotkey \(key, privacy: .public) -> \(combo?.display ?? "none", privacy: .public)")
    }

    public func resetToDefault(_ key: String) {
        guard let entry = entries[key] else { return }
        setCombo(entry.defaultCombo, for: key)
    }

    public func resetAll() {
        order.forEach(resetToDefault)
    }

    /// PolyMac 안에서 같은 조합을 쓰는 다른 단축키
    public func conflict(for combo: KeyCombo, excluding key: String) -> Registration? {
        registrations.first { $0.key != key && $0.combo == combo }
    }

    /// 단축키를 녹화하는 동안에는 등록을 잠시 풀어야 키 입력이 녹화 창으로 들어온다.
    public func suspend() {
        isSuspended = true
        order.forEach(unregisterRef)
    }

    public func resume() {
        isSuspended = false
        order.forEach(apply)
    }

    // MARK: - 내부

    private func storedCombo(for key: String, default defaultCombo: KeyCombo?) -> KeyCombo? {
        guard let stored = UserDefaults.standard.string(forKey: "hotkey.\(key)") else { return defaultCombo }
        if stored == "none" { return nil }
        return KeyCombo(storageString: stored) ?? defaultCombo
    }

    private func apply(_ key: String) {
        unregisterRef(key)
        if let local = entries[key], let onChange = local.onLocalChange {
            onChange(isSuspended ? nil : local.combo)
            return
        }
        guard !isSuspended, var entry = entries[key], let combo = entry.combo else { return }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x504D_4143), id: id) // 'PMAC'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            entry.ref = ref
            entry.hotKeyID = id
            keyForID[id] = key
        } else {
            logger.error("hotkey conflict \(combo.display, privacy: .public) (\(entry.name, privacy: .public)) status=\(status)")
        }
        entries[key] = entry
    }

    private func unregisterRef(_ key: String) {
        guard var entry = entries[key], let ref = entry.ref else { return }
        UnregisterEventHotKey(ref)
        keyForID[entry.hotKeyID] = nil
        entry.ref = nil
        entries[key] = entry
    }

    fileprivate func fire(_ id: UInt32) {
        guard let key = keyForID[id] else { return }
        entries[key]?.handler()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            // Carbon 이벤트는 메인 스레드에서 전달된다
            MainActor.assumeIsolated { HotkeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
