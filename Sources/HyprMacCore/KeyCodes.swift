/// macOS virtual key codes (ANSI layout), keyed by Hyprland-style key names.
public enum KeyCodes {
    public static let table: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26,
        "minus": 27, "8": 28, "0": 29, "bracketright": 30, "o": 31, "u": 32, "bracketleft": 33,
        "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "apostrophe": 39, "quote": 39,
        "k": 40, "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46,
        "period": 47, "tab": 48, "space": 49, "grave": 50, "backspace": 51, "escape": 53, "esc": 53,
        "delete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "-": 27, "=": 24, "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50, "\\": 42,
    ]

    public static func code(for name: String) -> UInt16? {
        table[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}
