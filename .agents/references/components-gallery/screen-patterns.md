# Screen Patterns

## Library browsing

Present the current menu category, selection, and available tracks/albums/artists. Keep sorting, filtering, and destination decisions outside row components. Empty state should explain how to import audio.

## Now Playing

Show the current track, artwork if available, elapsed/duration, and transport actions. Reflect the playback service’s state rather than guessing from which screen is visible.

## File import

Present the platform file importer, forward selected URLs to the application import flow, and show partial success/failure. The presentation layer must not persist raw external URLs.

## Reference fidelity

Match a named iPod generation only after the user supplies or approves the visual reference. Until then, keep component responsibilities and dimensions adaptable; do not state that a generic click-wheel mock is an exact recreation.
