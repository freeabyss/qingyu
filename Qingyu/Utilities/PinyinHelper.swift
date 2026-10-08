import Foundation

/// Pinyin conversion helper for Chinese-to-Latin matching.
///
/// Converts Chinese characters into their Mandarin pinyin (without tones)
/// so that users can search Chinese content by typing Latin characters.
///
/// Example:
/// - `toPinyin("采购合同")` -> `"caigouhetong"`
/// - `toInitials("采购合同")` -> `"cght"`
///
/// Conversion uses `CFStringTransform` with `kCFStringTransformMandarinLatin`
/// followed by `kCFStringTransformStripDiacritics` to drop tone marks.
///
/// ## Performance
/// - Pure ASCII strings short-circuit (lowercased without transform).
/// - Results are memoised in a thread-safe `NSCache` capped at 5,000 entries
///   to bound memory while still giving high hit rates for repeated
///   re-indexing of clipboard/app/file names.
enum PinyinHelper {

    // MARK: - Caches

    private static let pinyinCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 5_000
        return cache
    }()

    private static let initialsCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 5_000
        return cache
    }()

    // MARK: - Public API

    /// Convert a string to its full pinyin form (lowercased, no spaces, no tones).
    ///
    /// - Parameter input: Source string (may mix Latin and CJK characters).
    /// - Returns: A lowercase Latin representation. Non-CJK characters are
    ///   preserved as-is and lowercased. For ASCII-only input the function
    ///   short-circuits and only lowercases.
    static func toPinyin(_ input: String) -> String {
        guard !input.isEmpty else { return "" }

        // Fast path: ASCII-only strings don't need transform
        if isASCIIOnly(input) {
            return input.lowercased()
        }

        let key = input as NSString
        if let cached = pinyinCache.object(forKey: key) {
            return cached as String
        }

        let spaced = transformToSpacedPinyin(input)
        let collapsed = spaced
            .replacingOccurrences(of: " ", with: "")
            .lowercased()

        pinyinCache.setObject(collapsed as NSString, forKey: key)
        return collapsed
    }

    /// Extract the leading character of each pinyin syllable.
    ///
    /// Example: `"采购合同"` -> `"cght"`; `"Sublime Text"` -> `"st"`;
    /// `"Visual Studio Code"` -> `"vsc"`; `"Safari"` -> `"s"`.
    ///
    /// For ASCII-only input, word boundaries are derived from whitespace and
    /// camelCase transitions so multi-word app names are still searchable by
    /// their initials. For CJK input we rely on CFStringTransform's space
    /// separation between pinyin syllables.
    ///
    /// - Parameter input: Source string.
    /// - Returns: Concatenated lowercase initials.
    static func toInitials(_ input: String) -> String {
        guard !input.isEmpty else { return "" }

        // Fast path: pure ASCII → split on whitespace + camelCase boundaries
        if isASCIIOnly(input) {
            return latinInitials(input)
        }

        let key = input as NSString
        if let cached = initialsCache.object(forKey: key) {
            return cached as String
        }

        let spaced = transformToSpacedPinyin(input).lowercased()
        let syllables = spaced.split(separator: " ", omittingEmptySubsequences: true)
        let initials = syllables.compactMap { $0.first.map(String.init) }.joined()

        initialsCache.setObject(initials as NSString, forKey: key)
        return initials
    }

    /// Clear all cached pinyin results. Primarily used by tests.
    static func clearCache() {
        pinyinCache.removeAllObjects()
        initialsCache.removeAllObjects()
    }

    // MARK: - Internals

    /// Run CFStringTransform to produce space-separated, tone-free pinyin.
    private static func transformToSpacedPinyin(_ input: String) -> String {
        let mutable = NSMutableString(string: input) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return mutable as String
    }

    /// Return true if every scalar in `input` is within the ASCII range.
    private static func isASCIIOnly(_ input: String) -> Bool {
        for scalar in input.unicodeScalars where scalar.value > 127 {
            return false
        }
        return true
    }

    /// Extract initials from a Latin-only string.
    ///
    /// Splits on whitespace, then within each token also splits at camelCase
    /// transitions and digit/letter boundaries to surface meaningful initials.
    /// Examples:
    /// - `"Sublime Text"` -> `"st"`
    /// - `"VSCode"` -> `"vsc"`
    /// - `"iTerm2"` -> `"it"` (camelCase + digit boundary not used past 2 letters)
    /// - `"Safari"` -> `"s"`
    private static func latinInitials(_ input: String) -> String {
        var initials: [Character] = []
        let tokens = input.split { $0.isWhitespace || $0 == "-" || $0 == "_" }
        for token in tokens {
            let chars = Array(token)
            for idx in chars.indices {
                let ch = chars[idx]
                if idx == 0 {
                    initials.append(Character(ch.lowercased()))
                    continue
                }

                let previous = chars[idx - 1]
                let next = idx + 1 < chars.count ? chars[idx + 1] : nil

                // Lowercase/digit → uppercase starts a camelCase word.
                // Consecutive uppercase acronym letters are also initials when
                // followed by another uppercase letter, so VSCode becomes vsc
                // while Safari remains s and Code remains c.
                if ch.isUppercase,
                   previous.isLowercase || previous.isNumber || (previous.isUppercase && next != nil) {
                    initials.append(Character(ch.lowercased()))
                }
            }
        }
        return String(initials)
    }
}
