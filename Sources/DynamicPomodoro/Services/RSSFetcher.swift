import Foundation

/// Fetches a single RSS 2.0 or Atom feed and returns the parsed items.
/// No external dependencies — uses URLSession + Foundation's XMLParser.
enum RSSFetcher {
    enum FetchError: Error {
        case http(Int)
        case empty
        case parse
    }

    /// Fetch + parse `source.url`, mapping each item/entry to a `NewsItem`.
    /// Network errors propagate; parse errors return an empty array so a
    /// single bad feed never fails a multi-feed refresh.
    static func fetch(source: NewsFeedSource, urlSession: URLSession = .shared) async throws -> [NewsItem] {
        var request = URLRequest(url: source.url)
        request.setValue("DynamicPomodoro/1.0 (+rss)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw FetchError.http(http.statusCode)
        }
        guard !data.isEmpty else { throw FetchError.empty }
        return parse(data: data, source: source)
    }

    /// Pure parse path — exposed so tests can feed fixture bytes directly.
    static func parse(data: Data, source: NewsFeedSource) -> [NewsItem] {
        let parser = XMLParser(data: data)
        let delegate = FeedParserDelegate(source: source)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return delegate.items
    }
}

// MARK: - Parser

/// Handles RSS 2.0 (`<item>`) and Atom (`<entry>`) in one pass. We don't
/// distinguish the flavours upfront; tags from either show up in `tag` and
/// the element-end handlers pick the right field.
private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    let source: NewsFeedSource
    var items: [NewsItem] = []

    // Per-item scratch
    private var inItem = false
    private var currentTag = ""
    private var attrs: [String: String] = [:]
    private var title = ""
    private var link = ""
    private var atomLinkHref: String?
    private var summary = ""
    private var guid: String?
    private var atomID: String?
    private var pubDate: String?
    private var updated: String?
    private var published: String?

    init(source: NewsFeedSource) {
        self.source = source
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let tag = elementName.lowercased()
        currentTag = tag
        attrs = attributeDict
        if tag == "item" || tag == "entry" {
            resetItemState()
            inItem = true
        }
        if inItem && tag == "link" {
            // Atom: <link href="..."/> — capture from attrs since the element
            // typically has no text content.
            if let href = attributeDict["href"] {
                atomLinkHref = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentTag {
        case "title":         title += string
        case "link":          link += string
        case "description":   summary += string
        case "summary":       summary += string
        case "content":       summary += string
        case "guid":          guid = (guid ?? "") + string
        case "id":            atomID = (atomID ?? "") + string
        case "pubdate":       pubDate = (pubDate ?? "") + string
        case "published":     published = (published ?? "") + string
        case "updated":       updated = (updated ?? "") + string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard inItem, let text = String(data: CDATABlock, encoding: .utf8) else { return }
        // Re-route CDATA through the character handler so the same per-tag
        // routing applies.
        self.parser(parser, foundCharacters: text)
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let tag = elementName.lowercased()
        defer { currentTag = "" }
        guard tag == "item" || tag == "entry" else { return }
        finalizeItem()
    }

    private func resetItemState() {
        title = ""; link = ""; atomLinkHref = nil; summary = ""
        guid = nil; atomID = nil; pubDate = nil; updated = nil; published = nil
    }

    private func finalizeItem() {
        inItem = false
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLink = (atomLinkHref ?? link).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let url = URL(string: resolvedLink),
              url.scheme?.hasPrefix("http") == true else { return }
        let rawGUID = (guid ?? atomID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateString = pubDate ?? published ?? updated
        let date = FeedDate.parse(dateString) ?? Date()
        let item = NewsItem(
            id: NewsItem.makeID(from: rawGUID, link: url),
            title: trimmedTitle,
            summary: summary,
            url: url,
            publishedAt: date,
            sourceID: source.id,
            sourceName: source.name
        )
        items.append(item)
    }
}

// MARK: - Date parsing

/// Feed dates land in two main shapes: RSS 2.0 uses RFC822 ("Mon, 11 May 2026
/// 14:30:00 +0000"), Atom uses ISO8601. Try both; whichever parses wins.
enum FeedDate {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static let rfc822NoSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm Z"
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = iso.date(from: trimmed) { return d }
        if let d = isoFractional.date(from: trimmed) { return d }
        if let d = rfc822.date(from: trimmed) { return d }
        if let d = rfc822NoSeconds.date(from: trimmed) { return d }
        return nil
    }
}
