import Foundation

/// A language Whisper can transcribe. `code` is Whisper's ISO 639-1 style code ("en", "zh", "yue").
struct Language: Identifiable, Hashable, Codable, Sendable {
    let code: String
    let englishName: String
    let nativeName: String

    var id: String { code }

    /// Sentinel shown in pickers for automatic detection (not part of `all`).
    static let autoCode = "auto"

    static func named(_ code: String?) -> Language? {
        guard let code else { return nil }
        return all.first { $0.code == code }
    }

    /// Languages to surface first in pickers.
    static let popularCodes: [String] = ["en", "es", "fr", "de", "it", "pt", "nl", "zh", "ja", "ko", "hi", "ar", "ru"]

    static var popular: [Language] { popularCodes.compactMap(named) }

    /// Every language a Whisper multilingual model accepts: the classic 99 plus Cantonese ("yue"),
    /// which large-v3 added. Codes match `Constants.languages` in WhisperKit, so any `code` here is
    /// valid for `DecodingOptions.language`. Sorted by English name.
    static let all: [Language] = [
        Language(code: "af", englishName: "Afrikaans", nativeName: "Afrikaans"),
        Language(code: "sq", englishName: "Albanian", nativeName: "Shqip"),
        Language(code: "am", englishName: "Amharic", nativeName: "አማርኛ"),
        Language(code: "ar", englishName: "Arabic", nativeName: "العربية"),
        Language(code: "hy", englishName: "Armenian", nativeName: "Հայերեն"),
        Language(code: "as", englishName: "Assamese", nativeName: "অসমীয়া"),
        Language(code: "az", englishName: "Azerbaijani", nativeName: "Azərbaycan dili"),
        Language(code: "ba", englishName: "Bashkir", nativeName: "Башҡорт теле"),
        Language(code: "eu", englishName: "Basque", nativeName: "Euskara"),
        Language(code: "be", englishName: "Belarusian", nativeName: "Беларуская"),
        Language(code: "bn", englishName: "Bengali", nativeName: "বাংলা"),
        Language(code: "bs", englishName: "Bosnian", nativeName: "Bosanski"),
        Language(code: "br", englishName: "Breton", nativeName: "Brezhoneg"),
        Language(code: "bg", englishName: "Bulgarian", nativeName: "Български"),
        Language(code: "yue", englishName: "Cantonese", nativeName: "粵語"),
        Language(code: "ca", englishName: "Catalan", nativeName: "Català"),
        Language(code: "zh", englishName: "Chinese", nativeName: "中文"),
        Language(code: "hr", englishName: "Croatian", nativeName: "Hrvatski"),
        Language(code: "cs", englishName: "Czech", nativeName: "Čeština"),
        Language(code: "da", englishName: "Danish", nativeName: "Dansk"),
        Language(code: "nl", englishName: "Dutch", nativeName: "Nederlands"),
        Language(code: "en", englishName: "English", nativeName: "English"),
        Language(code: "et", englishName: "Estonian", nativeName: "Eesti"),
        Language(code: "fo", englishName: "Faroese", nativeName: "Føroyskt"),
        Language(code: "fi", englishName: "Finnish", nativeName: "Suomi"),
        Language(code: "fr", englishName: "French", nativeName: "Français"),
        Language(code: "gl", englishName: "Galician", nativeName: "Galego"),
        Language(code: "ka", englishName: "Georgian", nativeName: "ქართული"),
        Language(code: "de", englishName: "German", nativeName: "Deutsch"),
        Language(code: "el", englishName: "Greek", nativeName: "Ελληνικά"),
        Language(code: "gu", englishName: "Gujarati", nativeName: "ગુજરાતી"),
        Language(code: "ht", englishName: "Haitian Creole", nativeName: "Kreyòl ayisyen"),
        Language(code: "ha", englishName: "Hausa", nativeName: "Hausa"),
        Language(code: "haw", englishName: "Hawaiian", nativeName: "ʻŌlelo Hawaiʻi"),
        Language(code: "he", englishName: "Hebrew", nativeName: "עברית"),
        Language(code: "hi", englishName: "Hindi", nativeName: "हिन्दी"),
        Language(code: "hu", englishName: "Hungarian", nativeName: "Magyar"),
        Language(code: "is", englishName: "Icelandic", nativeName: "Íslenska"),
        Language(code: "id", englishName: "Indonesian", nativeName: "Bahasa Indonesia"),
        Language(code: "it", englishName: "Italian", nativeName: "Italiano"),
        Language(code: "ja", englishName: "Japanese", nativeName: "日本語"),
        Language(code: "jw", englishName: "Javanese", nativeName: "Basa Jawa"),
        Language(code: "kn", englishName: "Kannada", nativeName: "ಕನ್ನಡ"),
        Language(code: "kk", englishName: "Kazakh", nativeName: "Қазақ тілі"),
        Language(code: "km", englishName: "Khmer", nativeName: "ភាសាខ្មែរ"),
        Language(code: "ko", englishName: "Korean", nativeName: "한국어"),
        Language(code: "lo", englishName: "Lao", nativeName: "ລາວ"),
        Language(code: "la", englishName: "Latin", nativeName: "Latina"),
        Language(code: "lv", englishName: "Latvian", nativeName: "Latviešu"),
        Language(code: "ln", englishName: "Lingala", nativeName: "Lingála"),
        Language(code: "lt", englishName: "Lithuanian", nativeName: "Lietuvių"),
        Language(code: "lb", englishName: "Luxembourgish", nativeName: "Lëtzebuergesch"),
        Language(code: "mk", englishName: "Macedonian", nativeName: "Македонски"),
        Language(code: "mg", englishName: "Malagasy", nativeName: "Malagasy"),
        Language(code: "ms", englishName: "Malay", nativeName: "Bahasa Melayu"),
        Language(code: "ml", englishName: "Malayalam", nativeName: "മലയാളം"),
        Language(code: "mt", englishName: "Maltese", nativeName: "Malti"),
        Language(code: "mi", englishName: "Maori", nativeName: "Te Reo Māori"),
        Language(code: "mr", englishName: "Marathi", nativeName: "मराठी"),
        Language(code: "mn", englishName: "Mongolian", nativeName: "Монгол"),
        Language(code: "my", englishName: "Myanmar", nativeName: "မြန်မာဘာသာ"),
        Language(code: "ne", englishName: "Nepali", nativeName: "नेपाली"),
        Language(code: "no", englishName: "Norwegian", nativeName: "Norsk"),
        Language(code: "nn", englishName: "Nynorsk", nativeName: "Nynorsk"),
        Language(code: "oc", englishName: "Occitan", nativeName: "Occitan"),
        Language(code: "ps", englishName: "Pashto", nativeName: "پښتو"),
        Language(code: "fa", englishName: "Persian", nativeName: "فارسی"),
        Language(code: "pl", englishName: "Polish", nativeName: "Polski"),
        Language(code: "pt", englishName: "Portuguese", nativeName: "Português"),
        Language(code: "pa", englishName: "Punjabi", nativeName: "ਪੰਜਾਬੀ"),
        Language(code: "ro", englishName: "Romanian", nativeName: "Română"),
        Language(code: "ru", englishName: "Russian", nativeName: "Русский"),
        Language(code: "sa", englishName: "Sanskrit", nativeName: "संस्कृतम्"),
        Language(code: "sr", englishName: "Serbian", nativeName: "Српски"),
        Language(code: "sn", englishName: "Shona", nativeName: "ChiShona"),
        Language(code: "sd", englishName: "Sindhi", nativeName: "سنڌي"),
        Language(code: "si", englishName: "Sinhala", nativeName: "සිංහල"),
        Language(code: "sk", englishName: "Slovak", nativeName: "Slovenčina"),
        Language(code: "sl", englishName: "Slovenian", nativeName: "Slovenščina"),
        Language(code: "so", englishName: "Somali", nativeName: "Soomaali"),
        Language(code: "es", englishName: "Spanish", nativeName: "Español"),
        Language(code: "su", englishName: "Sundanese", nativeName: "Basa Sunda"),
        Language(code: "sw", englishName: "Swahili", nativeName: "Kiswahili"),
        Language(code: "sv", englishName: "Swedish", nativeName: "Svenska"),
        Language(code: "tl", englishName: "Tagalog", nativeName: "Tagalog"),
        Language(code: "tg", englishName: "Tajik", nativeName: "Тоҷикӣ"),
        Language(code: "ta", englishName: "Tamil", nativeName: "தமிழ்"),
        Language(code: "tt", englishName: "Tatar", nativeName: "Татарча"),
        Language(code: "te", englishName: "Telugu", nativeName: "తెలుగు"),
        Language(code: "th", englishName: "Thai", nativeName: "ไทย"),
        Language(code: "bo", englishName: "Tibetan", nativeName: "བོད་སྐད་"),
        Language(code: "tr", englishName: "Turkish", nativeName: "Türkçe"),
        Language(code: "tk", englishName: "Turkmen", nativeName: "Türkmençe"),
        Language(code: "uk", englishName: "Ukrainian", nativeName: "Українська"),
        Language(code: "ur", englishName: "Urdu", nativeName: "اردو"),
        Language(code: "uz", englishName: "Uzbek", nativeName: "Oʻzbekcha"),
        Language(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt"),
        Language(code: "cy", englishName: "Welsh", nativeName: "Cymraeg"),
        Language(code: "yi", englishName: "Yiddish", nativeName: "ייִדיש"),
        Language(code: "yo", englishName: "Yoruba", nativeName: "Yorùbá"),
    ]
}
