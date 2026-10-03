import SwiftUI

/// Stable, typed destinations for the retro embedded menu hierarchy.
public enum PlayerDestination: Hashable, Sendable {
    case mainMenu
    case music
    case artists
    case artist(name: String)
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

    public init(root: PlayerDestination = .mainMenu, selectedItemID: String? = nil) {
        self.path = [root]
        self.selection = selectedItemID.map(PlayerMenuSelection.item(id:))
    }

    public var currentDestination: PlayerDestination { path.last ?? .mainMenu }

    public mutating func select(itemID: String) {
        selection = .item(id: itemID)
    }

    public mutating func select(action: PlayerMenuAction) {
        selection = .action(action)
    }

    public mutating func push(_ destination: PlayerDestination) {
        path.append(destination)
    }

    @discardableResult
    public mutating func pop() -> PlayerDestination? {
        guard path.count > 1 else { return nil }
        return path.removeLast()
    }

    public mutating func returnToRoot() {
        guard let root = path.first else { return }
        path = [root]
    }
}
