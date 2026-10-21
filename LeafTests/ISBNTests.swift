import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct ISBNTests {
    @Test func parsesThirteenDigits() {
        let plain: String? = ISBN.parse("9780261102217")
        let hyphens: String? = ISBN.parse("978-0-261-10221-7")
        let prefixed: String? = ISBN.parse(" ISBN: 978 0 261 10221 7 ")
        #expect(plain == "9780261102217")
        #expect(hyphens == "9780261102217")
        #expect(prefixed == "9780261102217")
    }

    @Test func convertsTenDigits() {
        let hobbit: String? = ISBN.parse("0-261-10221-4")
        let withX: String? = ISBN.parse("0-8044-2957-X")
        let lowerX: String? = ISBN.parse("080442957x")
        #expect(hobbit == "9780261102217")
        #expect(withX == "9780804429573")
        #expect(lowerX == "9780804429573")
    }

    @Test func refusesBadChecksumsAndShapes() {
        let typo: String? = ISBN.parse("9780261102218")
        let badTen: String? = ISBN.parse("0261102215")
        let xInside: String? = ISBN.parse("02611X2214")
        let title: String? = ISBN.parse("1984")
        let words: String? = ISBN.parse("the hobbit")
        let empty: String? = ISBN.parse("")
        #expect(typo == nil)
        #expect(badTen == nil)
        #expect(xInside == nil)
        #expect(title == nil)
        #expect(words == nil)
        #expect(empty == nil)
    }

    @Test func barcodesMustBeBookland() {
        let book: String? = ISBN.fromBarcode("9780261102217")
        let newer: String? = ISBN.fromBarcode("9798602477429")
        let cereal: String? = ISBN.fromBarcode("5000159484695")
        let price: String? = ISBN.fromBarcode("51299")
        #expect(book == "9780261102217")
        #expect(newer == "9798602477429")
        #expect(cereal == nil)
        #expect(price == nil)
    }

    @Test func spotsISBNsBeingTyped() {
        let typing: Bool = ISBN.looksLikeISBN("978-0-261")
        let year: Bool = ISBN.looksLikeISBN("1984")
        let title: Bool = ISBN.looksLikeISBN("Dune 2")
        #expect(typing)
        #expect(!year)
        #expect(!title)
    }
}
