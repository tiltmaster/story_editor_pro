import CoreGraphics
import Foundation

/// Ratios come from real detector landmarks; nil means missing or invalid
/// geometry and must never be interpreted as a closed eye or open mouth.
struct FaceExpressionMetrics: Equatable {
    let mouthOpenRatio: CGFloat?
    let leftEyeOpenRatio: CGFloat?
    let rightEyeOpenRatio: CGFloat?

    init(mouthOpenRatio: CGFloat? = nil, leftEyeOpenRatio: CGFloat? = nil, rightEyeOpenRatio: CGFloat? = nil) {
        self.mouthOpenRatio = mouthOpenRatio
        self.leftEyeOpenRatio = leftEyeOpenRatio
        self.rightEyeOpenRatio = rightEyeOpenRatio
    }

    var mouthIsOpen: Bool { mouthOpenRatio.map { $0.isFinite && $0 >= 0.22 } ?? false }
    var isWink: Bool {
        guard let left = leftEyeOpenRatio, let right = rightEyeOpenRatio,
              left.isFinite, right.isFinite, left >= 0, right >= 0 else { return false }
        return (left <= 0.13 && right >= 0.20) || (right <= 0.13 && left >= 0.20)
    }
}

enum FaceExpressionGeometry {
    /// MediaPipe lid/mouth distances must use pixels, not normalized XY, which
    /// distorts the ratio in portrait frames. Rotation leaves these unchanged.
    static func ratio(widthFrom first: CGPoint, widthTo second: CGPoint,
                      heightPairs: [(CGPoint, CGPoint)], imageSize: CGSize) -> CGFloat? {
        guard imageSize.width > 0, imageSize.height > 0, !heightPairs.isEmpty else { return nil }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot((b.x - a.x) * imageSize.width, (b.y - a.y) * imageSize.height)
        }
        let width = distance(first, second)
        let height = heightPairs.reduce(CGFloat.zero) { $0 + distance($1.0, $1.1) } / CGFloat(heightPairs.count)
        guard width.isFinite, height.isFinite, width > 2 else { return nil }
        return min(2, max(0, height / width))
    }

    /// Vision supplies contour regions rather than fixed MediaPipe indices.
    /// Project real region points onto the face's pixel-space eye axis so head
    /// roll and portrait aspect cannot masquerade as an expression.
    static func contourRatio(heightPoints: [CGPoint], widthPoints: [CGPoint],
                             firstEye: CGPoint, secondEye: CGPoint, imageSize: CGSize) -> CGFloat? {
        guard heightPoints.count >= 3, widthPoints.count >= 2,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let dx = (secondEye.x - firstEye.x) * imageSize.width
        let dy = (secondEye.y - firstEye.y) * imageSize.height
        let length = hypot(dx, dy)
        guard length.isFinite, length > 2 else { return nil }
        let axis = CGPoint(x: dx / length, y: dy / length)
        func span(_ points: [CGPoint], along direction: CGPoint) -> CGFloat? {
            let projected = points.map { $0.x * imageSize.width * direction.x + $0.y * imageSize.height * direction.y }
            guard projected.allSatisfy({ $0.isFinite }), let minimum = projected.min(), let maximum = projected.max() else { return nil }
            return maximum - minimum
        }
        guard let width = span(widthPoints, along: axis), width > 2,
              let height = span(heightPoints, along: CGPoint(x: -axis.y, y: axis.x)) else { return nil }
        return min(2, max(0, height / width))
    }
}

struct FaceExpressionReaction: Equatable {
    let hearts: CGFloat
    let butterflies: CGFloat
    static let none = FaceExpressionReaction(hearts: 0, butterflies: 0)
}

/// Rising-edge, hysteresis, and refractory rules match the Android engine.
/// Time only animates a burst that real facial geometry has already triggered.
struct FaceExpressionReactions {
    private var mouthArmed = true
    private var winkArmed = true
    private var heartStarted: Double = -.infinity
    private var butterflyStarted: Double = -.infinity
    private var lastSample: Double = -.infinity

    mutating func reset() { self = FaceExpressionReactions() }

    mutating func sample(_ metrics: FaceExpressionMetrics?, at time: Double) -> FaceExpressionReaction {
        guard let metrics = metrics, time.isFinite else { reset(); return .none }
        if time < lastSample || time - lastSample > 0.35 { reset() }
        lastSample = time
        if let mouth = metrics.mouthOpenRatio, mouth.isFinite, mouth <= 0.14 { mouthArmed = true }
        if metrics.mouthIsOpen {
            if mouthArmed && time - heartStarted >= 0.65 { heartStarted = time }
            mouthArmed = false
        }
        if let left = metrics.leftEyeOpenRatio, let right = metrics.rightEyeOpenRatio,
           left.isFinite, right.isFinite, left >= 0.20, right >= 0.20 { winkArmed = true }
        if metrics.isWink {
            if winkArmed && time - butterflyStarted >= 0.65 { butterflyStarted = time }
            winkArmed = false
        }
        func envelope(started: Double, duration: Double) -> CGFloat {
            let age = time - started
            guard age >= 0, age < duration else { return 0 }
            return CGFloat(sin(.pi * age / duration))
        }
        return FaceExpressionReaction(hearts: envelope(started: heartStarted, duration: 0.75),
                                      butterflies: envelope(started: butterflyStarted, duration: 0.65))
    }

    /// A single photo cannot advance a live burst's clock. Show peak artwork
    /// only when its own freshly detected geometry contains the expression.
    static func still(_ metrics: FaceExpressionMetrics) -> FaceExpressionReaction {
        FaceExpressionReaction(hearts: metrics.mouthIsOpen ? 1 : 0, butterflies: metrics.isWink ? 1 : 0)
    }
}
