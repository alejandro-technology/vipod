---
name: theme
description: "Trigger: iPod visual theme, wheel styling, SwiftUI design tokens. Implement visual values from an approved hardware reference."
license: "UNLICENSED"
metadata:
  author: "VIPOD contributors"
  version: "1.0"
---

## Activation Contract

Use when creating or tuning the device frame, wheel, menu highlight, typography, artwork, spacing, or motion.

## Hard Rules

- Confirm which iPod generation and reference images define the target before pixel-level styling.
- Centralize repeated visual measurements and colors in the project DesignSystem.
- Keep styling out of Domain/Application behavior.
- Respect accessibility and Reduce Motion even when a retro visual is requested.

## Decision Gates

| Need | Action |
|---|---|
| One-off composition | Keep values local to that feature view |
| Repeated visual primitive | Add a named token or shared DesignSystem component |
| Artwork/font asset | Confirm provenance, license, and project resource setup |

## Execution Steps

1. Read `rules/theme-styles.md` and inspect existing assets/tokens.
2. Record the approved reference measurements and unresolved differences.
3. Implement reusable tokens and narrow SwiftUI shapes.
4. Compare the result against the reference and check accessibility settings.

## Output Contract

Report reference used, tokens/assets added, affected screens, and verification.

## References

- [`../../rules/theme-styles.md`](../../rules/theme-styles.md)
- [`../../references/components-gallery/click-wheel.md`](../../references/components-gallery/click-wheel.md)
