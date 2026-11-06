import AppKit
import AVFoundation
import ImageIO
import PDFKit
import Quartz
import UniformTypeIdentifiers
import Vision

/// 드롭 변환. macOS 기본 프레임워크만 쓴다. 원본은 읽기만 하고, 결과는 임시 파일로 만든 뒤 옮겨서
/// 실패해도 반쯤 만든 파일이 남지 않는다.
enum ConvertOp: String, CaseIterable {
    case toJPEG, toPNG, toHEIC, long1920, long1280, stripInfo, removeBackground, extractText
    case pdfMerge, imagesToPDF, pdfToPNG
    case toMP4, toHEVC, to720p, audioOnly, toGIF
    case toM4A, toWAV, toMP3
    case docToPDF, docToDOCX, docToTXT, docToRTF, docToHTML
    case sheetToCSV
    case zip, unarchive
    // F27 9번: 종류별 변환 늘리기
    case toTIFF, pdfToJPG, pdfToText, pdfSplit, pdfToDOCX, docToODT, csvToXLSX, sheetToPDF, toMOV, posterFrame, toAIFF
    // F33: 목표 용량으로 줄이기(이미지·PDF)
    case shrink500K, shrink1M, shrink2M, shrink5M, shrink10M

    static let shrinks: [ConvertOp] = [.shrink500K, .shrink1M, .shrink2M, .shrink5M, .shrink10M]
    // 이미지 크기 줄이기: 긴 쪽(가로·세로 중 큰 쪽) 픽셀
    case long3840, long2560, long800
    static let longs: [ConvertOp] = [.long3840, .long2560, .long1920, .long1280, .long800]
    var longEdge: Int? {
        switch self {
        case .long3840: 3840
        case .long2560: 2560
        case .long1920: 1920
        case .long1280: 1280
        case .long800: 800
        default: nil
        }
    }

    /// F33 목표 바이트(10진: 1MB = 1,000,000. 제출 사이트가 2진이어도 넘지 않게 작은 쪽)
    var targetBytes: Int? {
        switch self {
        case .shrink500K: 500_000
        case .shrink1M: 1_000_000
        case .shrink2M: 2_000_000
        case .shrink5M: 5_000_000
        case .shrink10M: 10_000_000
        default: nil
        }
    }
    /// "500KB" · "1MB" …
    var targetName: String {
        guard let b = targetBytes else { return "" }
        return b < 1_000_000 ? "\(b / 1000)KB" : "\(b / 1_000_000)MB"
    }

    var title: String {
        switch self {
        case .toJPEG: "JPEG로"
        case .toPNG: "PNG로"
        case .toHEIC: "HEIC로"
        case .long3840, .long2560, .long1920, .long1280, .long800: "해상도 줄이기(긴 쪽 \(longEdge!)px)"
        case .stripInfo: "위치·촬영 정보 지우기"
        case .removeBackground: "배경 지우기"
        case .extractText: "글자 꺼내기"
        case .pdfMerge: "PDF 합치기"
        case .imagesToPDF: "PDF 하나로"
        case .pdfToPNG: "페이지를 PNG로"
        case .toMP4: "MP4(H.264)로"
        case .toHEVC: "HEVC로"
        case .to720p: "720p로 줄이기"
        case .audioOnly: "소리만 M4A로"
        case .toGIF: "GIF로 (앞 10초)"
        case .toM4A: "M4A로"
        case .toWAV: "WAV로"
        case .toMP3: "MP3로"
        case .docToPDF: "PDF로"
        case .docToDOCX: "Word(DOCX)로"
        case .docToTXT: "텍스트(TXT)로"
        case .docToRTF: "RTF로"
        case .docToHTML: "HTML로"
        case .sheetToCSV: "CSV로 (시트마다)"
        case .zip: "ZIP으로 압축"
        case .unarchive: "압축 풀기"
        case .toTIFF: "TIFF로"
        case .pdfToJPG: "페이지를 JPG로"
        case .pdfToText: "글자만 TXT로"
        case .pdfSplit: "페이지마다 PDF로"
        case .shrink500K, .shrink1M, .shrink2M, .shrink5M, .shrink10M: "\(targetName) 이하로 줄이기"
        case .pdfToDOCX: "Word(DOCX)로 (글자만)"
        case .docToODT: "ODT로"
        case .csvToXLSX: "엑셀(XLSX)로"
        case .sheetToPDF: "PDF로 (단순 표)"
        case .toMOV: "MOV로"
        case .posterFrame: "대표 사진(JPG)"
        case .toAIFF: "AIFF로"
        }
    }

    var symbol: String {
        switch self {
        case .toJPEG, .toPNG, .toHEIC: "photo"
        case .long3840, .long2560, .long1920, .long1280, .long800: "arrow.down.right.and.arrow.up.left"
        case .stripInfo: "location.slash"
        case .removeBackground: "person.crop.rectangle"
        case .extractText: "text.viewfinder"
        case .pdfMerge, .imagesToPDF: "doc.on.doc"
        case .pdfToPNG: "doc.richtext"
        case .toMP4, .toHEVC: "film"
        case .to720p: "rectangle.compress.vertical"
        case .audioOnly, .toM4A, .toWAV: "waveform"
        case .toGIF: "sparkles.rectangle.stack"
        case .toMP3: "waveform"
        case .docToPDF, .docToDOCX, .docToTXT, .docToRTF, .docToHTML: "doc.text"
        case .sheetToCSV: "tablecells"
        case .zip: "archivebox"
        case .unarchive: "shippingbox.and.arrow.backward"
        case .toTIFF: "photo"
        case .pdfToJPG: "doc.richtext"
        case .pdfToText, .pdfToDOCX, .docToODT: "doc.text"
        case .shrink500K, .shrink1M, .shrink2M, .shrink5M, .shrink10M: "arrow.down.circle"
        case .pdfSplit: "doc.on.doc"
        case .csvToXLSX, .sheetToPDF: "tablecells"
        case .toMOV: "film"
        case .posterFrame: "photo.on.rectangle"
        case .toAIFF: "waveform"
        }
    }

    /// F27 원형 변환 칸 이름(짧게)
    var short: String {
        switch self {
        case .toJPEG: "JPEG"
        case .toPNG: "PNG"
        case .toHEIC: "HEIC"
        case .toTIFF: "TIFF"
        case .imagesToPDF: "PDF"
        case .long3840, .long2560, .long1920, .long1280, .long800: "\(longEdge!)px"
        case .shrink500K, .shrink1M, .shrink2M, .shrink5M, .shrink10M: targetName
        case .stripInfo: "위치정보 빼기"
        case .removeBackground: "배경 빼기"
        case .extractText: "글자 꺼내기"
        case .pdfMerge: "합치기"
        case .pdfToPNG: "PNG"
        case .pdfToJPG: "JPG"
        case .pdfToText: "텍스트"
        case .pdfToDOCX, .docToDOCX: "Word"
        case .pdfSplit: "페이지 나누기"
        case .toMP4: "MP4"
        case .toHEVC: "HEVC"
        case .toMOV: "MOV"
        case .to720p: "720p"
        case .audioOnly: "소리만"
        case .toGIF: "GIF"
        case .posterFrame: "대표 사진"
        case .toM4A: "M4A"
        case .toWAV: "WAV"
        case .toMP3: "MP3"
        case .toAIFF: "AIFF"
        case .docToPDF, .sheetToPDF: "PDF"
        case .docToTXT: "TXT"
        case .docToRTF: "RTF"
        case .docToHTML: "HTML"
        case .docToODT: "ODT"
        case .sheetToCSV: "CSV"
        case .csvToXLSX: "XLSX"
        case .zip: "ZIP"
        case .unarchive: "압축 풀기"
        }
    }

    /// 칸 아래 짧은 설명(품질 제한 칸은 꼭 밝힌다)
    var note: String? {
        switch self {
        case .toPNG: "투명 유지"
        case .imagesToPDF: "한 파일로"
        case .stripInfo: "GPS·촬영 정보"
        case .removeBackground: "투명 PNG"
        case .extractText: "TXT로"
        case .pdfToPNG, .pdfToJPG: "쪽마다"
        case .pdfToText: "TXT"
        case .pdfToDOCX: "글자만"
        case .pdfSplit: "쪽마다 PDF"
        case .toMP4: "H.264"
        case .to720p: "줄이기"
        case .audioOnly: "M4A"
        case .toGIF: "앞 10초"
        case .posterFrame: "JPG 1장"
        case .sheetToCSV: "시트마다"
        case .sheetToPDF: "단순 표"
        case .zip: "압축"
        default: nil
        }
    }

    /// 안쪽 고리(무엇으로 = 형식)인지, 바깥 고리(무엇을 = 동작)인지
    var isFormat: Bool {
        switch self {
        case .toJPEG, .toPNG, .toHEIC, .toTIFF, .imagesToPDF, .pdfToPNG, .pdfToJPG, .pdfToText, .pdfToDOCX,
             .toMP4, .toHEVC, .toMOV, .toGIF, .toM4A, .toWAV, .toMP3, .toAIFF,
             .docToPDF, .docToDOCX, .docToTXT, .docToRTF, .docToHTML, .docToODT, .sheetToCSV, .csvToXLSX, .sheetToPDF: true
        default: false
        }
    }

    /// 형식 칸의 결과 확장자(같은 형식이면 칸을 뺀다)
    var outputExt: String? {
        switch self {
        case .toJPEG: "jpeg"
        case .toPNG: "png"
        case .toHEIC: "heic"
        case .toTIFF: "tiff"
        case .toMP4: "mp4"
        case .toMOV: "mov"
        case .toM4A: "m4a"
        case .toWAV: "wav"
        case .toMP3: "mp3"
        case .toAIFF: "aiff"
        case .docToDOCX: "docx"
        case .docToTXT: "txt"
        case .docToRTF: "rtf"
        case .docToHTML: "html"
        case .docToODT: "odt"
        case .csvToXLSX: "xlsx"
        case .sheetToCSV: "csv"
        default: nil
        }
    }

    /// jpg→jpeg, tif→tiff, aif→aiff, htm→html
    static func normalizedExt(_ ext: String) -> String {
        let e = ext.lowercased()
        return ["jpg": "jpeg", "tif": "tiff", "aif": "aiff", "htm": "html"][e] ?? e
    }

    /// 여러 파일을 결과 하나로 합치는 작업
    var combines: Bool { self == .pdfMerge || self == .imagesToPDF || self == .zip }   // imagesToPDF는 1장도 PDF로(F27)

    enum Kind { case image, pdf, video, audio, document, sheet, archive, other }

    static let documentExts: Set<String> = ["docx", "doc", "rtf", "odt", "html", "htm", "txt", "wordml"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "7z", "rar"]

    static func kind(of url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        if documentExts.contains(ext) { return .document }
        if ext == "xlsx" || ext == "csv" { return .sheet }
        if archiveExts.contains(ext) { return .archive }
        guard let t = UTType(filenameExtension: ext) else { return .other }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .movie) { return .video }
        if t.conforms(to: .audio) { return .audio }
        return .other
    }

    /// 놓인 파일들에 공통으로 가능한 변환. 섞여 있으면 교집합.
    /// ZIP 압축은 어떤 파일·폴더든 가능하다(여러 개면 하나로).
    static func options(for urls: [URL]) -> [ConvertOp] {
        specific(urls) + [.zip]
    }

    private static func specific(_ urls: [URL]) -> [ConvertOp] {
        let kinds = Set(urls.map(kind))
        guard kinds.count == 1, let k = kinds.first else { return [] }
        let multi = urls.count > 1
        let mp3: [ConvertOp] = Converter.tool("ffmpeg") != nil ? [.toMP3] : []
        let exts = Set(urls.map { ConvertOp.normalizedExt($0.pathExtension) })
        let ops: [ConvertOp]
        switch k {
        case .image: ops = [.toJPEG, .toPNG, .toHEIC, .toTIFF, .imagesToPDF] + longs + shrinks + [.stripInfo, .removeBackground, .extractText]
        case .pdf: ops = [.pdfToPNG, .pdfToJPG, .pdfToText, .pdfToDOCX] + (multi ? [.pdfMerge] : []) + shrinks + [.pdfSplit]
        case .video: ops = [.toMP4, .toHEVC, .toMOV, .toGIF, .to720p, .audioOnly] + mp3 + [.posterFrame]
        case .audio: ops = [.toM4A, .toWAV] + mp3 + [.toAIFF]
        case .document: ops = [.docToPDF, .docToDOCX, .docToTXT, .docToRTF, .docToHTML, .docToODT]
        case .sheet: ops = exts == ["csv"] ? [.csvToXLSX, .sheetToPDF] : exts == ["xlsx"] ? [.sheetToCSV, .sheetToPDF] : []
        case .archive: return [.unarchive]
        case .other: return []
        }
        // 같은 형식으로 바꾸는 칸은 빼기(모든 종류)
        return ops.filter { op in op.outputExt.map { !(exts.count == 1 && exts.contains($0)) } ?? true }
    }
}

struct ConvertError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum Converter {
    private static let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2   // 동시에 2개, 나머지는 줄 선다
        q.qualityOfService = .userInitiated
        return q
    }()
    private static let nameLock = NSLock()

    /// 변환을 돌리고, 끝나면 메인 스레드에서 결과 파일들과 실패 메시지, 알림("이미 작아요" 등, F33)을 돌려준다.
    static func run(_ op: ConvertOp, _ urls: [URL], done: @escaping ([URL], [String], [String]) -> Void) {
        let batches = op.combines ? [urls] : urls.map { [$0] }
        let group = DispatchGroup()
        let lock = NSLock()
        var outputs: [URL] = [], errors: [String] = [], notes: [String] = []
        for batch in batches {
            group.enter()
            queue.addOperation {
                do {
                    let made = try convert(op, batch) { n in lock.withLock { notes.append("\(batch[0].lastPathComponent): \(n)") } }
                    lock.withLock { outputs += made }
                } catch {
                    lock.withLock { errors.append("\(batch[0].lastPathComponent): \(error.localizedDescription)") }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(outputs, errors, notes) }
    }

    static func convert(_ op: ConvertOp, _ urls: [URL], note: (String) -> Void = { _ in }) throws -> [URL] {
        let src = urls[0]
        switch op {
        case .toJPEG: return [try reencode(src, .jpeg, quality: 0.9)]
        case .toPNG: return [try reencode(src, .png, quality: nil)]
        case .toHEIC: return [try reencode(src, .heic, quality: 0.8)]
        case .long3840, .long2560, .long1920, .long1280, .long800:
            if let px = pixelSize(src), max(px.width, px.height) <= op.longEdge! { note("지금 \(px.width)×\(px.height), 더 줄일 게 없어요"); return [] }
            return [try resized(src, longEdge: op.longEdge!)]
        case .stripInfo:
            let image = try loadImage(src, maxPixel: nil)
            let type = UTType(filenameExtension: src.pathExtension.lowercased()) ?? .png
            let canWrite = (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(type.identifier)
            let outType: UTType = canWrite ? type : .png
            return [try finalize(writeImage(image, outType, quality: 0.95), from: src, ext: outType.preferredFilenameExtension ?? "png")]
        case .removeBackground: return [try removeBackground(src)]
        case .extractText: return [try extractText(src)]
        case .pdfMerge:
            let merged = PDFDocument()
            for url in urls {
                guard let doc = PDFDocument(url: url) else { throw ConvertError("PDF를 열 수 없어요") }
                for i in 0..<doc.pageCount { if let p = doc.page(at: i) { merged.insert(p, at: merged.pageCount) } }
            }
            return [try finalizePDF(merged, from: src, label: "합침")]
        case .imagesToPDF:
            let doc = PDFDocument()
            for url in urls {
                let cg = try loadImage(url, maxPixel: nil)
                guard let page = PDFPage(image: NSImage(cgImage: cg, size: .zero)) else { throw ConvertError("PDF 페이지를 만들 수 없어요") }
                doc.insert(page, at: doc.pageCount)
            }
            return [try finalizePDF(doc, from: src, label: urls.count > 1 ? "합침" : "PDF")]
        case .pdfToPNG:
            guard let doc = PDFDocument(url: src) else { throw ConvertError("PDF를 열 수 없어요") }
            return try (0..<doc.pageCount).map { i in
                let page = doc.page(at: i)!
                let box = page.bounds(for: .mediaBox)
                let img = page.thumbnail(of: CGSize(width: box.width * 2, height: box.height * 2), for: .mediaBox)
                guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ConvertError("페이지를 그릴 수 없어요") }
                return try finalize(writeImage(cg, .png, quality: nil), from: src, ext: "png", label: "p\(i + 1)")
            }
        case .toMP4: return [try export(src, preset: AVAssetExportPresetHighestQuality, type: .mp4, ext: "mp4")]
        case .toHEVC: return [try export(src, preset: AVAssetExportPresetHEVCHighestQuality, type: .mp4, ext: "mp4")]
        case .to720p: return [try export(src, preset: AVAssetExportPreset1280x720, type: .mp4, ext: "mp4")]
        case .audioOnly, .toM4A: return [try export(src, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a")]
        case .toGIF: return [try gif(src)]
        case .toWAV: return [try wav(src)]
        case .toMP3:
            let tmp = tempURL(ext: "mp3")
            try run(tool("ffmpeg")!, ["-v", "error", "-y", "-i", src.path, "-vn", "-codec:a", "libmp3lame", "-q:a", "2", tmp.path])
            return [try finalize(tmp, from: src, ext: "mp3")]
        case .docToPDF: return [try documentPDF(src)]
        case .docToDOCX: return [try textutil(src, "docx")]
        case .docToTXT: return [try textutil(src, "txt")]
        case .docToRTF: return [try textutil(src, "rtf")]
        case .docToHTML: return [try textutil(src, "html")]
        case .sheetToCSV: return try XLSX.toCSV(src)
        case .zip: return [try zip(urls)]
        case .toTIFF: return [try reencode(src, .tiff, quality: nil)]
        case .pdfToJPG:
            guard let doc = PDFDocument(url: src) else { throw ConvertError("PDF를 열 수 없어요") }
            return try (0..<doc.pageCount).map { i in
                let page = doc.page(at: i)!
                let box = page.bounds(for: .mediaBox)
                let img = page.thumbnail(of: CGSize(width: box.width * 2, height: box.height * 2), for: .mediaBox)
                guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ConvertError("페이지를 그릴 수 없어요") }
                return try finalize(writeImage(cg, .jpeg, quality: 0.9), from: src, ext: "jpg", label: "p\(i + 1)")
            }
        case .pdfToText:
            guard let doc = PDFDocument(url: src) else { throw ConvertError("PDF를 열 수 없어요") }
            guard let text = doc.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConvertError("글자가 없는 PDF예요(스캔본이면 사진으로 바꾼 뒤 '글자 꺼내기')") }
            let tmp = tempURL(ext: "txt")
            try text.write(to: tmp, atomically: true, encoding: .utf8)
            return [try finalize(tmp, from: src, ext: "txt")]
        case .pdfToDOCX:
            guard let doc = PDFDocument(url: src) else { throw ConvertError("PDF를 열 수 없어요") }
            let all = NSMutableAttributedString()
            for i in 0..<doc.pageCount {
                if let a = doc.page(at: i)?.attributedString { all.append(a); all.append(NSAttributedString(string: "\n\n")) }
            }
            guard !all.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConvertError("글자가 없는 PDF예요") }
            let data = try all.data(from: NSRange(location: 0, length: all.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            let tmp = tempURL(ext: "docx")
            try data.write(to: tmp)
            return [try finalize(tmp, from: src, ext: "docx")]
        case .shrink500K, .shrink1M, .shrink2M, .shrink5M, .shrink10M:
            return ConvertOp.kind(of: src) == .pdf ? try shrinkPDF(src, op, note: note) : try shrinkImage(src, op, note: note)
        case .pdfSplit:
            guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { throw ConvertError("PDF를 열 수 없어요") }
            return try (0..<doc.pageCount).map { i in
                let one = PDFDocument()
                if let p = doc.page(at: i)?.copy() as? PDFPage { one.insert(p, at: 0) }
                return try finalizePDF(one, from: src, label: "p\(i + 1)")
            }
        case .docToODT: return [try textutil(src, "odt")]
        case .csvToXLSX: return [try XLSX.write(rows: XLSX.parseCSV(String(decoding: Data(contentsOf: src), as: UTF8.self)), from: src)]
        case .sheetToPDF:
            let rows = src.pathExtension.lowercased() == "csv"
                ? XLSX.parseCSV(String(decoding: try Data(contentsOf: src), as: UTF8.self))
                : try XLSX.sheets(src).first?.rows ?? []
            guard !rows.isEmpty else { throw ConvertError("표가 비어 있어요") }
            return [try finalize(TablePDF.render(rows), from: src, ext: "pdf")]
        case .toMOV: return [try export(src, preset: AVAssetExportPresetHighestQuality, type: .mov, ext: "mov")]
        case .posterFrame:
            let asset = AVURLAsset(url: src)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            let mid = CMTime(seconds: max(0, CMTimeGetSeconds(asset.duration) / 2), preferredTimescale: 600)
            guard let cg = try? gen.copyCGImage(at: mid, actualTime: nil) else { throw ConvertError("장면을 꺼내지 못했어요") }
            return [try finalize(writeImage(cg, .jpeg, quality: 0.9), from: src, ext: "jpg", label: "대표 사진")]
        case .toAIFF: return [try pcm(src, ext: "aiff", bigEndian: true)]
        case .unarchive:
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tasky-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            do { try run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", src.path, "-C", dir.path]) }
            catch { try? FileManager.default.removeItem(at: dir); throw ConvertError("압축을 풀지 못했어요") }
            return [try finalize(dir, from: src, ext: "")]
        }
    }

    // MARK: F33 목표 용량으로 줄이기

    private static func fileSize(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    static func sizeText(_ n: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }

    /// JPEG 품질을 낮추고(30%까지), 그래도 크면 긴 변을 0.8배씩(800px까지) 줄여 목표 아래로. 투명은 흰 배경.
    private static func shrinkImage(_ src: URL, _ op: ConvertOp, note: (String) -> Void) throws -> [URL] {
        let target = op.targetBytes!
        if fileSize(src) <= target { note("이미 \(op.targetName) 이하예요"); return [] }
        let image = try loadImage(src, maxPixel: nil)
        let long = max(image.width, image.height)
        func flat(_ edge: Int) -> CGImage? {
            let k = Double(edge) / Double(long)
            let w = max(1, Int(Double(image.width) * k)), h = max(1, Int(Double(image.height) * k))
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ctx.makeImage()
        }
        func jpeg(_ img: CGImage, _ q: Double) -> Data? {
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
            return CGImageDestinationFinalize(dest) ? data as Data : nil
        }
        var smallest: Data?
        var edge = long, found: Data?
        while found == nil {
            if let img = flat(edge), let low = jpeg(img, 0.3) {
                if low.count < smallest?.count ?? .max { smallest = low }
                if low.count <= target {
                    // 목표 아래에서 가장 높은 품질(0.3~0.9 이분 탐색 5번)
                    var lo = 0.3, hi = 0.9, best = low
                    for _ in 0..<5 {
                        let mid = (lo + hi) / 2
                        if let d = jpeg(img, mid), d.count <= target { best = d; lo = mid } else { hi = mid }
                    }
                    found = best
                }
            }
            let next = Int(Double(edge) * 0.8)
            if found != nil || edge <= min(long, 800) { break }
            edge = max(next, min(long, 800))
        }
        guard let data = found ?? smallest else { throw ConvertError("이미지를 저장하지 못했어요") }
        if data.count >= fileSize(src) { note("더 줄이지 못했어요 (\(sizeText(fileSize(src))))"); return [] }
        if found == nil { note("목표에 못 맞췄어요 (\(sizeText(data.count)))") }
        let tmp = tempURL(ext: "jpg")
        try data.write(to: tmp)
        return [try finalize(tmp, from: src, ext: "jpg", label: "\(op.targetName) 이하")]
    }

    /// 안의 이미지를 다시 압축(QuartzFilter, 글자·벡터 유지) → 그래도 크면 쪽을 그림으로 바꿔 목표 아래로.
    private static func shrinkPDF(_ src: URL, _ op: ConvertOp, note: (String) -> Void) throws -> [URL] {
        let target = op.targetBytes!
        if fileSize(src) <= target { note("이미 \(op.targetName) 이하예요"); return [] }
        guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { throw ConvertError("PDF를 열 수 없어요") }
        var smallest: (url: URL, size: Int, raster: Bool)?
        var tried: [URL] = []
        defer { for u in tried where u != smallest?.url { try? FileManager.default.removeItem(at: u) } }
        func keep(_ url: URL, raster: Bool) -> Bool {
            guard PDFDocument(url: url)?.pageCount == doc.pageCount else { return false }
            let n = fileSize(url)
            if n < smallest?.size ?? .max { smallest = (url, n, raster) }
            return n <= target
        }
        var done = false
        for (q, dpi) in [(0.75, 150.0), (0.5, 150.0), (0.5, 100.0), (0.3, 72.0)] where !done {
            let filter = QuartzFilter(properties: [
                "Domains": ["Applications": true, "Printing": true], "FilterType": 1, "Name": "Tasky",
                "FilterData": ["ColorSettings": ["ImageSettings": [
                    "Compression Quality": q, "ImageCompression": "ImageJPEGCompress",
                    "ImageScaleSettings": ["ImageResolution": dpi, "ImageScaleFactor": 0.0, "ImageScaleInterpolate": 3, "ImageSizeMax": 0, "ImageSizeMin": 0]]]]])
            let tmp = tempURL(ext: "pdf")
            tried.append(tmp)
            guard let filter, PDFDocument(url: src)?.write(to: tmp, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) == true else { continue }
            done = keep(tmp, raster: false)
        }
        // 긴 변 픽셀 상한도 둔다: 'PDF 하나로'로 만든 PDF는 쪽 크기가 사진 픽셀 크기라 dpi만으로는 줄지 않는다
        for (dpi, q, cap) in [(150.0, 0.6, 2000.0), (110.0, 0.5, 1500.0), (80.0, 0.4, 1100.0), (60.0, 0.3, 800.0)] where !done {
            let out = PDFDocument()
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                var box = page.bounds(for: .mediaBox)
                if page.rotation % 180 != 0 { box.size = CGSize(width: box.height, height: box.width) }   // thumbnail은 회전을 적용해 그린다
                let k = min(dpi / 72, cap / max(box.width, box.height))
                let img = page.thumbnail(of: CGSize(width: box.width * k, height: box.height * k), for: .mediaBox)
                guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let data = NSMutableData()
                guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
                guard CGImageDestinationFinalize(dest), let jpg = NSImage(data: data as Data) else { continue }
                jpg.size = box.size
                if let p = PDFPage(image: jpg) { out.insert(p, at: out.pageCount) }
            }
            let tmp = tempURL(ext: "pdf")
            tried.append(tmp)
            guard out.write(to: tmp) else { continue }
            done = keep(tmp, raster: true)
        }
        guard let best = smallest else { throw ConvertError("PDF를 저장하지 못했어요") }
        if best.size >= fileSize(src) { note("더 줄이지 못했어요 (\(sizeText(fileSize(src))))"); smallest = nil; return [] }
        if best.raster { note("글자를 선택·검색할 수 없게 됐어요") }
        if !done { note("목표에 못 맞췄어요 (\(sizeText(best.size)))") }
        return [try finalize(best.url, from: src, ext: "pdf", label: "\(op.targetName) 이하")]
    }

    // MARK: 이미지

    /// 방향(EXIF 회전)을 적용한 가로·세로 픽셀
    static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let turned = (5...8).contains(props[kCGImagePropertyOrientation] as? Int ?? 1)
        return turned ? (h, w) : (w, h)
    }

    /// 긴 쪽을 `longEdge`로 맞춘 크기(반올림). 이미 작으면 nil
    static func reduced(_ size: (width: Int, height: Int), longEdge: Int) -> (width: Int, height: Int)? {
        let long = max(size.width, size.height)
        guard long > longEdge else { return nil }
        let k = Double(longEdge) / Double(long)
        return (max(1, Int((Double(size.width) * k).rounded())), max(1, Int((Double(size.height) * k).rounded())))
    }

    /// 방향(EXIF 회전)을 적용한 이미지. 메타데이터는 따라오지 않는다.
    static func loadImage(_ url: URL, maxPixel: Int?) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ConvertError("이미지를 열 수 없어요")
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? Int.max, max(w, h)),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            throw ConvertError("이미지를 읽을 수 없어요")
        }
        return img
    }

    /// 형식만 바꾼다. 촬영 정보 등 메타데이터는 유지한다.
    private static func reencode(_ src: URL, _ type: UTType, quality: Double?) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else { throw ConvertError("이미지를 열 수 없어요") }
        let tmp = tempURL(ext: type.preferredFilenameExtension ?? "img")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError("이 Mac에서 \(type.preferredFilenameExtension?.uppercased() ?? "이 형식")로 저장할 수 없어요")
        }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError("저장하지 못했어요") }
        return try finalize(tmp, from: src, ext: type.preferredFilenameExtension ?? "img")
    }

    private static func resized(_ src: URL, longEdge: Int) throws -> URL {
        let img = try loadImage(src, maxPixel: longEdge)
        let type = UTType(filenameExtension: src.pathExtension.lowercased())
        let outType: UTType = type == .png ? .png : .jpeg
        return try finalize(writeImage(img, outType, quality: 0.9), from: src, ext: outType.preferredFilenameExtension!, label: "\(longEdge)px")
    }

    static func writeImage(_ img: CGImage, _ type: UTType, quality: Double?) throws -> URL {
        let tmp = tempURL(ext: type.preferredFilenameExtension ?? "img")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError("이 형식으로 저장할 수 없어요")
        }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError("저장하지 못했어요") }
        return tmp
    }

    private static func removeBackground(_ src: URL) throws -> URL {
        let img = try loadImage(src, maxPixel: nil)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: img)
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else {
            throw ConvertError("사람이나 사물을 찾지 못했어요")
        }
        let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else { throw ConvertError("결과를 만들지 못했어요") }
        return try finalize(writeImage(cg, .png, quality: nil), from: src, ext: "png", label: "배경 없음")
    }

    private static func extractText(_ src: URL) throws -> URL {
        let img = try loadImage(src, maxPixel: nil)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        try VNImageRequestHandler(cgImage: img).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.isEmpty else { throw ConvertError("글자를 찾지 못했어요") }
        let tmp = tempURL(ext: "txt")
        try text.write(to: tmp, atomically: true, encoding: .utf8)
        return try finalize(tmp, from: src, ext: "txt", label: "글자")
    }

    // MARK: PDF·영상·오디오

    private static func finalizePDF(_ doc: PDFDocument, from src: URL, label: String) throws -> URL {
        let tmp = tempURL(ext: "pdf")
        guard doc.write(to: tmp) else { throw ConvertError("PDF를 저장하지 못했어요") }
        return try finalize(tmp, from: src, ext: "pdf", label: label)
    }

    private static func export(_ src: URL, preset: String, type: AVFileType, ext: String) throws -> URL {
        let asset = AVURLAsset(url: src)
        if type == .m4a, asset.tracks(withMediaType: .audio).isEmpty { throw ConvertError("이 파일에는 소리가 없어요") }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConvertError("이 파일은 이 방식으로 바꿀 수 없어요")
        }
        let tmp = tempURL(ext: ext)
        session.outputURL = tmp
        session.outputFileType = type
        let done = DispatchSemaphore(value: 0)
        session.exportAsynchronously { done.signal() }
        done.wait()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: tmp)
            throw ConvertError(session.error?.localizedDescription ?? "내보내기에 실패했어요")
        }
        return try finalize(tmp, from: src, ext: ext)
    }

    private static func gif(_ src: URL) throws -> URL {
        let asset = AVURLAsset(url: src)
        let duration = min(CMTimeGetSeconds(asset.duration), 10)
        guard duration > 0 else { throw ConvertError("영상 길이를 알 수 없어요") }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let fps = 10.0
        let count = max(1, Int(duration * fps))
        let tmp = tempURL(ext: "gif")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw ConvertError("GIF를 만들 수 없어요")
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for i in 0..<count {
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            guard let frame = try? gen.copyCGImage(at: t, actualTime: nil) else { continue }
            CGImageDestinationAddImage(dest, frame, frameProps)
        }
        guard CGImageDestinationFinalize(dest) else { throw ConvertError("GIF를 저장하지 못했어요") }
        return try finalize(tmp, from: src, ext: "gif")
    }

    private static func wav(_ src: URL) throws -> URL { try pcm(src, ext: "wav", bigEndian: false) }

    /// 무압축 PCM(WAV는 리틀 엔디언, AIFF는 빅 엔디언). 파일 종류는 확장자로 정해진다
    private static func pcm(_ src: URL, ext: String, bigEndian: Bool) throws -> URL {
        let input = try AVAudioFile(forReading: src)
        let format = input.processingFormat
        let tmp = tempURL(ext: ext)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: bigEndian,
        ]
        do {
            let output = try AVAudioFile(forWriting: tmp, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768)!
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
        }
        return try finalize(tmp, from: src, ext: ext)
    }

    // MARK: 문서·압축·외부 도구

    /// macOS 기본 `textutil`로 문서 형식을 바꾼다 (docx·doc·rtf·odt·html·txt).
    private static func textutil(_ src: URL, _ format: String) throws -> URL {
        let tmp = tempURL(ext: format)
        try run(URL(fileURLWithPath: "/usr/bin/textutil"), ["-convert", format, "-output", tmp.path, src.path])
        return try finalize(tmp, from: src, ext: format)
    }

    /// 문서를 A4 PDF로. 텍스트 뷰를 PDF로 '인쇄'한다(AppKit이라 메인 스레드에서).
    private static func documentPDF(_ src: URL) throws -> URL {
        let tmp = tempURL(ext: "pdf")
        var failure: Error?
        let work = {
            do {
                let text = try NSAttributedString(url: src, options: [:], documentAttributes: nil)
                let info = NSPrintInfo()
                info.paperSize = CGSize(width: 595, height: 842)
                (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = (56, 56, 56, 56)
                info.jobDisposition = .save
                info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tmp
                let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 595 - 112, height: 842 - 112))
                view.textStorage?.setAttributedString(text)
                let op = NSPrintOperation(view: view, printInfo: info)
                op.showsPrintPanel = false
                op.showsProgressPanel = false
                if !op.run() { failure = ConvertError("PDF를 만들지 못했어요") }
            } catch { failure = ConvertError("문서를 열 수 없어요") }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        if let failure { throw failure }
        return try finalize(tmp, from: src, ext: "pdf")
    }

    /// 파일·폴더를 ZIP 하나로. 여러 개면 임시 폴더에 모아 압축한다.
    private static func zip(_ urls: [URL]) throws -> URL {
        let fm = FileManager.default
        let out = tempURL(ext: "zip")
        if urls.count == 1 {
            try run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, out.path])
        } else {
            let stage = fm.temporaryDirectory.appendingPathComponent("tasky-\(UUID().uuidString)")
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stage) }
            for u in urls { try fm.copyItem(at: u, to: stage.appendingPathComponent(u.lastPathComponent)) }
            try run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--sequesterRsrc", stage.path, out.path])
        }
        return try finalize(out, from: urls[0], ext: "zip", label: urls.count > 1 ? "외 \(urls.count - 1)개" : nil)
    }

    /// 사용자가 설치한 명령줄 도구(Homebrew 등). 없으면 nil.
    static func tool(_ name: String) -> URL? {
        ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(fileURLWithPath: "\($0)/\(name)") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func run(_ exe: URL, _ args: [String]) throws {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .split(separator: "\n").last.map(String.init)
            throw ConvertError(msg ?? "변환에 실패했어요")
        }
    }

    // MARK: 파일 이름

    static func tempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tasky-\(UUID().uuidString).\(ext)")
    }

    /// 임시 결과를 원본 옆 `이름 라벨.확장자`로 옮긴다. 원본·기존 파일과 겹치면 `이름 라벨 2`(원본은 덮어쓰지 않음).
    /// 원본 폴더에 쓸 수 없으면 다운로드 폴더로.
    static func finalize(_ tmp: URL, from src: URL, ext: String, label: String? = nil) throws -> URL {
        let fm = FileManager.default
        var dir = src.deletingLastPathComponent()
        if !fm.isWritableFile(atPath: dir.path) {
            dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        let base = src.deletingPathExtension().lastPathComponent + (label.map { " \($0)" } ?? "")
        nameLock.lock(); defer { nameLock.unlock() }
        for n in 1...999 {
            let name = n == 1 ? base : "\(base) \(n)"
            let target = dir.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
            if fm.fileExists(atPath: target.path) { continue }
            do {
                try fm.moveItem(at: tmp, to: target)
                return target
            } catch {
                try? fm.removeItem(at: tmp)
                throw ConvertError("결과 파일을 저장하지 못했어요")
            }
        }
        try? fm.removeItem(at: tmp)
        throw ConvertError("같은 이름의 결과가 너무 많아요")
    }
}

/// xlsx → 시트마다 CSV. 외부 라이브러리 없이 압축을 풀어 XML을 읽는다.
/// shortcut: 날짜·수식은 저장된 값(숫자) 그대로 내보낸다, 서식이 필요해지면 numFmt 해석을 더한다.
enum XLSX {
    /// 시트마다 (이름, 줄). 엑셀 파일은 zip이라 임시 폴더에 풀어 XML만 읽는다
    static func sheets(_ src: URL) throws -> [(name: String, rows: [[String]])] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("tasky-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", src.path, dir.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ConvertError("엑셀 파일을 열 수 없어요") }

        let shared = XMLItems(url: dir.appendingPathComponent("xl/sharedStrings.xml")).sharedStrings()
        let rels = Dictionary(XMLItems(url: dir.appendingPathComponent("xl/_rels/workbook.xml.rels"))
            .elements("Relationship").compactMap { a in a["Id"].flatMap { id in a["Target"].map { (id, $0) } } }) { a, _ in a }
        let sheets = XMLItems(url: dir.appendingPathComponent("xl/workbook.xml")).elements("sheet")
        guard !sheets.isEmpty else { throw ConvertError("시트를 찾지 못했어요") }
        return sheets.compactMap { sheet in
            guard let rid = sheet["r:id"], var target = rels[rid] else { return nil }
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            return (sheet["name"] ?? "시트", XMLItems(url: dir.appendingPathComponent(target)).cells(shared: shared))
        }
    }

    static func toCSV(_ src: URL) throws -> [URL] {
        let all = try sheets(src)
        return try all.map { sheet in
            let csv = sheet.rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n")
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tasky-\(UUID().uuidString).csv")
            // 엑셀에서 한글이 깨지지 않도록 BOM을 붙인다
            try (Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)).write(to: tmp)
            return try Converter.finalize(tmp, from: src, ext: "csv", label: all.count > 1 ? sheet.name : nil)
        }
    }

    /// RFC 4180 CSV 읽기(따옴표 안의 쉼표·줄바꿈·"" 처리, 앞 BOM 무시)
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" { if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false } }
                else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        return rows
    }

    /// 가장 작은 엑셀 파일 한 장(숫자는 숫자로, 나머지는 글자). 직접 XML을 쓰고 ditto로 묶는다
    static func write(rows: [[String]], from src: URL) throws -> URL {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("tasky-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        func put(_ path: String, _ xml: String) throws {
            let url = stage.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: url)
        }
        let head = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        try put("[Content_Types].xml", head + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>"#)
        try put("_rels/.rels", head + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#)
        try put("xl/workbook.xml", head + #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>"#)
        try put("xl/_rels/workbook.xml.rels", head + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#)
        try put("xl/worksheets/sheet1.xml", head + #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"# + sheetXML(rows) + "</sheetData></worksheet>")
        let out = Converter.tempURL(ext: "xlsx")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--norsrc", stage.path, out.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw ConvertError("엑셀 파일을 만들지 못했어요") }
        return try Converter.finalize(out, from: src, ext: "xlsx")
    }

    /// 시트 XML의 줄들(자체 검사 대상)
    static func sheetXML(_ rows: [[String]]) -> String {
        func letters(_ n: Int) -> String { n < 26 ? String(UnicodeScalar(65 + n)!) : letters(n / 26 - 1) + letters(n % 26) }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        return rows.enumerated().map { r, row in
            "<row r=\"\(r + 1)\">" + row.enumerated().map { c, v in
                let ref = letters(c) + "\(r + 1)"
                if !v.isEmpty, Double(v) != nil, !v.hasPrefix("0") || v == "0" || v.hasPrefix("0.") { return "<c r=\"\(ref)\"><v>\(v)</v></c>" }
                return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(v))</t></is></c>"
            }.joined() + "</row>"
        }.joined()
    }

    static func quote(_ s: String) -> String {
        s.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// "B12" → 1 (0부터)
    static func column(_ ref: String) -> Int {
        ref.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }
}

/// F27 표 → PDF(단순 표): A4 가로, 칸 너비는 글자 수로, 넘치면 다음 쪽. 글자·선만 그린다
enum TablePDF {
    static func render(_ rows: [[String]]) throws -> URL {
        let url = Converter.tempURL(ext: "pdf")
        var box = CGRect(x: 0, y: 0, width: 842, height: 595)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil as CFDictionary?) else { throw ConvertError("PDF를 만들지 못했어요") }
        let font = NSFont.systemFont(ofSize: 9), bold = NSFont.boldSystemFont(ofSize: 9)
        let cols = rows.map(\.count).max() ?? 0
        let margin: CGFloat = 36, rowH: CGFloat = 16
        var widths = (0..<cols).map { c in min(200, max(36, rows.prefix(200).map { c < $0.count ? ($0[c] as NSString).size(withAttributes: [.font: font]).width + 10 : 0 }.max() ?? 0)) }
        let total = widths.reduce(0, +), avail = box.width - margin * 2
        if total > avail { widths = widths.map { $0 * avail / total } }
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let prev = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.current = prev }
        var y: CGFloat = 0
        for (r, row) in rows.enumerated() {
            if r == 0 || y - rowH < margin {
                if r > 0 { ctx.endPDFPage() }
                ctx.beginPDFPage(nil)
                y = box.height - margin
            }
            var x = margin
            for (c, w) in widths.enumerated() {
                let text = c < row.count ? row[c] : ""
                (text as NSString).draw(in: CGRect(x: x + 4, y: y - rowH + 3, width: w - 8, height: rowH - 4),
                                        withAttributes: [.font: r == 0 ? bold : font, .paragraphStyle: para, .foregroundColor: NSColor.black])
                x += w
            }
            ctx.setStrokeColor(gray: 0.8, alpha: 1); ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: y - rowH)); ctx.addLine(to: CGPoint(x: x, y: y - rowH)); ctx.strokePath()
            y -= rowH
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }
}

/// XMLParser로 필요한 것만 읽는 작은 도우미
final class XMLItems: NSObject, XMLParserDelegate {
    private let data: Data?
    private var handler: ((String, [String: String]) -> Void)?
    private var endHandler: ((String) -> Void)?
    private var textHandler: ((String) -> Void)?

    init(url: URL) { data = try? Data(contentsOf: url) }

    private func parse() {
        guard let data else { return }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        handler?(e, attributes)
    }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) { endHandler?(e) }
    func parser(_ p: XMLParser, foundCharacters s: String) { textHandler?(s) }

    func elements(_ name: String) -> [[String: String]] {
        var out: [[String: String]] = []
        handler = { e, a in if e == name { out.append(a) } }
        parse()
        return out
    }

    /// sharedStrings.xml: <si>마다 안의 <t> 글자를 이어 붙인다
    func sharedStrings() -> [String] {
        var out: [String] = [], current = "", inT = false
        handler = { e, _ in if e == "si" { current = "" } else if e == "t" { inT = true } }
        endHandler = { e in if e == "t" { inT = false } else if e == "si" { out.append(current) } }
        textHandler = { if inT { current += $0 } }
        parse()
        return out
    }

    /// 시트 XML → 행·열 표
    func cells(shared: [String]) -> [[String]] {
        var rows: [Int: [Int: String]] = [:]
        var row = 0, col = 0, type = "", value = "", inValue = false
        handler = { e, a in
            switch e {
            case "row": row = (Int(a["r"] ?? "") ?? (row + 1))
            case "c": col = XLSX.column(a["r"] ?? "A"); type = a["t"] ?? ""; value = ""
            case "v", "t": inValue = true
            default: break
            }
        }
        endHandler = { e in
            if e == "v" || e == "t" { inValue = false }
            if e == "c" {
                let text = type == "s" ? (Int(value).flatMap { $0 < shared.count ? shared[$0] : nil } ?? "")
                    : type == "b" ? (value == "1" ? "TRUE" : "FALSE") : value
                rows[row, default: [:]][col] = text
            }
        }
        textHandler = { if inValue { value += $0 } }
        parse()
        guard let maxRow = rows.keys.max() else { return [] }
        let maxCol = rows.values.flatMap(\.keys).max() ?? 0
        return (1...maxRow).map { r in (0...maxCol).map { rows[r]?[$0] ?? "" } }
    }
}
