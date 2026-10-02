import SwiftUI

/// Circular touch wheel with explicit intents and independently accessible hardware controls.
public struct ClickWheel: View {
    public var theme: iPodTheme
    public var accessibilityID: String
    public var browse: (Int) -> Void
    public var select: () -> Void
    public var menu: () -> Void
    public var playPause: () -> Void
    public var next: () -> Void
    public var previous: () -> Void

    @State private var lastAngle: CGFloat?
    @State private var pendingAngle: CGFloat = 0
    @State private var didDrag = false
    @State private var isTrackingGesture = false
    @State private var suppressionTask: Task<Void, Never>?

    private let radiansPerStep: CGFloat = 0.16

    public init(
        theme: iPodTheme = .classicBlack,
        accessibilityID: String = "wheel",
        browse: @escaping (Int) -> Void,
        select: @escaping () -> Void,
        menu: @escaping () -> Void,
        playPause: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void
    ) {
        self.theme = theme
        self.accessibilityID = accessibilityID
        self.browse = browse
        self.select = select
        self.menu = menu
        self.playPause = playPause
        self.next = next
        self.previous = previous
    }

    public var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let wheelDiameter = diameter * theme.wheelDiameterFraction
            let centerDiameter = wheelDiameter * theme.wheelCenterFraction

            ZStack {
                Circle().fill(theme.palette.wheel)
                    .overlay(Circle().stroke(theme.palette.wheelEdge, lineWidth: 1))
                    .frame(width: wheelDiameter, height: wheelDiameter)
                    .position(center)

                Button(action: guarded(menu)) {
                    Text(String(localized: "MENU"))
                        .font(.system(size: max(12, diameter * 0.052), weight: .semibold))
                        .foregroundStyle(theme.palette.controlText)
                        .lineLimit(1)
                        .frame(width: max(64, wheelDiameter * 0.36), height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: center.x, y: center.y - wheelDiameter * 0.34)
                .accessibilityLabel(String(localized: "Menu"))
                .accessibilityHint(String(localized: "Return to the previous menu"))
                .accessibilityIdentifier("\(accessibilityID).menu")

                Button(action: guarded(previous)) {
                    PreviousShape().fill(theme.palette.controlText).frame(width: 29, height: 15)
                        .frame(width: 52, height: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: center.x - wheelDiameter * 0.34, y: center.y)
                .accessibilityLabel(String(localized: "Previous"))
                .accessibilityIdentifier("\(accessibilityID).previous")

                Button(action: guarded(next)) {
                    NextShape().fill(theme.palette.controlText).frame(width: 29, height: 15)
                        .frame(width: 52, height: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: center.x + wheelDiameter * 0.34, y: center.y)
                .accessibilityLabel(String(localized: "Next"))
                .accessibilityIdentifier("\(accessibilityID).next")

                Button(action: guarded(playPause)) {
                    PlayPauseShape().fill(theme.palette.controlText).frame(width: 29, height: 18)
                        .frame(width: 52, height: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: center.x, y: center.y + wheelDiameter * 0.34)
                .accessibilityLabel(String(localized: "Play or Pause"))
                .accessibilityIdentifier("\(accessibilityID).playPause")

                Button(action: guarded(select)) {
                    Circle().fill(theme.palette.wheelEdge.opacity(0.72))
                        .frame(width: centerDiameter, height: centerDiameter)
                        .overlay(Circle().stroke(theme.palette.wheelEdge.opacity(0.7), lineWidth: 1))
                        .frame(width: max(centerDiameter, 44), height: max(centerDiameter, 44))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(center)
                .accessibilityLabel(String(localized: "Select"))
                .accessibilityHint(String(localized: "Open the selected item"))
                .accessibilityIdentifier("\(accessibilityID).select")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Attach to the whole wheel bounds so a circular gesture can start over any control.
            .contentShape(Rectangle())
            .simultaneousGesture(rotationGesture(center: center, deadZone: centerDiameter / 2))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Click wheel"))
        .accessibilityIdentifier(accessibilityID)
        .accessibilityAdjustableAction { direction in
            browse(direction == .increment ? 1 : -1)
        }
    }

    private func guarded(_ action: @escaping () -> Void) -> () -> Void {
        { if !didDrag { action() } }
    }

    private func rotationGesture(center: CGPoint, deadZone: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if !isTrackingGesture {
                    isTrackingGesture = true
                    suppressionTask?.cancel()
                    didDrag = true
                }
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                guard hypot(dx, dy) > deadZone else {
                    // Reset the angular baseline in the center; moving out does not jump.
                    lastAngle = nil
                    return
                }
                let angle = atan2(dy, dx)
                guard let previousAngle = lastAngle else {
                    lastAngle = angle
                    pendingAngle = 0
                    return
                }
                var delta = angle - previousAngle
                if delta > .pi { delta -= 2 * .pi }
                if delta < -.pi { delta += 2 * .pi }
                lastAngle = angle
                pendingAngle += delta
                let steps = Int(pendingAngle / radiansPerStep)
                guard steps != 0 else { return }
                pendingAngle -= CGFloat(steps) * radiansPerStep
                browse(steps)
            }
            .onEnded { _ in
                lastAngle = nil
                pendingAngle = 0
                isTrackingGesture = false
                guard didDrag else { return }
                // Keep the release from triggering an underlying Button tap.
                suppressionTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    didDrag = false
                }
            }
    }
}

private struct PreviousShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let barWidth = rect.width * 0.14
            let triangleWidth = (rect.width - barWidth) / 2
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: barWidth, height: rect.height))
            path.move(to: CGPoint(x: rect.minX + barWidth, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + barWidth + triangleWidth, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + barWidth + triangleWidth, y: rect.maxY))
            path.closeSubpath()
            path.move(to: CGPoint(x: rect.minX + barWidth + triangleWidth, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct NextShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let barWidth = rect.width * 0.14
            let triangleWidth = (rect.width - barWidth) / 2
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + triangleWidth, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            path.move(to: CGPoint(x: rect.minX + triangleWidth, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - barWidth, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + triangleWidth, y: rect.maxY))
            path.closeSubpath()
            path.addRect(CGRect(x: rect.maxX - barWidth, y: rect.minY, width: barWidth, height: rect.height))
        }
    }
}

private struct PlayPauseShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let playWidth = rect.width * 0.48
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + playWidth, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            let barWidth = rect.width * 0.12
            path.addRect(CGRect(x: rect.maxX - barWidth * 2.5, y: rect.minY, width: barWidth, height: rect.height))
            path.addRect(CGRect(x: rect.maxX - barWidth, y: rect.minY, width: barWidth, height: rect.height))
        }
    }
}
