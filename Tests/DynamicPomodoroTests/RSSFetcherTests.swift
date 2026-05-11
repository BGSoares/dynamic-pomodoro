import XCTest
@testable import DynamicPomodoro

final class RSSFetcherTests: XCTestCase {

    private func source(_ name: String = "test") -> NewsFeedSource {
        NewsFeedSource(
            id: "test",
            name: name,
            url: URL(string: "https://example.invalid/feed")!,
            enabled: true
        )
    }

    func testParsesRSS2() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>LeMond wins 1989 Tour</title>
              <link>https://example.com/89</link>
              <guid>https://example.com/89</guid>
              <description><![CDATA[<p>By <b>eight</b> seconds.</p>]]></description>
              <pubDate>Mon, 11 May 2026 14:30:00 +0000</pubDate>
            </item>
            <item>
              <title>Pantani on the Galibier</title>
              <link>https://example.com/galibier</link>
              <description>Stage 15, 1998.</description>
              <pubDate>Sun, 10 May 2026 09:00:00 +0000</pubDate>
            </item>
          </channel>
        </rss>
        """
        let items = RSSFetcher.parse(data: Data(xml.utf8), source: source())
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "LeMond wins 1989 Tour")
        XCTAssertEqual(items[0].url, URL(string: "https://example.com/89"))
        XCTAssertEqual(items[0].sourceName, "test")
        XCTAssertFalse(items[0].summary.contains("<b>"), "HTML should be available in raw form for stripHTML; assert via asActivity")
        let activity = items[0].asActivity()
        XCTAssertFalse(activity.instruction.contains("<"))
        XCTAssertTrue(activity.instruction.contains("eight seconds"))
        XCTAssertEqual(activity.category, .cyclingNews)
    }

    func testParsesAtom() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Feed</title>
          <entry>
            <id>tag:example.com,2026:1</id>
            <title>Voigt's hour record</title>
            <link href="https://example.com/voigt" />
            <summary>51.110 km in an hour.</summary>
            <published>2026-05-09T12:00:00Z</published>
          </entry>
        </feed>
        """
        let items = RSSFetcher.parse(data: Data(xml.utf8), source: source("Atom"))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Voigt's hour record")
        XCTAssertEqual(items[0].url, URL(string: "https://example.com/voigt"))
        XCTAssertTrue(items[0].id.hasPrefix("news_"))
    }

    func testMalformedXMLReturnsEmpty() {
        let items = RSSFetcher.parse(data: Data("not xml at all".utf8), source: source())
        XCTAssertEqual(items, [])
    }

    func testItemsWithoutValidLinkAreDropped() {
        let xml = """
        <rss version="2.0"><channel>
          <item><title>No link</title></item>
          <item><title>Bad scheme</title><link>ftp://nope</link></item>
          <item><title>Good</title><link>https://ok.example/x</link></item>
        </channel></rss>
        """
        let items = RSSFetcher.parse(data: Data(xml.utf8), source: source())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Good")
    }

    func testIDIsStableForSameGUID() {
        let url = URL(string: "https://example.com/a")!
        let id1 = NewsItem.makeID(from: "guid-1", link: url)
        let id2 = NewsItem.makeID(from: "guid-1", link: url)
        XCTAssertEqual(id1, id2)
        XCTAssertTrue(id1.hasPrefix("news_"))
    }

    func testRFC822DateParses() {
        let d = FeedDate.parse("Mon, 11 May 2026 14:30:00 +0000")
        XCTAssertNotNil(d)
    }

    func testISO8601DateParses() {
        let d = FeedDate.parse("2026-05-09T12:00:00Z")
        XCTAssertNotNil(d)
    }

    func testSummaryClipping() {
        let long = String(repeating: "word ", count: 200)
        let clipped = NewsItem.clipSummary(long, limit: 100)
        XCTAssertLessThanOrEqual(clipped.count, 101)
        XCTAssertTrue(clipped.hasSuffix("…"))
    }
}
