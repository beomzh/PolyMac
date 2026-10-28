import AppKit
import Carbon.HIToolbox

public extension NSEvent {
    /// 누른 자판 위치의 영문 소문자·숫자 (한글 입력 상태에서도 R 자리는 "r").
    /// charactersIgnoringModifiers는 입력 소스를 따라 "ㄱ"이 되므로 단축키 판단에는 이것을 쓴다.
    /// 영문·숫자 자리가 아니면 원래 글자를 돌려준다 (↩는 "\r").
    var latinKey: String? {
        if let mapped = Self.latinKeys[Int(keyCode)] { return mapped }
        return charactersIgnoringModifiers?.lowercased()
    }

    private static let latinKeys: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f",
        kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r",
        kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Return: "\r", kVK_ANSI_KeypadEnter: "\r",
    ]
}
