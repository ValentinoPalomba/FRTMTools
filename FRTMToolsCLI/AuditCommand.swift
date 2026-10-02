import AppKit
import CoreText
import Foundation

/// Static artifact audit. The embedded collector uses only the Python standard library;
/// PDF export uses macOS CoreText so a CLI installation has no pip dependencies.
enum AuditCommand {
    struct Manifest: Decodable {
        struct Report: Decodable { let json: String; let pdf: String }
        let reports: [Report]
    }
    struct Document: Decodable {
        struct Block: Decodable {
            let title: String
            let headers: [String]
            let rows: [[Cell]]
            let note: String?
        }
        let title: String
        let blocks: [Block]
    }
    struct Cell: Decodable {
        let text: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { text = "Non disponibile" }
            else if let value = try? c.decode(String.self) { text = value }
            else if let value = try? c.decode(Bool.self) { text = value ? "Sì" : "No" }
            else if let value = try? c.decode(Int64.self) { text = String(value) }
            else { text = String(try c.decode(Double.self)) }
        }
    }

    static func run(_ arguments: [String]) throws -> Int32 {
        if arguments.contains("--help") || arguments.contains("-h") {
            print("Usage: frtmtools audit <package-or-folder> [--output <directory>] [--offline] [--app-map <json>]")
            print("Outputs: individual HTML/PDF reports, JSON evidence and index-audit.html.")
            print("Inputs: APK, IPA, APP, xcarchive folders or a single xcarchive.zip.")
            print("Requires Python 3.9+; APK additionally requires Android SDK cmdline-tools/build-tools.")
            return 0
        }
        var input: String?
        var output: String?
        var offline = false
        var appMap: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "-o", "--output":
                index += 1
                guard index < arguments.count else { throw error("Missing output directory") }
                output = arguments[index]
            case "--offline": offline = true
            case "--app-map":
                index += 1
                guard index < arguments.count else { throw error("Missing app map JSON path") }
                appMap = URL(fileURLWithPath: arguments[index]).standardizedFileURL.path
            default:
                guard !arguments[index].hasPrefix("-"), input == nil else {
                    throw error("Unknown option or extra input: \(arguments[index])")
                }
                input = arguments[index]
            }
            index += 1
        }
        guard let input else { throw error("Provide a package or folder. See frtmtools audit --help.") }
        let source = URL(fileURLWithPath: input).standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else { throw error("Input does not exist: \(source.path)") }
        let destination = output.map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? source.deletingLastPathComponent().appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-audit")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let manifestURL = destination.appendingPathComponent("audit-run.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-", source.path, destination.path] + (offline ? ["--offline"] : []) + (appMap.map { ["--app-map", $0] } ?? [])
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(AuditCollector.source.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw error("Audit collector failed (exit \(process.terminationStatus)); check Python/SDK diagnostics above.")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        for report in manifest.reports {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: destination.appendingPathComponent(report.json)))
            try writePDF(document, to: destination.appendingPathComponent(report.pdf))
        }
        print("Audit: \(destination.path) (\(manifest.reports.count) HTML/PDF reports)")
        return process.terminationStatus
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "FRTMTools.Audit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func writePDF(_ document: Document, to url: URL) throws {
        let text = NSMutableAttributedString()
        func append(_ string: String, size: CGFloat = 9.5, bold: Bool = false) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            paragraph.paragraphSpacing = 5
            text.append(NSAttributedString(string: string + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.21, alpha: 1),
                .paragraphStyle: paragraph
            ]))
        }
        append(document.title, size: 21, bold: true)
        for block in document.blocks {
            append(block.title, size: 14, bold: true)
            if let note = block.note, !note.isEmpty { append(note, size: 9) }
            if block.rows.isEmpty { append("Nessun riscontro / dati non disponibili") }
            for row in block.rows {
                append(zip(block.headers, row).map { "\($0): \($1.text)" }.joined(separator: " | "))
            }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw error("Cannot create PDF: \(url.path)")
        }
        var offset = 0
        var page = 1
        while offset < text.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: CGRect(x: 44, y: 48, width: 507, height: 750), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context)
            let range = CTFrameGetVisibleStringRange(frame)
            guard range.length > 0 else { context.endPDFPage(); context.closePDF(); throw error("PDF pagination failed") }
            let footer = NSAttributedString(string: "FRTMTools - Audit statico | Pagina \(page)", attributes: [.font: NSFont.systemFont(ofSize: 8)])
            context.textPosition = CGPoint(x: 44, y: 24)
            CTLineDraw(CTLineCreateWithAttributedString(footer), context)
            context.endPDFPage()
            offset += range.length
            page += 1
        }
        context.closePDF()
    }
}
