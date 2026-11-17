import OpenGesturesCore
import SwiftUI

/// A small drawing of the surface and the fingers that make a gesture, so
/// the editor shows the movement instead of describing it.
struct GestureDiagram: View {
    let gesture: Gesture
    let device: DeviceKind
    /// The axis a bound slide moves along; both when unknown.
    var slideAxis: Axis?

    var body: some View {
        Canvas { context, size in
            let surface = surfaceRect(in: size)
            let shape = surfacePath(surface)
            context.fill(shape, with: .color(.primary.opacity(0.05)))
            context.stroke(shape, with: .color(.primary.opacity(0.18)), lineWidth: 1)

            var clipped = context
            clipped.clip(to: shape)
            for zone in zones() {
                clipped.fill(Path(map(zone, into: surface)), with: .color(.accentColor.opacity(0.3)))
            }

            let figure = figure()
            for arrow in figure.arrows {
                drawArrow(arrow, in: surface, context: context)
            }
            for (index, point) in figure.fingers.enumerated() {
                drawFinger(at: map(point, into: surface), role: figure.roles[index], context: context)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Surface

    private func surfaceRect(in size: CGSize) -> CGRect {
        let ratio: CGFloat = device == .trackpad ? 1.6 : 0.58
        var width = size.width - 2
        var height = width / ratio
        if height > size.height - 2 {
            height = size.height - 2
            width = height * ratio
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func surfacePath(_ rect: CGRect) -> Path {
        let radius = device == .trackpad ? rect.height * 0.12 : rect.width * 0.48
        return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }

    private func map(_ point: CGPoint, into rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func map(_ zone: CGRect, into rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + zone.minX * rect.width,
            y: rect.minY + zone.minY * rect.height,
            width: zone.width * rect.width,
            height: zone.height * rect.height
        )
    }

    // MARK: - Fingers and arrows

    private enum Role { case moving, held, pressed }

    private struct Arrow {
        var from: CGPoint
        var to: CGPoint
        var twoWay = false
    }

    private struct Figure {
        var fingers: [CGPoint] = []
        var roles: [Role] = []
        var arrows: [Arrow] = []

        mutating func add(_ x: CGFloat, _ y: CGFloat = 0.5, _ role: Role = .moving) {
            fingers.append(CGPoint(x: x, y: y))
            roles.append(role)
        }

        mutating func row(_ count: Int, y: CGFloat = 0.5, role: Role = .moving) {
            let spacing: CGFloat = 0.13
            let start = 0.5 - spacing * CGFloat(count - 1) / 2
            for index in 0..<count {
                add(start + spacing * CGFloat(index), y, role)
            }
        }
    }

    private func figure() -> Figure {
        var figure = Figure()
        let fingers = gesture.fingerCount ?? 1

        switch gesture {
        case .holdLeftTapRight: figure.add(0.4, 0.5, .held); figure.add(0.62)
        case .holdRightTapLeft: figure.add(0.6, 0.5, .held); figure.add(0.38)
        case .holdTwoTapLeft: figure.add(0.5, 0.5, .held); figure.add(0.63, 0.5, .held); figure.add(0.3)
        case .holdTwoTapRight: figure.add(0.37, 0.5, .held); figure.add(0.5, 0.5, .held); figure.add(0.7)
        case .holdTwoTapBetween: figure.add(0.32, 0.5, .held); figure.add(0.68, 0.5, .held); figure.add(0.5)
        case .holdThreeTapLeft:
            figure.add(0.45, 0.5, .held); figure.add(0.58, 0.5, .held); figure.add(0.71, 0.5, .held); figure.add(0.24)
        case .holdThreeTapRight:
            figure.add(0.29, 0.5, .held); figure.add(0.42, 0.5, .held); figure.add(0.55, 0.5, .held); figure.add(0.76)
        case .holdSlide:
            figure.add(0.36, 0.5, .held)
            figure.add(0.62)
            figure.arrows.append(Arrow(from: CGPoint(x: 0.62, y: 0.2), to: CGPoint(x: 0.62, y: 0.8), twoWay: true))
        case .indexToPinky, .pinkyToIndex:
            figure.row(4, y: 0.42)
            let forward = gesture == .indexToPinky
            figure.arrows.append(Arrow(
                from: CGPoint(x: forward ? 0.3 : 0.7, y: 0.72),
                to: CGPoint(x: forward ? 0.7 : 0.3, y: 0.72)
            ))
        default:
            switch gesture.category {
            case .tap, .doubleTap:
                figure.row(fingers)
            case .swipe:
                figure.row(fingers)
                let direction = SwipeShape(gesture)?.direction
                for arrow in swipeArrows(direction) { figure.arrows.append(arrow) }
            case .slide:
                figure.row(fingers)
                // Two-way arrows beside and below the row of fingers.
                let side = 0.5 + 0.13 * CGFloat(fingers) / 2 + 0.07
                if slideAxis != .horizontal {
                    figure.arrows.append(Arrow(from: CGPoint(x: side, y: 0.22), to: CGPoint(x: side, y: 0.78), twoWay: true))
                }
                if slideAxis != .vertical {
                    figure.arrows.append(Arrow(from: CGPoint(x: 0.3, y: 0.8), to: CGPoint(x: 0.7, y: 0.8), twoWay: true))
                }
            case .click:
                if gesture.fingerCount != nil {
                    figure.row(fingers, role: .pressed)
                } else {
                    figure.fingers = zones().prefix(1).map { CGPoint(x: $0.midX, y: $0.midY) }
                    figure.roles = figure.fingers.map { _ in .pressed }
                }
            case .hold, .brush:
                break
            }
        }
        return figure
    }

    private func swipeArrows(_ direction: Direction?) -> [Arrow] {
        let center = CGPoint(x: 0.5, y: 0.5)
        func arrow(_ dx: CGFloat, _ dy: CGFloat) -> Arrow {
            Arrow(from: CGPoint(x: center.x + dx * 0.2, y: center.y + dy * 0.28),
                  to: CGPoint(x: center.x + dx * 0.4, y: center.y + dy * 0.4))
        }
        switch direction {
        case .left: return [arrow(-1, 0)]
        case .right: return [arrow(1, 0)]
        case .up: return [arrow(0, -1)]
        case .down: return [arrow(0, 1)]
        case nil: return [arrow(-1, 0), arrow(1, 0), arrow(0, -1), arrow(0, 1)]
        }
    }

    /// Highlighted areas, in unit coordinates with y growing downwards.
    private func zones() -> [CGRect] {
        // Drawn deeper than the real 15% so the zone reads at this size, and
        // as deep on both axes of the wider-than-tall surface.
        let edge: CGFloat = 0.28
        let band = edge * 0.625
        switch gesture {
        case .edgeClick:
            return [CGRect(x: 0, y: 0, width: 1, height: edge), CGRect(x: 0, y: 1 - edge, width: 1, height: edge),
                    CGRect(x: 0, y: 0, width: band, height: 1), CGRect(x: 1 - band, y: 0, width: band, height: 1)]
        case .cornerClick:
            return [false, true].flatMap { right in [false, true].map { bottom in
                CGRect(x: right ? 1 - band : 0, y: bottom ? 1 - edge : 0, width: band, height: edge)
            } }
        default:
            break
        }
        guard let zone = ClickZone(gesture) else { return [] }
        if let corner = zone.corner {
            return [CGRect(x: corner.right ? 1 - band : 0, y: corner.top ? 0 : 1 - edge, width: band, height: edge)]
        }
        guard let side = zone.edge else { return [] }
        // The span along the edge, from 0 to 1.
        let span: (CGFloat, CGFloat) = switch zone.part {
        case nil: (0, 1)
        case .half(.top), .half(.left): (0, 0.5)
        case .half(.bottom), .half(.right): (0.5, 1)
        case .third(.top), .third(.left): (0, 1 / 3)
        case .third(.middle): (1 / 3, 2 / 3)
        case .third(.bottom), .third(.right): (2 / 3, 1)
        }
        switch side {
        case .left: return [CGRect(x: 0, y: span.0, width: band, height: span.1 - span.0)]
        case .right: return [CGRect(x: 1 - band, y: span.0, width: band, height: span.1 - span.0)]
        case .top: return [CGRect(x: span.0, y: 0, width: span.1 - span.0, height: edge)]
        case .bottom: return [CGRect(x: span.0, y: 1 - edge, width: span.1 - span.0, height: edge)]
        }
    }

    // MARK: - Drawing

    private func drawFinger(at point: CGPoint, role: Role, context: GraphicsContext) {
        let radius: CGFloat = 5.5
        let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        switch role {
        case .moving:
            context.fill(dot, with: .color(.accentColor))
            if gesture.category == .doubleTap {
                let ring = radius + 3.5
                let outer = Path(ellipseIn: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2))
                context.stroke(outer, with: .color(.accentColor.opacity(0.6)), lineWidth: 1.2)
            }
        case .held:
            context.fill(dot, with: .color(.primary.opacity(0.35)))
        case .pressed:
            context.fill(dot, with: .color(.accentColor))
            let ring = radius + 3
            let outer = Path(ellipseIn: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2))
            context.stroke(outer, with: .color(.accentColor.opacity(0.35)), lineWidth: 3)
        }
    }

    private func drawArrow(_ arrow: Arrow, in surface: CGRect, context: GraphicsContext) {
        let from = map(arrow.from, into: surface)
        let to = map(arrow.to, into: surface)
        let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        let color = GraphicsContext.Shading.color(.secondary)

        var line = Path()
        line.move(to: from)
        line.addLine(to: to)
        context.stroke(line, with: color, style: style)
        context.stroke(head(at: to, from: from), with: color, style: style)
        if arrow.twoWay {
            context.stroke(head(at: from, from: to), with: color, style: style)
        }
    }

    private func head(at tip: CGPoint, from tail: CGPoint) -> Path {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length: CGFloat = 5
        var path = Path()
        path.move(to: CGPoint(x: tip.x - length * cos(angle - .pi / 5), y: tip.y - length * sin(angle - .pi / 5)))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle + .pi / 5), y: tip.y - length * sin(angle + .pi / 5)))
        return path
    }
}
