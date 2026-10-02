---
description: Inspect the repository and prepare a safe setup plan for the native iOS project.
agent: build
---

Inspect the current repository and report its readiness for the VIPOD iOS app. This command is read-only unless the user explicitly requests project creation or setup changes.

Check for an Xcode project/workspace, app and test targets, Swift/Xcode/deployment versions, package declarations, asset/resource setup, and relevant signing/capability configuration. Do not invent credentials, bundle identifiers, deployment targets, or entitlements. Do not create source files as part of a status-only request.

If project files are absent, report that the repository currently contains only `.agents` guidance and ask one focused question before creating an Xcode project.

Return **Found**, **Missing**, **Decisions needed**, and **Next action**.
