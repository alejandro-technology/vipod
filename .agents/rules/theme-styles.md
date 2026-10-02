---
trigger: model_decision
---

# Theme & Styles Rules

Build the visual system from an approved reference for the chosen iPod model. Keep colors, typography, geometry, spacing, textures, and animation decisions centralized so visual tuning is consistent.

## Core mandates

1. Capture reference dimensions and appearance as named design tokens; do not scatter guessed measurements or hex colors across screens.
2. Keep feature-specific visual layout local. Promote a primitive to the shared DesignSystem only when multiple features use it.
3. Recreate the wheel, screen frame, menu highlight, and typography with the simplest SwiftUI shapes and drawing APIs that meet the reference.
4. Use licensed/local assets only when the reference requires artwork or a typeface; record their source and avoid bundling assets copied from unapproved sources.
5. Make motion intentional and respect Reduce Motion. Preserve accessibility while matching the physical-device feel.
6. Confirm whether the target is a specific Classic/click-wheel generation before fixing screen aspect ratio, labels, colors, or controls.

## Do not

- Claim “exactly the same” without a named model and visual acceptance reference.
- Use system symbols, generic gradients, or current iOS chrome where they conflict with the approved reference.
- Encode styling decisions in playback/domain logic.
- Hardcode repeated values in multiple views when a design token is appropriate.

## See also

- [`components.md`](components.md)
- [`../references/components-gallery/click-wheel.md`](../references/components-gallery/click-wheel.md)
