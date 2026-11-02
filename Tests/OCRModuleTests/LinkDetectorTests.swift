import Foundation
import Testing
@testable import OCRModule

@Test func findsWebLinksInOrderOnce() {
    let text = "자세한 내용은 https://github.com/beomzh/PolyMac 또는 help@example.com, 다시 https://github.com/beomzh/PolyMac"
    #expect(LinkDetector.links(in: text).map(\.absoluteString) == ["https://github.com/beomzh/PolyMac"])
}

@Test func bareDomainsBecomeHTTPSAndExplicitHTTPStays() {
    #expect(LinkDetector.links(in: "주소: example.com/docs").map(\.absoluteString) == ["https://example.com/docs"])
    #expect(LinkDetector.links(in: "http://intranet.local/wiki").first?.scheme == "http")
}

@Test func ignoresOtherSchemesAndLimits() {
    #expect(LinkDetector.links(in: "mail help@example.com, tel 010-1234-5678, ftp://files.example.com").isEmpty)
    let many = (1...5).map { "https://a\($0).example.com" }.joined(separator: " ")
    #expect(LinkDetector.links(in: many).count == 3)
}

@Test func buttonTitleShowsHost() {
    #expect(LinkDetector.title(URL(string: "https://github.com/beomzh/PolyMac")!).contains("github.com/beomzh/PolyMac"))
}
