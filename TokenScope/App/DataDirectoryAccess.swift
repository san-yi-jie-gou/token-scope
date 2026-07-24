import Foundation

enum DataDirectoryAccessError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return L10n.string("dataAccess.error.accessDenied")
        }
    }
}

final class DataDirectoryAccess {
    private static let bookmarkKey = "usageDataDirectoryBookmark"

    private let defaults: UserDefaults
    private var accessedURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        accessedURL?.stopAccessingSecurityScopedResource()
    }

    func restore() -> URL? {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return nil }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL

            guard beginAccessing(url) else {
                defaults.removeObject(forKey: Self.bookmarkKey)
                return nil
            }

            if isStale {
                try persistBookmark(for: url)
            }
            return url
        } catch {
            defaults.removeObject(forKey: Self.bookmarkKey)
            return nil
        }
    }

    func authorize(_ selectedURL: URL) throws -> URL {
        let url = selectedURL.standardizedFileURL
        try persistBookmark(for: url)

        guard beginAccessing(url) else {
            defaults.removeObject(forKey: Self.bookmarkKey)
            throw DataDirectoryAccessError.accessDenied
        }
        return url
    }

    private func persistBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: Self.bookmarkKey)
    }

    private func beginAccessing(_ url: URL) -> Bool {
        accessedURL?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            accessedURL = nil
            return false
        }
        accessedURL = url
        return true
    }
}
