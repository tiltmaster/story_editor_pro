import CoreImage
import UIKit

/// Small, cached vector sprites transformed on the GPU using the live face pose.
/// No full-resolution UIKit allocation occurs in the per-frame tracking path.
final class FaceAdornmentCompositor {
    private var sprites: [String: CIImage] = [:]

    func composite(over source: CIImage, pose: FaceARPose, lensId: String,
                   time: Double, intensity: CGFloat) -> CIImage {
        let distance = pose.eyeDistance * source.extent.width
        guard distance > 8 else { return source }
        let center = CGPoint(x: pose.center.x * source.extent.width, y: pose.center.y * source.extent.height)
        var output = source
        func place(_ sprite: CIImage, x: CGFloat, y: CGFloat, radius: CGFloat, angle: CGFloat = 0) {
            // The sprite origin is centered, so rotation never moves the anchor.
            var image = sprite.transformed(by: CGAffineTransform(translationX: -sprite.extent.midX, y: -sprite.extent.midY))
            image = image.transformed(by: CGAffineTransform(scaleX: radius * 2 * distance / sprite.extent.width,
                                                           y: radius * 2 * distance / sprite.extent.height))
            image = image.transformed(by: CGAffineTransform(rotationAngle: angle))
            image = image.transformed(by: CGAffineTransform(translationX: x * distance, y: -y * distance))
            image = image.transformed(by: CGAffineTransform(rotationAngle: pose.rollRadians))
            image = image.transformed(by: CGAffineTransform(translationX: center.x, y: center.y))
            if intensity < 0.999 {
                image = image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, intensity))])
            }
            output = image.composited(over: output)
        }
        if lensId == "face_freckles" {
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

    private func sprite(_ id: String) -> CIImage {
        if let image = sprites[id] { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { renderer in
            let cg = renderer.cgContext
            if id == "freckles" {
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
