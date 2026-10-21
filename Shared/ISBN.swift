import Foundation

/// Reading an ISBN from what the reader typed or a barcode the camera saw. Pure and Foundation-only.
///
/// Every answer is the 13-digit form, so a book typed as an ISBN-10 and the same book scanned from its EAN-13 barcode
/// look the same. Checksums are verified, so a misread barcode or a typo is refused instead of looked up.
enum ISBN {
    /// The ISBN-13 in `text`, or nil. Accepts hyphens and spaces ("978-0-261-10221-7"), an "ISBN" prefix, and the
    /// ISBN-10 form with an `X` check digit, which is converted.
    static func parse(_ text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if body.hasPrefix("ISBN") { body = String(body.dropFirst(4)) }
        let kept = body.filter { $0 != "-" && $0 != " " && $0 != ":" }
        guard kept.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "X") }) else { return nil }
        switch kept.count {
        case 13 where !kept.contains("X"):
            return isValid13(kept) ? kept : nil
        case 10:
            return isValid10(kept) ? convert10(kept) : nil
        default:
            return nil
        }
    }

    /// The ISBN in a scanned barcode payload: an EAN-13 starting 978 or 979 ("Bookland"). The price barcode beside it
    /// (EAN-5) and other products' barcodes are refused.
    static func fromBarcode(_ payload: String) -> String? {
        let digits = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 13, digits.hasPrefix("978") || digits.hasPrefix("979") else { return nil }
        return parse(digits)
    }

    /// True when `text` is shaped like an ISBN someone is typing (digits, hyphens, maybe an X), long enough that it
    /// is not a title such as "1984".
    static func looksLikeISBN(_ text: String) -> Bool {
        let kept = text.uppercased().filter { $0 != "-" && $0 != " " }
        return kept.count >= 9 && kept.allSatisfy { $0.isASCII && ($0.isNumber || $0 == "X") }
    }

    // MARK: Checksums

    private static func digits(_ text: String) -> [Int] {
        text.map { $0 == "X" ? 10 : Int(String($0)) ?? 0 }
    }

    private static func isValid13(_ text: String) -> Bool {
        let d = digits(text)
        let sum = d.enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
        return sum % 10 == 0
    }

    private static func isValid10(_ text: String) -> Bool {
        // Only the check digit may be an X.
        guard !text.dropLast().contains("X") else { return false }
        let d = digits(text)
        let sum = d.enumerated().reduce(0) { $0 + $1.element * (10 - $1.offset) }
        return sum % 11 == 0
    }

    private static func convert10(_ text: String) -> String {
        let body = "978" + text.dropLast()
        let d = digits(body)
        let sum = d.enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
        return body + String((10 - sum % 10) % 10)
    }
}
