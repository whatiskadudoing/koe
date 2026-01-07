public struct Language: Codable, Sendable, Equatable, Hashable {
    public let code: String
    public let name: String
    public let flag: String

    public init(code: String, name: String, flag: String) {
        self.code = code
        self.name = name
        self.flag = flag
    }

    public static let auto = Language(code: "auto", name: "Auto-detect", flag: "🌐")
    public static let english = Language(code: "en", name: "English", flag: "🇺🇸")
    public static let spanish = Language(code: "es", name: "Spanish", flag: "🇪🇸")
    public static let portuguese = Language(code: "pt", name: "Portuguese", flag: "🇧🇷")
    public static let french = Language(code: "fr", name: "French", flag: "🇫🇷")
    public static let german = Language(code: "de", name: "German", flag: "🇩🇪")
    public static let italian = Language(code: "it", name: "Italian", flag: "🇮🇹")
    public static let japanese = Language(code: "ja", name: "Japanese", flag: "🇯🇵")
    public static let korean = Language(code: "ko", name: "Korean", flag: "🇰🇷")
    public static let chinese = Language(code: "zh", name: "Chinese", flag: "🇨🇳")

    public static let all: [Language] = [
        .auto, .english, .spanish, .portuguese, .french,
        .german, .italian, .japanese, .korean, .chinese
    ]

    public var isAuto: Bool { code == "auto" }
}
