import Foundation

nonisolated public actor FileLibraryCollectionStore: LibraryCollectionStore {
    private let fileURL: URL

    public init(storageURL: URL) {
        fileURL = storageURL.appendingPathComponent("library-collections.json")
    }

    public func load() async throws -> LibraryCollectionCatalog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LibraryCollectionCatalog() }
        do { return try JSONDecoder().decode(LibraryCollectionCatalog.self, from: Data(contentsOf: fileURL)) }
        catch { throw LibraryCollectionStoreError.loadFailed }
    }

    public func save(_ catalog: LibraryCollectionCatalog) async throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(catalog).write(to: fileURL, options: .atomic)
        } catch { throw LibraryCollectionStoreError.saveFailed }
    }
}

public enum LibraryCollectionStoreError: Error, Sendable {
    case loadFailed
    case saveFailed
}
