import CoreGraphics

public enum Direction: Sendable {
    case left, right, up, down

    public init?(_ token: String) {
        switch token.trimmingCharacters(in: .whitespaces).lowercased() {
        case "l", "left": self = .left
        case "r", "right": self = .right
        case "u", "t", "up", "top": self = .up
        case "d", "b", "down", "bottom": self = .down
        default: return nil
        }
    }
}

public enum Geometry {
    /// Finds the closest rectangle in `direction` from `source`.
    /// Coordinates use the Accessibility convention (y grows downward).
    public static func neighbor<ID>(of source: CGRect, in candidates: [(ID, CGRect)], direction: Direction) -> ID? {
        let tolerance: CGFloat = 8
        var best: (id: ID, score: CGFloat)?

        // Pass 1: rectangles that lie beyond the source's edge (tiled layouts).
        for (id, r) in candidates {
            let gap: CGFloat, overlap: CGFloat, perpendicular: CGFloat
            switch direction {
            case .left:
                guard r.maxX <= source.minX + tolerance, r.midX < source.midX else { continue }
                gap = source.minX - r.maxX
                overlap = min(r.maxY, source.maxY) - max(r.minY, source.minY)
                perpendicular = abs(r.midY - source.midY)
            case .right:
                guard r.minX >= source.maxX - tolerance, r.midX > source.midX else { continue }
                gap = r.minX - source.maxX
                overlap = min(r.maxY, source.maxY) - max(r.minY, source.minY)
                perpendicular = abs(r.midY - source.midY)
            case .up:
                guard r.maxY <= source.minY + tolerance, r.midY < source.midY else { continue }
                gap = source.minY - r.maxY
                overlap = min(r.maxX, source.maxX) - max(r.minX, source.minX)
                perpendicular = abs(r.midX - source.midX)
            case .down:
                guard r.minY >= source.maxY - tolerance, r.midY > source.midY else { continue }
                gap = r.minY - source.maxY
                overlap = min(r.maxX, source.maxX) - max(r.minX, source.minX)
                perpendicular = abs(r.midX - source.midX)
            }
            let score = (overlap > 0 ? 0 : 100_000) + max(gap, 0) + perpendicular * 0.01
            if best == nil || score < best!.score { best = (id, score) }
        }
        if let best { return best.id }

        // Pass 2: centre-based fallback (overlapping floating windows).
        for (id, r) in candidates {
            let dx = r.midX - source.midX, dy = r.midY - source.midY
            let primary: CGFloat, secondary: CGFloat
            switch direction {
            case .left: primary = -dx; secondary = abs(dy)
            case .right: primary = dx; secondary = abs(dy)
            case .up: primary = -dy; secondary = abs(dx)
            case .down: primary = dy; secondary = abs(dx)
            }
            guard primary > 1 else { continue }
            let score = primary + secondary * 2
            if best == nil || score < best!.score { best = (id, score) }
        }
        return best?.id
    }

    /// Fraction (0...1) of `rect` covered by the union-ish of `areas` (sum of intersections, clamped).
    public static func visibleFraction(of rect: CGRect, in areas: [CGRect]) -> CGFloat {
        let total = rect.width * rect.height
        guard total > 0 else { return 0 }
        var covered: CGFloat = 0
        for a in areas {
            let i = rect.intersection(a)
            if !i.isNull { covered += i.width * i.height }
        }
        return min(1, covered / total)
    }

    public static func centered(_ size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(x: (rect.midX - size.width / 2).rounded(), y: (rect.midY - size.height / 2).rounded(),
               width: size.width, height: size.height)
    }
}
