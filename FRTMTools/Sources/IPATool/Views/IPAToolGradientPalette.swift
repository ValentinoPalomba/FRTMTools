import AppKit
import CoreImage

struct AppGradientPalette {
    let colors: [NSColor]
    let useLightText: Bool
}

func defaultAppGradient(for app: IPAToolStoreApp) -> AppGradientPalette {
    let bundle = app.bundleId
    var hash: UInt64 = 1469598103934665603
    for scalar in bundle.unicodeScalars {
        hash = (hash ^ UInt64(scalar.value)) &* 1099511628211
    }
    let baseHue = Double(hash % 360) / 360.0
    let secondaryHue = (baseHue + 0.07).truncatingRemainder(dividingBy: 1)
    let accentHue = (baseHue + 0.14).truncatingRemainder(dividingBy: 1)

    let colors = [
        NSColor(hue: baseHue, saturation: 0.70, brightness: 0.95, alpha: 1),
        NSColor(hue: secondaryHue, saturation: 0.65, brightness: 0.8, alpha: 1),
        NSColor(hue: accentHue, saturation: 0.6, brightness: 0.6, alpha: 1)
    ]
    return AppGradientPalette(colors: colors, useLightText: shouldUseLightText(for: colors))
}

enum AppIconPaletteGenerator {
    static func palette(from image: NSImage, fallback: AppGradientPalette) -> AppGradientPalette {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallback
        }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: [.workingColorSpace: NSColorSpace.sRGB.cgColorSpace as Any])

        guard let primary = averageColor(of: ciImage, context: context) else {
            return fallback
        }

        let accent = primary.adjusted(brightness: 0.85, saturation: 1.15)
        let highlight = primary.adjusted(brightness: 1.2, saturation: 0.9)

        var colors = [highlight, primary, accent]
        colors = ensureContrast(for: colors)

        return AppGradientPalette(colors: colors, useLightText: shouldUseLightText(for: colors))
    }

    private static func averageColor(of image: CIImage, context: CIContext) -> NSColor? {
        let extent = image.extent
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let outputImage = filter?.outputImage else { return nil }

        let bitmap = calloc(4, MemoryLayout<UInt8>.size)
        defer { free(bitmap) }
        context.render(
            outputImage,
            toBitmap: bitmap!,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let data = bitmap!.assumingMemoryBound(to: UInt8.self)
        let r = CGFloat(data[0]) / 255
        let g = CGFloat(data[1]) / 255
        let b = CGFloat(data[2]) / 255
        let a = CGFloat(data[3]) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func ensureContrast(for colors: [NSColor]) -> [NSColor] {
        guard let reference = colors.first else { return colors }
        let brightness = reference.perceivedBrightness
        if brightness > 0.85 {
            return colors.map { $0.adjusted(brightness: 0.6, saturation: 1.2) }
        } else if brightness < 0.25 {
            return colors.map { $0.adjusted(brightness: 1.4, saturation: 0.8) }
        }
        return colors
    }
}

private func shouldUseLightText(for colors: [NSColor]) -> Bool {
    guard let reference = colors.first else { return true }
    return reference.perceivedBrightness < 0.7
}

private extension NSColor {
    func adjusted(brightness: CGFloat, saturation: CGFloat) -> NSColor {
        let working = usingColorSpace(.sRGB) ?? self
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var alpha: CGFloat = 0
        working.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        return NSColor(hue: hue,
                       saturation: min(max(sat * saturation, 0), 1),
                       brightness: min(max(bri * brightness, 0), 1),
                       alpha: alpha)
    }

    var perceivedBrightness: CGFloat {
        let working = usingColorSpace(.sRGB) ?? self
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        working.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r) + (0.587 * g) + (0.114 * b)
    }
}
