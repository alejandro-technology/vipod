import Foundation

private struct AlbumKey: Hashable {
    let artist: String
    let title: String

    var stableID: String {
        "album.\(artist.utf8.count):\(artist)\(title.utf8.count):\(title)"
    }

    static func key(for track: Track) -> AlbumKey {
        let artist = track.albumArtist ?? (track.isCompilation ? String(localized: "Various Artists") : track.artist)
        return AlbumKey(artist: artist, title: track.album)
    }
}

struct ClassicPlayerMenuBuilder {
    func rows(
        for destination: PlayerDestination,
        tracks: [Track],
        filterText: String,
        hasConnectedAudioOutput: Bool
    ) -> [ClassicPlayerRow] {
        switch destination {
        case .mainMenu:
            return [
                row("menu.music", String(localized: "Music"), .open(.music)),
                row("menu.shuffle", String(localized: "Shuffle Songs"), .shuffle(tracks)),
                row("menu.queue", String(localized: "Queue"), .open(.queue)),
                row("menu.nowPlaying", String(localized: "Now Playing"), .open(.nowPlaying)),
                row("menu.settings", String(localized: "Settings"), .open(.settings)),
                row("menu.import", String(localized: "Import Music"), .importMusic)
            ]
        case .music:
            return [
                row("music.artists", String(localized: "Artists"), .open(.artists)),
                row("music.albums", String(localized: "Albums"), .open(.albums)),
                row("music.songs", String(localized: "Songs"), .open(.songs)),
                row("music.playlists", String(localized: "Playlists"), .open(.playlists)),
                row("music.favorites", String(localized: "Favorites"), .open(.favorites)),
                row("menu.import", String(localized: "Import Music"), .importMusic)
            ]
        case .artists:
            return filtered(Array(Set(tracks.map(\.artist))).sorted().map { name in
                row("artist.\(name)", name, .open(.artist(name: name)))
            }, by: filterText)
        case .artist(let name):
            let artistTracks = tracks.filter { $0.artist == name }
            let queue = filteredTracks(artistTracks, by: filterText)
            let albums = albumKeys(in: artistTracks).map { album in
                row(album.stableID, album.title, .open(.album(artist: album.artist, title: album.title)))
            }
            return filtered(albums + artistTracks.map { trackRow($0, queue: queue) }, by: filterText)
        case .albums:
            return filtered(albumKeys(in: tracks).map { album in
                row(album.stableID, album.title, .open(.album(artist: album.artist, title: album.title)), subtitle: album.artist)
            }, by: filterText)
        case .album(let artist, let album):
            let albumTracks = tracks.filter { AlbumKey.key(for: $0) == AlbumKey(artist: artist, title: album) }
                .sorted(by: trackOrder)
            let queue = filteredTracks(albumTracks, by: filterText)
            return filtered(albumTracks.map { trackRow($0, queue: queue) }, by: filterText)
        case .songs:
            let queue = filteredTracks(tracks, by: filterText)
            return filtered(tracks.map { trackRow($0, queue: queue) }, by: filterText)
        case .playlists, .playlist, .favorites:
            return []
        case .nowPlaying:
            return []
        case .queue:
            return []
        case .settings:
            var settingsRows: [ClassicPlayerRow] = [
                row("theme.black", String(localized: "Black iPod"), .setTheme(.black)),
                row("theme.white", String(localized: "White iPod"), .setTheme(.white)),
                row("settings.shuffle", String(localized: "Shuffle"), .toggleShuffle),
                row("repeat.off", String(localized: "Repeat Off"), .setRepeat(.off)),
                row("repeat.all", String(localized: "Repeat All"), .setRepeat(.all)),
                row("repeat.one", String(localized: "Repeat One"), .setRepeat(.one)),
                row("menu.import", String(localized: "Import Music"), .importMusic)
            ]
            if hasConnectedAudioOutput {
                settingsRows.insert(contentsOf: BluetoothDeviceKind.allCases.map { kind in
                    row("settings.bluetooth.\(kind.rawValue)", bluetoothKindName(kind), .setBluetoothKind(kind))
                }, at: settingsRows.count - 1)
            }
            return settingsRows
        }
    }

    private func row(
        _ id: String,
        _ title: String,
        _ action: ClassicPlayerRow.Action,
        subtitle: String? = nil
    ) -> ClassicPlayerRow {
        ClassicPlayerRow(id: id, title: title, subtitle: subtitle, action: action)
    }

    private func trackRow(_ track: Track, queue: [Track]) -> ClassicPlayerRow {
        ClassicPlayerRow(
            id: "track.\(track.id.uuidString)",
            title: track.title,
            subtitle: "\(track.artist) · \(track.album)",
            action: .play(track, queue: queue)
        )
    }

    private func filtered(_ rows: [ClassicPlayerRow], by filterText: String) -> [ClassicPlayerRow] {
        guard !filterText.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(filterText)
                || ($0.subtitle?.localizedCaseInsensitiveContains(filterText) ?? false)
        }
    }

    private func filteredTracks(_ tracks: [Track], by filterText: String) -> [Track] {
        guard !filterText.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(filterText)
                || $0.artist.localizedCaseInsensitiveContains(filterText)
                || $0.album.localizedCaseInsensitiveContains(filterText)
        }
    }

    private func albumKeys(in tracks: [Track]) -> [AlbumKey] {
        Array(Set(tracks.map { AlbumKey.key(for: $0) }))
            .sorted { lhs, rhs in
                lhs.artist == rhs.artist ? lhs.title < rhs.title : lhs.artist < rhs.artist
            }
    }

    private func trackOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        if lhs.discNumber != rhs.discNumber {
            switch (lhs.discNumber, rhs.discNumber) {
            case let (left?, right?): if left != right { return left < right }
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): break
            }
        }
        if lhs.trackNumber != rhs.trackNumber {
            switch (lhs.trackNumber, rhs.trackNumber) {
            case let (left?, right?): if left != right { return left < right }
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): break
            }
        }
        if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        if lhs.artist != rhs.artist { return lhs.artist.localizedStandardCompare(rhs.artist) == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func bluetoothKindName(_ kind: BluetoothDeviceKind) -> String {
        switch kind {
        case .automatic: String(localized: "Bluetooth: Automatic")
        case .airPods: String(localized: "Bluetooth: AirPods")
        case .headphones: String(localized: "Bluetooth: Headphones")
        case .speaker: String(localized: "Bluetooth: Speaker")
        }
    }
}
