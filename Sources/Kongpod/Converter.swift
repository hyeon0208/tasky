import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// 드롭 변환. macOS 기본 프레임워크만 쓴다. 원본은 읽기만 하고, 결과는 임시 파일로 만든 뒤 옮겨서
/// 실패해도 반쯤 만든 파일이 남지 않는다.
enum ConvertOp: String, CaseIterable {
    case toJPEG, toPNG, toHEIC, long1920, long1280, shrink, stripInfo, removeBackground, extractText
    case pdfMerge, imagesToPDF, pdfToPNG
    case toMP4, toHEVC, to720p, audioOnly, toGIF
    case toM4A, toWAV, toMP3
    case docToPDF, docToDOCX, docToTXT, docToRTF, docToHTML
    case sheetToCSV
    case zip, unarchive

    var title: String {
        switch self {
        case .toJPEG: "JPEG로"
        case .toPNG: "PNG로"
        case .toHEIC: "HEIC로"
        case .long1920: "긴 변 1920"
        case .long1280: "긴 변 1280"
        case .shrink: "용량 줄이기"
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
        }
    }

    var symbol: String {
        switch self {
        case .toJPEG, .toPNG, .toHEIC: "photo"
        case .long1920, .long1280: "arrow.down.right.and.arrow.up.left"
        case .shrink: "arrow.down.circle"
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
        }
    }

    /// 여러 파일을 결과 하나로 합치는 작업
    var combines: Bool { self == .pdfMerge || self == .imagesToPDF || self == .zip }

    enum Kind { case image, pdf, video, audio, document, sheet, archive, other }

    static let documentExts: Set<String> = ["docx", "doc", "rtf", "odt", "html", "htm", "txt", "wordml"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "7z", "rar"]

    static func kind(of url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        if documentExts.contains(ext) { return .document }
        if ext == "xlsx" { return .sheet }
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
        switch k {
        case .image: return [.toJPEG, .toPNG, .toHEIC, .long1920, .long1280, .shrink, .stripInfo, .removeBackground, .extractText]
                            + (multi ? [.imagesToPDF] : [])
        case .pdf: return [.pdfToPNG] + (multi ? [.pdfMerge] : [])
        case .video: return [.toMP4, .toHEVC, .to720p, .audioOnly, .toGIF] + mp3
        case .audio: return [.toM4A, .toWAV] + mp3
        case .document:
            let ext = Set(urls.map { $0.pathExtension.lowercased() })
            return [.docToPDF, .docToDOCX, .docToTXT, .docToRTF, .docToHTML].filter { op in
                // 같은 형식으로 바꾸는 칸은 빼기
                !(ext == ["docx"] && op == .docToDOCX) && !(ext == ["txt"] && op == .docToTXT)
                    && !(ext == ["rtf"] && op == .docToRTF) && !(ext.isSubset(of: ["html", "htm"]) && op == .docToHTML)
            }
        case .sheet: return [.sheetToCSV]
        case .archive: return [.unarchive]
        case .other: return []
        }
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

    /// 변환을 돌리고, 끝나면 메인 스레드에서 결과 파일들과 실패 메시지를 돌려준다.
    static func run(_ op: ConvertOp, _ urls: [URL], done: @escaping ([URL], [String]) -> Void) {
        let batches = op.combines ? [urls] : urls.map { [$0] }
        let group = DispatchGroup()
        let lock = NSLock()
        var outputs: [URL] = [], errors: [String] = []
        for batch in batches {
            group.enter()
            queue.addOperation {
                do {
                    let made = try convert(op, batch)
                    lock.withLock { outputs += made }
                } catch {
                    lock.withLock { errors.append("\(batch[0].lastPathComponent): \(error.localizedDescription)") }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(outputs, errors) }
    }

    static func convert(_ op: ConvertOp, _ urls: [URL]) throws -> [URL] {
        let src = urls[0]
        switch op {
        case .toJPEG: return [try reencode(src, .jpeg, quality: 0.9)]
        case .toPNG: return [try reencode(src, .png, quality: nil)]
        case .toHEIC: return [try reencode(src, .heic, quality: 0.8)]
        case .long1920: return [try resized(src, longEdge: 1920)]
        case .long1280: return [try resized(src, longEdge: 1280)]
        case .shrink: return [try reencode(src, .jpeg, quality: 0.6)]
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
            return [try finalizePDF(doc, from: src, label: "합침")]
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
        case .unarchive:
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kongpod-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            do { try run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", src.path, "-C", dir.path]) }
            catch { try? FileManager.default.removeItem(at: dir); throw ConvertError("압축을 풀지 못했어요") }
            return [try finalize(dir, from: src, ext: "")]
        }
    }

    // MARK: 이미지

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
        return try finalize(writeImage(img, outType, quality: 0.9), from: src, ext: outType.preferredFilenameExtension!)
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

    private static func wav(_ src: URL) throws -> URL {
        let input = try AVAudioFile(forReading: src)
        let format = input.processingFormat
        let tmp = tempURL(ext: "wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
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
        return try finalize(tmp, from: src, ext: "wav")
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
            let stage = fm.temporaryDirectory.appendingPathComponent("kongpod-\(UUID().uuidString)")
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

    private static func tempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kongpod-\(UUID().uuidString).\(ext)")
    }

    /// 임시 결과를 원본 옆 `이름 (깍지).확장자`로 옮긴다. 겹치면 `(깍지 2)`.
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
            let name = "\(base) (깍지\(n == 1 ? "" : " \(n)"))"
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
    static func toCSV(_ src: URL) throws -> [URL] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("kongpod-\(UUID().uuidString)")
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

        var outputs: [URL] = []
        for sheet in sheets {
            guard let rid = sheet["r:id"], var target = rels[rid] else { continue }
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            let rows = XMLItems(url: dir.appendingPathComponent(target)).cells(shared: shared)
            let csv = rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n")
            let tmp = fm.temporaryDirectory.appendingPathComponent("kongpod-\(UUID().uuidString).csv")
            // 엑셀에서 한글이 깨지지 않도록 BOM을 붙인다
            try (Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)).write(to: tmp)
            let label = sheets.count > 1 ? (sheet["name"] ?? "시트") : nil
            outputs.append(try Converter.finalize(tmp, from: src, ext: "csv", label: label))
        }
        return outputs
    }

    static func quote(_ s: String) -> String {
        s.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// "B12" → 1 (0부터)
    static func column(_ ref: String) -> Int {
        ref.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
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
