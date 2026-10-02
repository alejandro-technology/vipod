# Click-Wheel Interaction Pattern

Treat the on-screen wheel as a touch interaction surface inspired by iPod controls. Confirm the target model before finalizing which regions/actions exist.

| Intent | Suggested interaction | Accessible equivalent |
|---|---|---|
| Browse menu | Circular drag/rotation changes selected row | Focusable menu rows and explicit previous/next selection actions |
| Open selection | Center region tap | Button with a localized Select label |
| Return to parent | Menu region tap | Back button/navigation action |
| Transport control | Previous/play/next regions when present in reference | Separately labeled buttons |
| Adjust volume | Wheel rotation only if the chosen model/flow assigns it | Standard adjustable accessibility control |

Keep gesture recognition deterministic, clamp or wrap selection according to the approved behavior, and avoid conflicting nested tap/drag recognizers. Do not rely on gesture-only operation; support VoiceOver, Dynamic Type where compatible with the reference, and Reduce Motion.
