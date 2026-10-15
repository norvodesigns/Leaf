import Foundation

/// Live search against Open Library (free, no key). Used alongside the bundled catalog when online.
enum OpenLibrary {
    private struct SearchResponse: Decodable {
        let docs: [Doc]
    }

    private struct Doc: Decodable {
        let key: String
        let title: String?
        let author_name: [String]?
        let first_publish_year: Int?
        let number_of_pages_median: Int?
        let cover_i: Int?
        let subject: [String]?
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.httpAdditionalHeaders = ["User-Agent": "Leaf/1.0 (iOS reading planner)"]
        return URLSession(configuration: configuration)
    }()

    /// Searches works and returns only results with a page count, since the plan needs one.
    static func search(_ query: String, limit: Int = 24) async throws -> [Book] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,number_of_pages_median,cover_i,subject"),
        ]
        guard let url = components.url else { return [] }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.docs.compactMap { doc in
            guard let title = doc.title, let pages = doc.number_of_pages_median, pages >= 20, pages <= 3000 else { return nil }
            let id = doc.key.replacingOccurrences(of: "/works/", with: "")
            let genres = genreTags(from: doc.subject ?? [])
            return Book(
                id: id,
                title: title,
                author: doc.author_name?.first ?? "Unknown author",
                year: doc.first_publish_year,
                pages: pages,
                coverID: doc.cover_i,
                genres: genres
            )
        }
    }

    /// Maps Open Library's free-form subjects onto Leaf's small genre vocabulary.
    static func genreTags(from subjects: [String]) -> [String] {
        let rules: [(String, [String])] = [
            ("graphic", ["graphic novel", "comic"]),
            ("children", ["juvenile", "children"]),
            ("young-adult", ["young adult"]),
            ("fantasy", ["fantasy", "magic"]),
            ("science-fiction", ["science fiction"]),
            ("mystery", ["mystery", "detective"]),
            ("thriller", ["thriller", "suspense"]),
            ("romance", ["romance", "love stories"]),
            ("horror", ["horror"]),
            ("historical", ["historical fiction"]),
            ("poetry", ["poetry", "poems"]),
            ("biography", ["biography"]),
            ("memoir", ["memoir", "autobiography"]),
            ("history", ["history"]),
            ("science", ["science", "physics", "biology"]),
            ("philosophy", ["philosophy"]),
            ("psychology", ["psychology"]),
            ("self-help", ["self-help", "self-actualization"]),
            ("business", ["business", "economics"]),
            ("classics", ["classic"]),
        ]
        let lowered = subjects.prefix(40).map { $0.lowercased() }
        var tags: [String] = []
        for (tag, keywords) in rules where tags.count < 3 {
            if lowered.contains(where: { subject in keywords.contains { subject.contains($0) } }) { tags.append(tag) }
        }
        if tags.isEmpty, lowered.contains(where: { $0.contains("fiction") }) { tags.append("fiction") }
        return tags
    }
}
