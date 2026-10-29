import SwiftUI

/// Stable, typed destinations for the retro embedded menu hierarchy.
public enum PlayerDestination: Hashable, Sendable {
    case mainMenu
    case music
    case playlists
    case playlist(id: UUID)
    case playlistSongPicker(id: UUID)
    case favorites
    case artists
    case artist(name: String)
    case artistAlbums(name: String)
    case artistSongs(name: String)
    case artistAlbum(artist: String, albumArtist: String, title: String)
    case albums
    case album(artist: String, title: String)
    case songs
    case queue
    case nowPlaying
    case settings
}

/// Menu selection is intentionally separate from the navigation path.
public enum PlayerMenuSelection: Hashable, Sendable {
    case item(id: String)
    case action(PlayerMenuAction)
}

public enum PlayerMenuAction: Hashable, Sendable {
    case open(PlayerDestination)
    case back
    case playPause
}

/// State primitive for a push/pop menu transition; the app model maps menu actions to behavior.
public struct PlayerNavigationState: Equatable, Sendable {
    public private(set) var path: [PlayerDestination]
    public private(set) var selection: PlayerMenuSelection?
    private var selectionsByDestination: [PlayerDestination: PlayerMenuSelection] = [:]

    public init(root: PlayerDestination = .mainMenu, selectedItemID: String? = nil) {
        self.path = [root]
        self.selection = selectedItemID.map(PlayerMenuSelection.item(id:))
        self.selectionsByDestination = selectedItemID.map { [root: .item(id: $0)] } ?? [:]
    }

    public var currentDestination: PlayerDestination { path.last ?? .mainMenu }

    public mutating func select(itemID: String) {
        setSelection(.item(id: itemID))
    }

    public mutating func clearSelection() {
        setSelection(nil)
    }

    public mutating func select(action: PlayerMenuAction) {
        setSelection(.action(action))
    }

    public mutating func push(_ destination: PlayerDestination) {
        rememberCurrentSelection()
        path.append(destination)
        selection = selectionsByDestination[destination]
    }

    @discardableResult
    public mutating func pop() -> PlayerDestination? {
        guard path.count > 1 else { return nil }
        rememberCurrentSelection()
        let popped = path.removeLast()
        selection = selectionsByDestination[currentDestination]
        return popped
    }

    public mutating func returnToRoot() {
        guard let root = path.first else { return }
        rememberCurrentSelection()
        path = [root]
        selection = selectionsByDestination[root]
    }

    private mutating func setSelection(_ selection: PlayerMenuSelection?) {
        self.selection = selection
        if let selection { selectionsByDestination[currentDestination] = selection }
        else { selectionsByDestination.removeValue(forKey: currentDestination) }
    }

    private mutating func rememberCurrentSelection() {
        if let selection { selectionsByDestination[currentDestination] = selection }
        else { selectionsByDestination.removeValue(forKey: currentDestination) }
    }
}
