# Layout Component Patterns

Keep layout elements focused on the shape of the selected iPod reference.

- **Device frame:** owns screen bezel, proportions, and safe-area composition from approved measurements.
- **Menu viewport:** presents a bounded list and selected-row treatment; it does not decide which menu destination comes next.
- **Now Playing layout:** arranges artwork, metadata, progress, and transport controls from playback presentation state.
- **Wheel surface:** draws the wheel and reports interaction intent; it does not own queue or volume policy.
- **Import feedback:** reports progress, successes, and failures without retaining document-picker URLs.

Do not add a generic dashboard/layout system for these few screens. Extract a shared layout only when it reduces real duplication and retains clear inputs.
