import CoreImage
import Metal
import UIKit

struct CreativeLensContext {
    let languageCode: String
    let countryCode: String
    let mirrorOutput: Bool
    let compositionId: String
    let placeStyle: String
    let placeName: String

    var hasOverlay: Bool { CreativeLensFrameRenderer.lensIds.contains(compositionId) || (placeStyle != "none" && !placeName.isEmpty) }

    init(languageCode: String = "en", countryCode: String = "", mirrorOutput: Bool = false,
         compositionId: String = "none", placeStyle: String = "none", placeName: String = "") {
        self.languageCode = String(languageCode.prefix(8)).lowercased()
        self.countryCode = String(countryCode.prefix(3)).uppercased()
        self.mirrorOutput = mirrorOutput
        self.compositionId = compositionId
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
        if Self.lensIds.contains(lensId) || lensContext.hasOverlay {
            source = overlayImage(size: CGSize(width: width, height: height),
                                  lensId: lensId, intensity: min(max(intensity, 0), 1),
                                  lensContext: lensContext).composited(over: source)
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
            if lensContext.placeStyle != "none" && !lensContext.placeName.isEmpty {
                drawPlace(in: cg, size: size, unit: unit, now: now, value: lensContext)
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
        let locale = locale(value)
        let baseline = size.height * 0.65
        label(format("EEEE", now, locale), at: CGPoint(x: size.width / 2, y: baseline),
              size: 76 * unit, color: UIColor(red: 1, green: 0.98, blue: 0.91, alpha: 0.95 * intensity),
              serif: true, bold: true, italic: true, align: .center, shadow: 8 * unit)
        label(format("h:mm a", now, locale), at: CGPoint(x: size.width / 2, y: baseline + 58 * unit),
              size: 32 * unit, color: UIColor(red: 1, green: 0.91, blue: 0.70, alpha: 0.90 * intensity),
              bold: true, align: .center)
        cg.setFillColor(UIColor(red: 1, green: 0.70, blue: 0.30, alpha: 0.75 * intensity).cgColor)
        cg.fill(CGRect(x: size.width / 2 - 150 * unit, y: baseline + 82 * unit, width: 300 * unit, height: 4 * unit))
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
        let locale = locale(value)
        let width = min(size.width * 0.72, 720 * unit)
        rounded(CGRect(x: (size.width - width) / 2, y: 42 * unit, width: width, height: 82 * unit),
                radius: 34 * unit, color: UIColor(red: 0.16, green: 0.11, blue: 0.07, alpha: 0.70 * intensity), in: cg)
        label(countryName(value, locale: locale).uppercased(with: locale),
              at: CGPoint(x: size.width / 2, y: 69 * unit), size: 30 * unit,
              color: UIColor(red: 1, green: 0.88, blue: 0.66, alpha: 0.96 * intensity), bold: true, align: .center)
        label(format("EEEE  •  d MMMM", now, locale),
              at: CGPoint(x: size.width / 2, y: size.height - 105 * unit), size: 27 * unit,
              color: UIColor(red: 1, green: 0.89, blue: 0.69, alpha: 0.92 * intensity),
              serif: true, bold: true, align: .center, shadow: 7 * unit)
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

    private func drawPlace(in cg: CGContext, size: CGSize, unit u: CGFloat, now: Date, value: CreativeLensContext) {
        let w = size.width, baseline = size.height * 0.73
        let cream = UIColor(red: 1, green: 245/255, blue: 225/255, alpha: 1)
        let gold = UIColor(red: 230/255, green: 193/255, blue: 134/255, alpha: 1)
        let arabic = value.languageCode == "ar"
        func title(_ text: String, x: CGFloat, baseline: CGFloat, size: CGFloat, color: UIColor,
                   maxWidth: CGFloat, centered: Bool = true, rightAligned: Bool = false, serif: Bool = true) {
            let font = (Self.containsArabic(text) || !serif) ? UIFont.boldSystemFont(ofSize: size)
                : (UIFont(name: "Georgia-BoldItalic", size: size) ?? .boldSystemFont(ofSize: size))
            let measured = (text as NSString).size(withAttributes: [.font: font]).width
            let fitted = font.withSize(size * min(1, maxWidth / max(measured, 1)))
            let width = (text as NSString).size(withAttributes: [.font: fitted]).width
            let paragraph = NSMutableParagraphStyle()
            paragraph.baseWritingDirection = .natural
            paragraph.alignment = rightAligned ? .right : .left
            paragraph.lineBreakMode = .byClipping
            let left = centered ? x - width/2 : (rightAligned ? x - width : x)
            (text as NSString).draw(in: CGRect(x: left, y: baseline - fitted.ascender,
                                               width: ceil(width) + 1, height: fitted.lineHeight * 1.6),
                                   withAttributes: [.font: fitted, .foregroundColor: color, .paragraphStyle: paragraph])
        }
        func rule(_ left: CGFloat, _ y: CGFloat, _ right: CGFloat) {
            cg.setStrokeColor(gold.cgColor); cg.setLineWidth(2*u)
            cg.move(to: CGPoint(x: left,y: y)); cg.addLine(to: CGPoint(x: right,y: y)); cg.strokePath()
        }
        switch value.placeStyle {
        case "postcard":
            let left=w*0.07, right=w*0.93, top=baseline-180*u, bottom=baseline+64*u
            let ink=UIColor(red: 27/255,green: 37/255,blue: 52/255,alpha: 1)
            let red=UIColor(red: 219/255,green: 45/255,blue: 57/255,alpha: 1)
            rounded(CGRect(x:left,y:top,width:right-left,height:bottom-top),radius:10*u,
                color:UIColor(red:250/255,green:249/255,blue:245/255,alpha:1),in:cg)
            let edge=(right-left)/24
            for i in 0..<24 {
                cg.setFillColor((i%2 == 0 ? red : UIColor(red:38/255,green:66/255,blue:103/255,alpha:1)).cgColor)
                cg.fill(CGRect(x:left+CGFloat(i)*edge,y:top,width:edge,height:7*u))
            }
            let leading=arabic ? right-28*u : left+28*u
            let align: NSTextAlignment=arabic ? .right : .left
            label(arabic ? "بطاقة بريدية · تحية من" : "POSTCARD / GREETINGS FROM",at:CGPoint(x:leading,y:top+22*u),size:19*u,color:red,mono:true,align:align)
            title(value.placeName,x:leading,baseline:top+124*u,size:64*u,color:ink,maxWidth:(right-left)*0.72,centered:false,rightAligned:arabic)
            label(format("dd MMM yyyy",now,locale(value)),at:CGPoint(x:leading,y:bottom-48*u),size:20*u,color:ink,mono:true,align:align)
            let stampX=arabic ? left+70*u : right-70*u
            cg.setStrokeColor(red.cgColor);cg.setLineWidth(3*u)
            cg.strokeEllipse(in:CGRect(x:stampX-43*u,y:top+73*u,width:86*u,height:86*u))
            cg.strokeEllipse(in:CGRect(x:stampX-35*u,y:top+81*u,width:70*u,height:70*u))
            label(format("dd",now,locale(value)),at:CGPoint(x:stampX,y:top+99*u),size:25*u,color:red,mono:true,align:.center)
        case "editorial":
            let left=w*0.07, right=w*0.93, top=baseline-166*u
            let leading=arabic ? right-32*u : left+32*u
            let align: NSTextAlignment=arabic ? .right : .left
            rounded(CGRect(x:left,y:top,width:right-left,height:226*u),radius:10*u,
                color:UIColor(red:16/255,green:18/255,blue:22/255,alpha:0.88),in:cg)
            cg.setFillColor(UIColor(red:237/255,green:52/255,blue:68/255,alpha:1).cgColor)
            cg.fill(CGRect(x:arabic ? right-7*u : left,y:top,width:7*u,height:226*u))
            label(arabic ? "من قلب المكان" : "ON LOCATION",at:CGPoint(x:leading,y:top+22*u),size:20*u,color:UIColor(red:245/255,green:78/255,blue:88/255,alpha:1),mono:true,align:align)
            title(value.placeName,x:leading,baseline:top+126*u,size:68*u,color:.white,maxWidth:w*0.77,centered:false,rightAligned:arabic,serif:false)
            label(format("EEEE  /  HH:mm",now,locale(value)),at:CGPoint(x:leading,y:top+169*u),size:21*u,color:UIColor(white:0.82,alpha:1),mono:true,align:align)
        case "stamp":
            cg.saveGState(); cg.translateBy(x: w/2,y: baseline-20*u); cg.rotate(by: -.pi*7/180)
            cg.translateBy(x: -w/2,y: -baseline+20*u)
            rounded(CGRect(x: w*0.18,y: baseline-155*u,width: w*0.64,height: 244*u),radius: 12*u,
                    color: UIColor(red: 247/255,green: 234/255,blue: 207/255,alpha: 0.88),in: cg)
            let ink = UIColor(red: 45/255,green: 70/255,blue: 62/255,alpha: 1)
            cg.setStrokeColor(ink.cgColor);cg.setLineWidth(3*u)
            cg.addPath(UIBezierPath(roundedRect: CGRect(x: w*0.18+14*u,y: baseline-141*u,width: w*0.64-28*u,height: 216*u),cornerRadius: 7*u).cgPath)
            cg.strokePath()
            label(arabic ? "ذكريات السفر" : "A MOMENT IN",at: CGPoint(x: w/2,y: baseline-117*u),size: 20*u,color: ink,mono: true,align: .center)
            title(value.placeName,x: w/2,baseline: baseline-20*u,size: 61*u,color: ink,maxWidth: w*0.53)
            label(format("dd . MM . yyyy",now,locale(value)),at: CGPoint(x: w/2,y: baseline+18*u),size: 22*u,color: ink,mono: true,align: .center)
            cg.restoreGState()
        default: break
        }
    }

    private func locale(_ value: CreativeLensContext) -> Locale {
        let identifier = value.countryCode.isEmpty ? value.languageCode : "\(value.languageCode)_\(value.countryCode)"
        return Locale(identifier: identifier)
    }

    private func countryName(_ value: CreativeLensContext, locale: Locale) -> String {
        return value.placeName.isEmpty
            ? (value.languageCode.hasPrefix("ar") ? "الساعة الذهبية" : "GOLDEN HOUR")
            : value.placeName
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
