import CoreImage
import Metal
import UIKit

struct CreativeLensContext {
    let languageCode: String
    let countryCode: String
    let mirrorOutput: Bool
    let compositionId: String
    let placeStyle: String
    let placeX, placeY, placeScale, placeRotation: CGFloat
    let placeArtwork: UIImage?
    let placeName: String

    var hasOverlay: Bool { CreativeLensFrameRenderer.lensIds.contains(compositionId) || (placeStyle != "none" && !placeName.isEmpty) }

    init(languageCode: String = "en", countryCode: String = "", mirrorOutput: Bool = false,
         compositionId: String = "none", placeStyle: String = "none", placeName: String = "",
         placeX: CGFloat = 0.5, placeY: CGFloat = 0.68, placeScale: CGFloat = 1, placeRotation: CGFloat = 0, placeArtwork: UIImage? = nil) {
        self.languageCode = String(languageCode.prefix(8)).lowercased()
        self.countryCode = String(countryCode.prefix(3)).uppercased()
        self.mirrorOutput = mirrorOutput
        self.compositionId = compositionId
        self.placeX = placeX; self.placeY = placeY; self.placeScale = placeScale; self.placeRotation = placeRotation; self.placeArtwork = placeArtwork
        self.placeStyle = placeStyle
        self.placeName = String(placeName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    }
}

/// Native Core Image compositor used by the live texture, photo capture and
/// video recorder. The selected lens is therefore never a preview-only widget.
final class CreativeLensFrameRenderer {
    static let lensIds: Set<String> = [
        "vhs1993", "daytime", "timefocus", "kuwaitgold", "retrodate"
    ]

    static let adornmentIds: Set<String> = ["face_celestial", "face_hearts", "face_freckles", "face_neon", "face_butterflies"]
    private let context: CIContext
    private let adornments = FaceAdornmentCompositor()
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private var cachedOverlay: CIImage?
    private var cachedKey = ""

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
        }
    }

    func render(
        input: CVPixelBuffer,
        lensId: String,
        intensity: CGFloat,
        lensContext: CreativeLensContext,
        pose: FaceARPose? = nil,
        time: Double = 0
    ) -> CVPixelBuffer? {
        if pose == nil { adornments.resetExpressions() }
        if pose == nil && !Self.lensIds.contains(lensId) && !lensContext.hasOverlay { return input }
        return render(source: CIImage(cvPixelBuffer: input), lensId: lensId, intensity: intensity,
               lensContext: lensContext, pose: pose, time: time)
    }

    func render(source input: CIImage, lensId: String, intensity: CGFloat,
                lensContext: CreativeLensContext, pose: FaceARPose? = nil,
                time: Double = 0, isPhoto: Bool = false) -> CVPixelBuffer? {
        let width = Int(input.extent.width)
        let height = Int(input.extent.height)
        guard let output = outputBuffer(width: width, height: height) else { return nil }
        var source = input
        if let pose = pose, Self.adornmentIds.contains(lensId) {
            source = adornments.composite(over: source, pose: pose, lensId: lensId, time: time, intensity: intensity, isPhoto: isPhoto)
        }
        if pose == nil && !isPhoto { adornments.resetExpressions() }
        // Face-only lenses never rasterize a full-frame transparent UIKit image.
        // Static text is composed once and covers the actual upright buffer size.
        if Self.lensIds.contains(lensId) || Self.lensIds.contains(lensContext.compositionId) {
            source = overlayImage(size: CGSize(width: width, height: height),
                                  lensId: lensId, intensity: min(max(intensity, 0), 1),
                                  lensContext: lensContext).composited(over: source)
        }
        if lensContext.placeStyle != "none", !lensContext.placeName.isEmpty,
           let artwork = lensContext.placeArtwork, let sticker = CIImage(image: artwork) {
            let unit = min(CGFloat(width)/1080, CGFloat(height)/1920) * lensContext.placeScale
            // CI uses a bottom-left origin; Flutter's clockwise angle is negative here.
            var positioned = sticker
                .transformed(by: CGAffineTransform(translationX: -sticker.extent.midX, y: -sticker.extent.midY))
                .transformed(by: CGAffineTransform(scaleX: unit, y: unit))
                .transformed(by: CGAffineTransform(rotationAngle: -lensContext.placeRotation))
                .transformed(by: CGAffineTransform(translationX: CGFloat(width)*lensContext.placeX,
                    y: CGFloat(height)*(1-lensContext.placeY)))
            if lensContext.mirrorOutput {
                positioned = positioned.transformed(by: CGAffineTransform(a:-1,b:0,c:0,d:1,tx:CGFloat(width),ty:0))
            }
            source = positioned.composited(over: source)
        }
        let composed = source.cropped(to: input.extent)
        context.render(
            composed,
            to: output,
            bounds: source.extent,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return output
    }

    func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92)
    }

    private func overlayImage(
        size: CGSize,
        lensId: String,
        intensity: CGFloat,
        lensContext: CreativeLensContext
    ) -> CIImage {
        let now = Date()
        // The authored overlays display minute-level time. Rebuilding a full
        // resolution transparent UIKit image every second caused avoidable
        // capture-stream hitches on older iPhones, while changing no visible
        // information that matters to the lens.
        let cadence = Int(now.timeIntervalSince1970 / 60)
        let key = "\(lensContext.compositionId)|\(lensContext.placeStyle)|\(lensContext.placeName)|\(lensId)|\(Int(size.width))x\(Int(size.height))|\(cadence)|\(lensContext.languageCode)|\(lensContext.countryCode)|\(lensContext.mirrorOutput)|\(Int(intensity * 100))"
        if key == cachedKey, let cachedOverlay = cachedOverlay { return cachedOverlay }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let cg = renderer.cgContext
            cg.clear(CGRect(origin: .zero, size: size))
            if lensContext.mirrorOutput {
                cg.translateBy(x: size.width, y: 0)
                cg.scaleBy(x: -1, y: 1)
            }
            let unit = max(0.35, min(size.width / 1080, size.height / 1920))
            switch lensContext.compositionId != "none" ? lensContext.compositionId : lensId {
            case "vhs1993": drawAnalog(in: cg, size: size, unit: unit, intensity: intensity, now: now, value: lensContext)
            case "daytime": drawGolden(in: cg, size: size, unit: unit, intensity: intensity, now: now, value: lensContext)
            case "timefocus": drawStudio(in: cg, size: size, unit: unit, intensity: intensity, now: now, value: lensContext)
            case "kuwaitgold": drawDesert(in: cg, size: size, unit: unit, intensity: intensity, now: now, value: lensContext)
            case "retrodate": drawFilm(in: cg, size: size, unit: unit, intensity: intensity, now: now, value: lensContext)
            default: break
            }
        }
        let overlay = CIImage(image: image) ?? CIImage.empty()
        cachedKey = key
        cachedOverlay = overlay
        return overlay
    }

    private func drawAnalog(in cg: CGContext, size: CGSize, unit: CGFloat, intensity: CGFloat, now: Date, value: CreativeLensContext) {
        let arabic = value.languageCode == "ar"
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor(white: 0.03, alpha: 0.26 * intensity).cgColor, UIColor.clear.cgColor] as CFArray,
            locations: [0, 1]
        ) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height * 0.25), options: [])
        }
        rounded(CGRect(x: 34 * unit, y: 36 * unit, width: 146 * unit, height: 52 * unit),
                radius: 18 * unit, color: UIColor(white: 0.04, alpha: 0.80 * intensity), in: cg)
        cg.setFillColor(UIColor(red: 1, green: 0.24, blue: 0.30, alpha: intensity).cgColor)
        cg.fillEllipse(in: CGRect(x: 49 * unit, y: 55 * unit, width: 14 * unit, height: 14 * unit))
        label(arabic ? "تسجيل" : "REC", at: CGPoint(x: 76 * unit, y: 49 * unit), size: 25 * unit,
              color: UIColor(white: 0.98, alpha: 0.96 * intensity), mono: true, bold: true)
        label(arabic ? "كاميرا ٠١" : "CAM 01", at: CGPoint(x: size.width - 34 * unit, y: 49 * unit), size: 23 * unit,
              color: UIColor(white: 0.96, alpha: 0.88 * intensity), mono: true, align: .right)
        label(format("HH:mm", now, locale(value)),
              at: CGPoint(x: 34 * unit, y: size.height - 104 * unit), size: 30 * unit,
              color: UIColor(white: 0.97, alpha: 0.94 * intensity), mono: true, bold: true)
        label(format("dd  MM  yyyy", now, locale(value)),
              at: CGPoint(x: size.width - 34 * unit, y: size.height - 101 * unit), size: 23 * unit,
              color: UIColor(white: 0.97, alpha: 0.87 * intensity), mono: true, align: .right)
    }

    private func drawGolden(in cg: CGContext, size: CGSize, unit: CGFloat, intensity: CGFloat, now: Date, value: CreativeLensContext) {
        cg.setStrokeColor(UIColor(red: 1, green: 220/255, blue: 165/255, alpha: 0.47*intensity).cgColor)
        cg.setFillColor(UIColor(red: 1, green: 220/255, blue: 165/255, alpha: 0.47*intensity).cgColor)
        cg.setLineWidth(2*unit)
        for side in 0...1 {
            cg.saveGState()
            cg.translateBy(x: side == 0 ? 0 : size.width, y: size.height*0.85)
            if side == 1 { cg.scaleBy(x: -1, y: 1) }
            cg.move(to: CGPoint(x:18*unit,y:0))
            cg.addCurve(to:CGPoint(x:145*unit,y:-380*unit),control1:CGPoint(x:95*unit,y:-100*unit),control2:CGPoint(x:55*unit,y:-265*unit));cg.strokePath()
            for i in 0...5 {
                let x=(30+CGFloat(i)*15)*unit, y=(-45-CGFloat(i)*51)*unit
                cg.move(to:CGPoint(x:x,y:y))
                cg.addQuadCurve(to:CGPoint(x:x+63*unit,y:y-49*unit),control:CGPoint(x:x+70*unit,y:y-8*unit))
                cg.addQuadCurve(to:CGPoint(x:x,y:y),control:CGPoint(x:x+13*unit,y:y-40*unit));cg.fillPath()
            }
            cg.restoreGState()
        }
    }

    private func drawStudio(in cg: CGContext, size: CGSize, unit: CGFloat, intensity: CGFloat, now: Date, value: CreativeLensContext) {
        let inset = 40 * unit
        let arm = 76 * unit
        cg.setStrokeColor(UIColor(red: 1, green: 0.92, blue: 0.80, alpha: 0.74 * intensity).cgColor)
        cg.setLineWidth(3 * unit)
        let points: [(CGPoint, CGPoint)] = [
            (.init(x: inset, y: inset), .init(x: inset + arm, y: inset)),
            (.init(x: inset, y: inset), .init(x: inset, y: inset + arm)),
            (.init(x: size.width - inset, y: inset), .init(x: size.width - inset - arm, y: inset)),
            (.init(x: size.width - inset, y: inset), .init(x: size.width - inset, y: inset + arm)),
            (.init(x: inset, y: size.height - inset), .init(x: inset + arm, y: size.height - inset)),
            (.init(x: inset, y: size.height - inset), .init(x: inset, y: size.height - inset - arm)),
            (.init(x: size.width - inset, y: size.height - inset), .init(x: size.width - inset - arm, y: size.height - inset)),
            (.init(x: size.width - inset, y: size.height - inset), .init(x: size.width - inset, y: size.height - inset - arm))
        ]
        points.forEach { cg.move(to: $0.0); cg.addLine(to: $0.1) }
        cg.strokePath()
        let caption = value.languageCode == "ar" ? "بورتريه" : "PORTRAIT"
        label("\(caption)  /  \u{2066}\(format("HH:mm", now, locale(value)))\u{2069}",
              at: CGPoint(x: size.width / 2, y: size.height - 86 * unit), size: 20 * unit,
              color: UIColor(red: 1, green: 0.94, blue: 0.86, alpha: 0.82 * intensity), mono: true, align: .center)
    }

    private func drawDesert(in cg: CGContext, size: CGSize, unit: CGFloat, intensity: CGFloat, now: Date, value: CreativeLensContext) {
        cg.setLineWidth(1.7*unit)
        for i in 0...7 {
            cg.setStrokeColor(UIColor(red:235/255,green:197/255,blue:143/255,alpha:CGFloat(95-i*8)/255*intensity).cgColor)
            let y=size.height-CGFloat(24+i*15)*unit
            cg.move(to:CGPoint(x:0,y:y))
            cg.addCurve(to:CGPoint(x:size.width,y:y-100*unit),control1:CGPoint(x:size.width*0.3,y:y-115*unit),control2:CGPoint(x:size.width*0.55,y:y+55*unit));cg.strokePath()
        }
    }

    private func drawFilm(in cg: CGContext, size: CGSize, unit: CGFloat, intensity: CGFloat, now: Date, value: CreativeLensContext) {
        cg.setFillColor(UIColor(white: 0.02, alpha: 0.32 * intensity).cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: size.width, height: 56 * unit))
        cg.fill(CGRect(x: 0, y: size.height - 56 * unit, width: size.width, height: 56 * unit))
        label(value.languageCode == "ar" ? "٣٥ مم  •  إطار ٢٤" : "35 MM  •  FRAME 24", at: CGPoint(x: 30 * unit, y: 20 * unit), size: 18 * unit,
              color: UIColor(red: 1, green: 0.96, blue: 0.84, alpha: 0.86 * intensity), mono: true)
        label(format("MMM dd  yyyy", now, locale(value)).uppercased(with: locale(value)),
              at: CGPoint(x: size.width - 30 * unit, y: size.height - 43 * unit), size: 19 * unit,
              color: UIColor(red: 1, green: 0.89, blue: 0.72, alpha: 0.88 * intensity), mono: true, align: .right)
        cg.setFillColor(UIColor(red: 1, green: 0.60, blue: 0.24, alpha: 0.72 * intensity).cgColor)
        cg.fillEllipse(in: CGRect(x: size.width - 43 * unit, y: 24 * unit, width: 10 * unit, height: 10 * unit))
    }

    private func locale(_ value: CreativeLensContext) -> Locale {
        let identifier = value.countryCode.isEmpty ? value.languageCode : "\(value.languageCode)_\(value.countryCode)"
        return Locale(identifier: identifier)
    }

    private func format(_ pattern: String, _ date: Date, _ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private func rounded(_ rect: CGRect, radius: CGFloat, color: UIColor, in cg: CGContext) {
        cg.setFillColor(color.cgColor)
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath)
        cg.fillPath()
    }

    private func label(
        _ value: String,
        at point: CGPoint,
        size: CGFloat,
        color: UIColor,
        mono: Bool = false,
        serif: Bool = false,
        bold: Bool = false,
        italic: Bool = false,
        align: NSTextAlignment = .left,
        shadow: CGFloat = 0
    ) {
        let base: UIFont
        if Self.containsArabic(value) { base = .systemFont(ofSize: size, weight: bold || serif ? .bold : .regular) }
        else if mono { base = .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular) }
        else if serif { base = UIFont(name: italic ? "Georgia-BoldItalic" : "Georgia-Bold", size: size) ?? .boldSystemFont(ofSize: size) }
        else { base = .systemFont(ofSize: size, weight: bold ? .bold : .regular) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .natural
        paragraph.alignment = align
        var attributes: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: color, .paragraphStyle: paragraph]
        if shadow > 0 {
            let value = NSShadow(); value.shadowBlurRadius = shadow; value.shadowOffset = CGSize(width: 0, height: shadow * 0.25); value.shadowColor = UIColor.black.withAlphaComponent(0.7)
            attributes[.shadow] = value
        }
        let width = max(1, cachedCanvasWidth - point.x)
        let rect: CGRect
        switch align {
        case .center: rect = CGRect(x: 0, y: point.y, width: cachedCanvasWidth, height: size * 1.6)
        case .right: rect = CGRect(x: 0, y: point.y, width: point.x, height: size * 1.6)
        default: rect = CGRect(x: point.x, y: point.y, width: width, height: size * 1.6)
        }
        (value as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func containsArabic(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x0600...0x08FF).contains($0.value) }
    }

    private var cachedCanvasWidth: CGFloat {
        CGFloat(poolSize.width)
    }

    private func outputBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let size = CGSize(width: width, height: height)
        if pool == nil || poolSize != size {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var newPool: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool) == kCVReturnSuccess else { return nil }
            pool = newPool
            poolSize = size
            cachedKey = ""
            cachedOverlay = nil
        }
        var buffer: CVPixelBuffer?
        guard let pool = pool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }
}
