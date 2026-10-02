# Core Component Patterns

Use these as component responsibilities, not as a mandate to build every item before a screen needs it.

| Component | Responsibility | Must not own |
|---|---|---|
| `MenuRow` | Title, optional subtitle/artwork, selection/highlight state | Navigation rules or library queries |
| `TrackRow` | Track metadata and selected/playing indication | File access or player creation |
| `ArtworkFrame` | Artwork crop, frame, and placeholder treatment | Metadata lookup |
| `TransportControls` | Play/pause, previous, next, and seek actions | Queue mutation policy |
| `PlaybackProgress` | Display elapsed/duration and forward seek intent | Timer or player lifecycle |

Keep action labels accessible even when the retro visual hides textual labels. Use localized display values and pass all state/action dependencies explicitly.
