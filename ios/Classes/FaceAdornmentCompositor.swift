import CoreImage
import UIKit

/// Small, cached vector sprites transformed on the GPU using the live face pose.
/// No full-resolution UIKit allocation occurs in the per-frame tracking path.
final class FaceAdornmentCompositor {
    private var sprites: [String: CIImage] = [:]
    private var cachedNeonContour: [CGPoint] = []
    private var cachedNeonFrameSize = CGSize.zero
    private var cachedNeonClosed = true
    private var cachedNeonEyeDistance: CGFloat = 0
    private var cachedNeonImage: CIImage?

    func composite(over source: CIImage, pose: FaceARPose, lensId: String,
                   time: Double, intensity: CGFloat) -> CIImage {
        let eyeAxis = pose.pixelEyeAxis(in: source.extent.size)
        let distance = hypot(eyeAxis.x, eyeAxis.y)
        let pixelRoll = atan2(eyeAxis.y, eyeAxis.x)
        guard distance > 8 else { return source }
        let center = CGPoint(x: pose.center.x * source.extent.width, y: pose.center.y * source.extent.height)
        var output = source
        func place(_ sprite: CIImage, x: CGFloat, y: CGFloat, radius: CGFloat, angle: CGFloat = 0, widthScale: CGFloat = 1, opacity: CGFloat = 1) {
            // The sprite origin is centered, so rotation never moves the anchor.
            var image = sprite.transformed(by: CGAffineTransform(translationX: -sprite.extent.midX, y: -sprite.extent.midY))
            image = image.transformed(by: CGAffineTransform(scaleX: radius * 2 * distance * widthScale / sprite.extent.width,
                                                           y: radius * 2 * distance / sprite.extent.height))
            image = image.transformed(by: CGAffineTransform(rotationAngle: angle))
            image = image.transformed(by: CGAffineTransform(translationX: x * distance, y: -y * distance))
            image = image.transformed(by: CGAffineTransform(rotationAngle: pixelRoll))
            image = image.transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
            if intensity * opacity < 0.999 {
                image = image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, intensity * opacity))])
            }
            output = image.composited(over: output)
        }
        if lensId == "face_neon" {
            guard var outline = neonImage(pose: pose, frameSize: source.extent.size, eyeDistance: distance) else { return source }
            let alpha = max(0, intensity) * (0.88 + 0.12 * sin(CGFloat(time) * 1.7))
            outline = outline.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
            output = outline.composited(over: source)
        } else if lensId == "face_butterflies" {
            for i in 0..<5 {
                let index = CGFloat(i)
                let phase = CGFloat(time) * 5.4 + index * 1.9
                let x = (index - 2) * 0.44 + sin(CGFloat(time) * 0.8 + index) * 0.035
                let y = -0.85 - (1 - abs(index - 2) / 2) * 0.38 + sin(phase * 0.3) * 0.045
                // The wing span oscillates around the anchored body. All five
                // butterflies retain their own phase as the head moves.
                place(sprite(i % 2 == 0 ? "butterflyLilac" : "butterflyBlue"),
                      x: x, y: y, radius: i == 2 ? 0.22 : 0.17,
                      angle: (index - 2) * 0.14,
                      widthScale: 0.42 + 0.58 * abs(sin(phase)))
            }
        } else if lensId == "face_freckles" {
            // Two cheek patches share exactly the same artwork, mirrored.
            let patch = sprite("freckles")
            place(patch, x: -0.55, y: 0.4, radius: 0.32)
            place(patch.transformed(by: CGAffineTransform(scaleX: -1, y: 1)), x: 0.55, y: 0.4, radius: 0.32)
        } else {
            let icon = sprite(lensId == "face_hearts" ? "heart" : "star")
            for i in 0..<7 {
                let index = CGFloat(i)
                let x = (index - 3) * 0.36
                let y = -0.72 - 0.32 * (1 - abs(index - 3) / 3) + sin(CGFloat(time) * 1.8 + index) * 0.045
                let radius = (0.09 + CGFloat(i % 3) * 0.025) * (1 + sin(CGFloat(time) * 2.2 + index) * 0.12)
                place(icon, x: x, y: y, radius: radius,
                      angle: lensId == "face_hearts" ? 0 : CGFloat(time) * 0.16 + index)
            }
            if lensId == "face_celestial" {
                for side in [-1.0, 1.0] { for i in 0..<3 {
                    place(icon, x: CGFloat(side) * (0.45 + CGFloat(i) * 0.17), y: 0.3 + CGFloat(i) * 0.025,
                          radius: 0.038 + 0.012 * sin(CGFloat(time) * 2 + CGFloat(i)))
                }}
            }
        }
        return output.cropped(to: source.extent)
    }

    /// Rasterize only a bounded face-sized tile when the detector pose changes.
    /// The camera-sized frame never enters UIKit; compositing and pulsing remain
    /// on Core Image. Missing contours pass through rather than inventing a jaw.
    private func neonImage(pose: FaceARPose, frameSize: CGSize, eyeDistance: CGFloat) -> CIImage? {
        guard pose.contour.count >= 12 else { return nil }
        if cachedNeonContour == pose.contour && cachedNeonFrameSize == frameSize && cachedNeonClosed == pose.contourClosed && cachedNeonEyeDistance == eyeDistance {
            return cachedNeonImage
        }
        let points = pose.contour.map { CGPoint(x: $0.x * frameSize.width, y: $0.y * frameSize.height) }
        guard let minX = points.map({ $0.x }).min(), let maxX = points.map({ $0.x }).max(),
              let minY = points.map({ $0.y }).min(), let maxY = points.map({ $0.y }).max(),
              minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { return nil }
        let padding = eyeDistance * 0.12
        let bounds = CGRect(x: minX - padding, y: minY - padding,
                            width: maxX - minX + padding * 2, height: maxY - minY + padding * 2)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = min(1, 512 / max(bounds.width, bounds.height))
        let tileSize = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: tileSize, format: format).image { renderer in
            let cg = renderer.cgContext
            let path = UIBezierPath()
            for (index, point) in points.enumerated() {
                let local = CGPoint(x: (point.x - bounds.minX) * scale,
                                    y: tileSize.height - (point.y - bounds.minY) * scale)
                if index == 0 { path.move(to: local) } else { path.addLine(to: local) }
            }
            if pose.contourClosed { path.close() }
            for (width, opacity) in [(0.075, 24.0), (0.035, 65.0), (0.009, 230.0)] {
                cg.saveGState()
                cg.setLineJoin(.round); cg.setLineCap(.round)
                cg.setLineWidth(eyeDistance * CGFloat(width) * scale)
                cg.addPath(path.cgPath); cg.replacePathWithStrokedPath(); cg.clip()
                let alpha = CGFloat(opacity / 255)
                let colors = [UIColor(red: 97/255, green: 250/255, blue: 243/255, alpha: alpha).cgColor,
                              UIColor(red: 162/255, green: 126/255, blue: 1, alpha: alpha).cgColor,
                              UIColor(red: 1, green: 121/255, blue: 197/255, alpha: alpha).cgColor]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: tileSize.width, y: tileSize.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                cg.restoreGState()
            }
        }
        let result = CIImage(image: image)?
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
        cachedNeonContour = pose.contour
        cachedNeonFrameSize = frameSize
        cachedNeonClosed = pose.contourClosed
        cachedNeonEyeDistance = eyeDistance
        cachedNeonImage = result
        return result
    }

    private func sprite(_ id: String) -> CIImage {
        if let image = sprites[id] { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { renderer in
            let cg = renderer.cgContext
            if id.hasPrefix("butterfly") {
                let lilac = id == "butterflyLilac"
                let wingColor = lilac
                    ? UIColor(red: 0.68, green: 0.42, blue: 1, alpha: 0.94)
                    : UIColor(red: 0.22, green: 0.73, blue: 1, alpha: 0.94)
                for side in [-1.0, 1.0] {
                    cg.saveGState()
                    if side < 0 { cg.translateBy(x: 128, y: 0); cg.scaleBy(x: -1, y: 1) }
                    let wing = UIBezierPath()
                    wing.move(to: CGPoint(x: 63, y: 59))
                    wing.addCurve(to: CGPoint(x: 112, y: 20), controlPoint1: CGPoint(x: 77, y: 34), controlPoint2: CGPoint(x: 101, y: 7))
                    wing.addCurve(to: CGPoint(x: 81, y: 70), controlPoint1: CGPoint(x: 132, y: 48), controlPoint2: CGPoint(x: 105, y: 66))
                    wing.addCurve(to: CGPoint(x: 76, y: 111), controlPoint1: CGPoint(x: 115, y: 70), controlPoint2: CGPoint(x: 105, y: 116))
                    wing.addCurve(to: CGPoint(x: 63, y: 59), controlPoint1: CGPoint(x: 62, y: 103), controlPoint2: CGPoint(x: 63, y: 79))
                    wing.close()
                    cg.addPath(wing.cgPath); cg.clip()
                    let colors = [UIColor(white: 1, alpha: 0.96).cgColor, wingColor.cgColor,
                                  UIColor(red: 0.18, green: 0.14, blue: 0.48, alpha: 0.98).cgColor]
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.52, 1]) {
                        cg.drawLinearGradient(gradient, start: CGPoint(x: 58, y: 55), end: CGPoint(x: 116, y: 42), options: [])
                    }
                    cg.setStrokeColor(UIColor(white: 1, alpha: 0.48).cgColor)
                    cg.setLineWidth(0.9)
                    for destination in [CGPoint(x: 105, y: 26), CGPoint(x: 109, y: 46), CGPoint(x: 91, y: 92)] {
                        cg.move(to: CGPoint(x: 65, y: 65)); cg.addLine(to: destination)
                    }
                    cg.strokePath()
                    cg.setFillColor(UIColor(white: 1, alpha: 0.82).cgColor)
                    for dot in [CGPoint(x: 105, y: 32), CGPoint(x: 107, y: 43), CGPoint(x: 94, y: 90)] {
                        cg.fillEllipse(in: CGRect(x: dot.x, y: dot.y, width: 2.8, height: 2.8))
                    }
                    cg.restoreGState()
                }
                cg.setFillColor(UIColor(red: 0.15, green: 0.11, blue: 0.28, alpha: 1).cgColor)
                cg.fillEllipse(in: CGRect(x: 61, y: 48, width: 6, height: 45))
                cg.setStrokeColor(UIColor(white: 0.95, alpha: 0.9).cgColor); cg.setLineWidth(1.3)
                cg.move(to: CGPoint(x: 63, y: 52)); cg.addQuadCurve(to: CGPoint(x: 53, y: 35), control: CGPoint(x: 63, y: 36))
                cg.move(to: CGPoint(x: 65, y: 52)); cg.addQuadCurve(to: CGPoint(x: 75, y: 35), control: CGPoint(x: 65, y: 36))
                cg.strokePath()
            } else if id == "freckles" {
                cg.setFillColor(UIColor(red: 112/255, green: 60/255, blue: 40/255, alpha: 0.43).cgColor)
                for i in 0..<18 {
                    let x = CGFloat((i * 37) % 100) + 10
                    let y = CGFloat((i * 23) % 100) * 0.48 + 34
                    let r = CGFloat(2 + i % 3)
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
            } else {
                let path = UIBezierPath()
                if id == "heart" {
                    path.move(to: CGPoint(x: 64, y: 115))
                    path.addCurve(to: CGPoint(x: 64, y: 32), controlPoint1: CGPoint(x: -32, y: 54), controlPoint2: CGPoint(x: 16, y: -16))
                    path.addCurve(to: CGPoint(x: 64, y: 115), controlPoint1: CGPoint(x: 112, y: -16), controlPoint2: CGPoint(x: 160, y: 54))
                } else {
                    for i in 0..<8 {
                        let a = CGFloat(i) * .pi / 4
                        let r: CGFloat = i % 2 == 0 ? 58 : 14.5
                        let p = CGPoint(x: 64 + cos(a)*r, y: 64 + sin(a)*r)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                path.close(); cg.addPath(path.cgPath); cg.clip()
                let colors = id == "heart"
                    ? [UIColor(red: 1, green: 0.79, blue: 0.86, alpha: 0.95).cgColor, UIColor(red: 0.93, green: 0.28, blue: 0.49, alpha: 0.92).cgColor]
                    : [UIColor(red: 1, green: 0.98, blue: 0.83, alpha: 0.98).cgColor, UIColor(red: 0.87, green: 0.65, blue: 0.32, alpha: 0.95).cgColor]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0,1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 100, y: 128), options: [])
                }
            }
        }
        let result = CIImage(image: image) ?? CIImage.empty()
        sprites[id] = result
        return result
    }
}
