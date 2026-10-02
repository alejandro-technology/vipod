import AVFoundation
import CryptoKit
import Foundation

nonisolated public actor FileTrackRepository: TrackRepository {
    public static let storageDirectoryName = "VIPOD"
    nonisolated private static let catalogFilename = "tracks.json"
    nonisolated private static let audioDirectoryName = "Audio"
    nonisolated private static let artworkDirectoryName = "Artwork"
    nonisolated private static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif"]

    public nonisolated let storageURL: URL
    private let fileManager: FileManager
    private var cachedTracks: [Track]?
    private var hasMutatingOperation = false

    public init(storageURL: URL? = nil, fileManager: FileManager = .default) throws {
        let root: URL
        if let storageURL {
            root = storageURL
        } else {
            guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw RepositoryError.storageUnavailable
            }
            root = support.appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
        }
        self.storageURL = root.standardizedFileURL
        self.fileManager = fileManager
        do {
            try fileManager.createDirectory(at: root.appendingPathComponent(Self.audioDirectoryName, isDirectory: true), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: root.appendingPathComponent(Self.artworkDirectoryName, isDirectory: true), withIntermediateDirectories: true)
        } catch {
            throw RepositoryError.storageFailure(underlying: error.localizedDescription)
        }
    }

    public func tracks() async throws -> [Track] {
        if let cachedTracks { return cachedTracks }
        let catalog = catalogURL
        guard fileManager.fileExists(atPath: catalog.path) else {
            cachedTracks = []
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([Track].self, from: Data(contentsOf: catalog))
            guard decoded.allSatisfy({ Self.isSafeRelativeFilename($0.audioFilename) && ($0.artworkFilename.map(Self.isSafeRelativeFilename) ?? true) }) else {
                throw RepositoryError.invalidCatalog
            }
            cachedTracks = decoded
            return decoded
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.catalogFailure(underlying: error.localizedDescription)
        }
    }

    public func importTracks(from urls: [URL]) async throws -> TrackImportReport {
        guard !hasMutatingOperation else { throw RepositoryError.operationInProgress }
        hasMutatingOperation = true
        defer { hasMutatingOperation = false }
        var current = try await tracks()
        var imported: [Track] = []
        var failures: [TrackImportFailure] = []
        var hashes = Set<String>()
        for track in current {
            let url = try Self.safeURL(filename: track.audioFilename, in: audioDirectoryURL)
            if let data = try? Data(contentsOf: url) { hashes.insert(Self.digest(data)) }
        }

        for source in urls {
            if Task.isCancelled { return await TrackImportReport(imported: imported, failures: failures, wasCancelled: true) }
            let filename = source.lastPathComponent
            var scoped = false
            #if os(iOS) || os(visionOS) || os(macOS)
            scoped = source.startAccessingSecurityScopedResource()
            #endif
            defer {
                #if os(iOS) || os(visionOS) || os(macOS)
                if scoped { source.stopAccessingSecurityScopedResource() }
                #endif
            }

            do {
                guard Self.supportedExtensions.contains(source.pathExtension.lowercased()) else {
                    throw RepositoryError.unsupportedFormat
                }
                let stagedAudio = storageURL.appendingPathComponent(".import-\(UUID().uuidString).\(source.pathExtension.lowercased())")
                do {
                    try Self.copyCoordinated(source, to: stagedAudio, fileManager: fileManager)
                    let data = try Data(contentsOf: stagedAudio, options: .mappedIfSafe)
                    let hash = Self.digest(data)
                    guard !hashes.contains(hash) else {
                        try? fileManager.removeItem(at: stagedAudio)
                        throw RepositoryError.duplicateImport
                    }
                    let metadata = try await Self.readMetadata(from: stagedAudio, filename: filename)
                    try await Self.validateAudio(at: stagedAudio)
                    if Task.isCancelled {
                        try? fileManager.removeItem(at: stagedAudio)
                        return await TrackImportReport(imported: imported, failures: failures, wasCancelled: true)
                    }

                    let id = UUID()
                    let ext = source.pathExtension.lowercased()
                    let audioFilename = "\(id.uuidString).\(ext)"
                    let artworkFilename = metadata.artwork.map { _ in "\(id.uuidString).jpg" }
                    let track = await Track(id: id, title: metadata.title, artist: metadata.artist, album: metadata.album, duration: metadata.duration, audioFilename: audioFilename, artworkFilename: artworkFilename)
                    let audioDestination = audioDirectoryURL.appendingPathComponent(audioFilename)
                    let artworkDestination = artworkFilename.map { artworkDirectoryURL.appendingPathComponent($0) }
                    var installedAudio = false
                    var installedArtwork = false
                    do {
                        try fileManager.moveItem(at: stagedAudio, to: audioDestination)
                        installedAudio = true
                        if let artwork = metadata.artwork, let artworkDestination {
                            try artwork.write(to: artworkDestination, options: .atomic)
                            installedArtwork = true
                        }
                        var next = current
                        next.append(track)
                        try writeCatalog(next)
                        current = next
                        cachedTracks = next
                        hashes.insert(hash)
                        imported.append(track)
                    } catch {
                        if installedAudio { try? fileManager.removeItem(at: audioDestination) }
                        if installedArtwork, let artworkDestination { try? fileManager.removeItem(at: artworkDestination) }
                        throw error
                    }
                } catch {
                    try? fileManager.removeItem(at: stagedAudio)
                    throw error
                }
            } catch is CancellationError {
                return await TrackImportReport(imported: imported, failures: failures, wasCancelled: true)
            } catch {
                failures.append(await TrackImportFailure(filename: filename, message: Self.userMessage(for: error)))
            }
        }
        cachedTracks = current
        return await TrackImportReport(imported: imported, failures: failures, wasCancelled: Task.isCancelled)
    }

    public func removeTrack(id: UUID) async throws {
        guard !hasMutatingOperation else { throw RepositoryError.operationInProgress }
        hasMutatingOperation = true
        defer { hasMutatingOperation = false }
        let current = try await tracks()
        guard let track = current.first(where: { $0.id == id }) else { return }
        let updated = current.filter { $0.id != id }
        try writeCatalog(updated)
        cachedTracks = updated
        if let audio = try? Self.safeURL(filename: track.audioFilename, in: audioDirectoryURL) { try? fileManager.removeItem(at: audio) }
        if let name = track.artworkFilename, let artwork = try? Self.safeURL(filename: name, in: artworkDirectoryURL) { try? fileManager.removeItem(at: artwork) }
    }

    public func mediaURL(for track: Track) throws -> URL {
        try Self.safeURL(filename: track.audioFilename, in: audioDirectoryURL)
    }

    public func artworkURL(for track: Track) throws -> URL? {
        guard let filename = track.artworkFilename else { return nil }
        return try Self.safeURL(filename: filename, in: artworkDirectoryURL)
    }

    public func artworkData(for track: Track) async throws -> Data? {
        guard let url = try artworkURL(for: track) else { return nil }
        do { return try Data(contentsOf: url, options: .mappedIfSafe) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    public nonisolated static func resolveMediaURL(for track: Track, in storageURL: URL) throws -> URL {
        let directory = storageURL.standardizedFileURL.appendingPathComponent(audioDirectoryName, isDirectory: true)
        return try safeURL(filename: track.audioFilename, in: directory)
    }

    public nonisolated static func resolveArtworkURL(for track: Track, in storageURL: URL) throws -> URL? {
        guard let filename = track.artworkFilename else { return nil }
        let directory = storageURL.standardizedFileURL.appendingPathComponent(artworkDirectoryName, isDirectory: true)
        return try safeURL(filename: filename, in: directory)
    }

    private var catalogURL: URL { storageURL.appendingPathComponent(Self.catalogFilename) }
    private var audioDirectoryURL: URL { storageURL.appendingPathComponent(Self.audioDirectoryName, isDirectory: true) }
    private var artworkDirectoryURL: URL { storageURL.appendingPathComponent(Self.artworkDirectoryName, isDirectory: true) }

    private func writeCatalog(_ tracks: [Track]) throws {
        do {
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: catalogURL, options: .atomic)
        } catch {
            throw RepositoryError.catalogFailure(underlying: error.localizedDescription)
        }
    }

    nonisolated private static func readMetadata(from url: URL, filename: String) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        let playable: Bool
        do { playable = try await asset.load(.isPlayable) }
        catch is CancellationError { throw CancellationError() }
        catch { throw RepositoryError.invalidAudio }
        guard playable else { throw RepositoryError.invalidAudio }
        let loadedDuration: CMTime?
        do { loadedDuration = try await asset.load(.duration) }
        catch is CancellationError { throw CancellationError() }
        catch { loadedDuration = nil }
        let seconds = loadedDuration?.seconds
        let duration = seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let metadata = try await asset.load(.commonMetadata)
        func value(_ identifier: String) async throws -> String? {
            guard let item = metadata.first(where: { $0.commonKey?.rawValue == identifier }) else { return nil }
            return try await item.load(.stringValue)
        }
        let title = try await value("title") ?? URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let artist = try await value("artist")
        let album = try await value("albumName")
        var artwork: Data?
        if let item = metadata.first(where: { $0.commonKey?.rawValue == "artwork" }) {
            artwork = try await item.load(.dataValue)
        }
        return AudioMetadata(title: title, artist: artist, album: album, duration: duration, artwork: artwork)
    }

    @MainActor
    private static func validateAudio(at url: URL) throws {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.duration.isFinite, player.duration >= 0, player.prepareToPlay() else {
                throw RepositoryError.invalidAudio
            }
            player.stop()
        } catch {
            throw RepositoryError.invalidAudio
        }
    }

    nonisolated private static func copyCoordinated(_ source: URL, to destination: URL, fileManager: FileManager) throws {
        #if os(iOS) || os(visionOS) || os(macOS)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readableURL in
            do { try fileManager.copyItem(at: readableURL, to: destination) }
            catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
        #else
        try fileManager.copyItem(at: source, to: destination)
        #endif
    }

    nonisolated private static func safeURL(filename: String, in directory: URL) throws -> URL {
        guard isSafeRelativeFilename(filename) else { throw RepositoryError.invalidCatalog }
        let root = directory.standardizedFileURL
        let url = root.appendingPathComponent(filename).standardizedFileURL
        guard url.deletingLastPathComponent() == root else { throw RepositoryError.invalidCatalog }
        return url
    }

    nonisolated private static func isSafeRelativeFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename != "." && filename != ".." && !filename.contains("/") && !filename.contains("\\") && URL(fileURLWithPath: filename).lastPathComponent == filename
    }

    nonisolated private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    nonisolated private static func userMessage(for error: Error) -> String {
        guard let error = error as? RepositoryError else { return "The file could not be imported. Check that it is available and try again." }
        switch error {
        case .unsupportedFormat: return "This audio format is not supported. Choose an MP3, M4A, WAV, or AIFF file."
        case .duplicateImport: return "This audio file is already in your library."
        case .invalidAudio: return "This file could not be decoded as playable audio."
        case .storageUnavailable, .storageFailure, .catalogFailure: return "The library could not be saved. Free up storage and try again."
        case .invalidCatalog: return "The library catalog contains an invalid file reference."
        case .operationInProgress: return "Another library update is already in progress. Try again shortly."
        }
    }
}

private struct AudioMetadata {
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let artwork: Data?
}

public enum RepositoryError: Error, Sendable {
    case storageUnavailable
    case storageFailure(underlying: String)
    case catalogFailure(underlying: String)
    case invalidCatalog
    case operationInProgress
    case unsupportedFormat
    case duplicateImport
    case invalidAudio
}
