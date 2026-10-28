import AppKit

/// 안내 토스트의 모양. 환경 설정 › 알림에서 바꾸고 UserDefaults("toast.*")에 저장한다.
/// 색을 정하지 않으면(nil) 시스템 라이트·다크 모드를 따른다.
public struct ToastStyle: Equatable, Sendable {
    /// "#RRGGBB" 또는 "#RRGGBBAA" (sRGB)
    public var textColor: String?
    public var backgroundColor: String?
    public var fontSize: Double = 13
    /// 알림창 최대 너비 — 글이 길면 이 너비에서 줄을 바꾼다
    public var maxWidth: Double = 420
    /// 글자와 창 가장자리 사이 여백
    public var padding: Double = 12

    public static let fontSizes: ClosedRange<Double> = 10...28
    public static let maxWidths: ClosedRange<Double> = 240...800
    public static let paddings: ClosedRange<Double> = 6...32

    public init() {}

    /// 범위를 벗어난 값(직접 defaults write 한 경우 등)은 가장 가까운 허용값으로
    public var clamped: ToastStyle {
        var s = self
        s.fontSize = min(max(fontSize, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
        s.maxWidth = min(max(maxWidth, Self.maxWidths.lowerBound), Self.maxWidths.upperBound)
        s.padding = min(max(padding, Self.paddings.lowerBound), Self.paddings.upperBound)
        if let t = textColor, Self.color(hex: t) == nil { s.textColor = nil }
        if let b = backgroundColor, Self.color(hex: b) == nil { s.backgroundColor = nil }
        return s
    }

    // MARK: - 저장

    private enum Key {
        static let text = "toast.textColor", background = "toast.backgroundColor"
        static let font = "toast.fontSize", width = "toast.maxWidth", padding = "toast.padding"
    }

    public static func load(from defaults: UserDefaults = .standard) -> ToastStyle {
        var s = ToastStyle()
        s.textColor = defaults.string(forKey: Key.text)
        s.backgroundColor = defaults.string(forKey: Key.background)
        if defaults.object(forKey: Key.font) != nil { s.fontSize = defaults.double(forKey: Key.font) }
        if defaults.object(forKey: Key.width) != nil { s.maxWidth = defaults.double(forKey: Key.width) }
        if defaults.object(forKey: Key.padding) != nil { s.padding = defaults.double(forKey: Key.padding) }
        return s.clamped
    }

    public func save(to defaults: UserDefaults = .standard) {
        let s = clamped
        let d = ToastStyle()
        // 기본값은 지워 둔다 — 나중에 기본값이 바뀌면 따라가게
        func put(_ value: Any?, _ key: String) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
        put(s.textColor, Key.text)
        put(s.backgroundColor, Key.background)
        put(s.fontSize == d.fontSize ? nil : s.fontSize, Key.font)
        put(s.maxWidth == d.maxWidth ? nil : s.maxWidth, Key.width)
        put(s.padding == d.padding ? nil : s.padding, Key.padding)
    }

    public static var current: ToastStyle {
        get { load() }
        set { newValue.save() }
    }

    // MARK: - 색

    public static func hex(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        let v = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
        return v[3] == 255 ? String(format: "#%02X%02X%02X", v[0], v[1], v[2]) : String(format: "#%02X%02X%02X%02X", v[0], v[1], v[2], v[3])
    }

    public static func color(hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let rgba = s.count == 6 ? value << 8 | 0xFF : value
        func part(_ shift: UInt64) -> CGFloat { CGFloat((rgba >> shift) & 0xFF) / 255 }
        return NSColor(srgbRed: part(24), green: part(16), blue: part(8), alpha: part(0))
    }
}
