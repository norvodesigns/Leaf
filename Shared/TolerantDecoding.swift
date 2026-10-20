import Foundation

/// Reading the library file without losing all of it to one entry this version can't read.
///
/// A tolerant decode keeps every element of a list it can read and leaves out the rest, and falls back to the
/// default for a setting it can't read, where a strict decode would fail as a whole. That matters when an older build
/// opens a file a newer one wrote (TestFlight lets a tester go back a build): an unknown shelf or tea family must cost
/// one entry, not the whole library. It is opt-in, by putting a `DecodeSkips` in the decoder's `userInfo`; without
/// one, decoding is strict as before (sync records and backup files rely on a failure to try something else).
final class DecodeSkips: @unchecked Sendable {
    /// Entries left out and settings that fell back to their defaults.
    private(set) var count = 0

    func add(_ skipped: Int) { count += max(0, skipped) }

    static let key = CodingUserInfoKey(rawValue: "leaf.decodeSkips")!

    /// A JSON decoder that decodes tolerantly and counts into this.
    func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[DecodeSkips.key] = self
        return decoder
    }
}

extension Decoder {
    /// The skip counter of a tolerant decode, or nil when decoding strictly.
    var decodeSkips: DecodeSkips? { userInfo[DecodeSkips.key] as? DecodeSkips }
}

/// One element of a list that may not decode; `value` is nil then.
private struct TolerantElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// A list, empty when missing. Tolerant (with `skips`), the elements that can't be read are left out and counted.
    func decodeList<T: Decodable>(_ type: T.Type, forKey key: Key, skips: DecodeSkips?) throws -> [T] {
        guard let skips else { return try decodeIfPresent([T].self, forKey: key) ?? [] }
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return [] }
        guard let raw = try? decode([TolerantElement<T>].self, forKey: key) else {
            skips.add(1)
            return []
        }
        let values = raw.compactMap(\.value)
        skips.add(raw.count - values.count)
        return values
    }

    /// A value with a default for when it is missing. Tolerant, one that can't be read also gets the default.
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key, or fallback: T, skips: DecodeSkips?) throws -> T {
        try decodeOptional(type, forKey: key, skips: skips) ?? fallback
    }

    /// An optional value. Tolerant, one that can't be read is nil.
    func decodeOptional<T: Decodable>(_ type: T.Type, forKey key: Key, skips: DecodeSkips?) throws -> T? {
        guard let skips else { return try decodeIfPresent(type, forKey: key) }
        do {
            return try decodeIfPresent(type, forKey: key)
        } catch {
            skips.add(1)
            return nil
        }
    }
}
