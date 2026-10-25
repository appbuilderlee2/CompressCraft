import Foundation

final class CompressionEngine {
    private let lock = NSLock()
    private var active: Process?
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func reset() { lock.lock(); stopped = false; lock.unlock() }
    func cancel() { lock.lock(); stopped = true; let p = active; lock.unlock(); p?.terminate() }
    static func find(_ name: String) -> String? {
        let executable = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/bin").path
        let bundled = executable ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin").path
        for dir in [bundled, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let p = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
    static func sevenZip() -> String? {
        for n in ["7zz", "7z", "7za"] { if let p = find(n) { return p } }
        return nil
    }
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(v) = self { return v }; return nil }
    }
    private func run(_ command: String, _ arguments: [String], directory: URL? = nil, callback: ((String) -> Void)? = nil) throws -> String {
        if cancelled { throw Failure.message("已取消") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command)
        p.arguments = arguments
        p.currentDirectoryURL = directory
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        lock.lock(); active = p; lock.unlock()
        defer { lock.lock(); active = nil; lock.unlock() }
        try p.run()
        var log = ""
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            let chunk = String(decoding: data, as: UTF8.self)
            callback?(chunk)
            if log.count < 15000 { log += chunk }
        }
        p.waitUntilExit()
        if cancelled { throw Failure.message("已取消") }
        if p.terminationStatus != 0 { throw Failure.message("執行失敗（\(p.terminationStatus)）：\(log.suffix(500))") }
        return log
    }
    func perform(url: URL, mode: JobMode, codec: String, speed: String, targetMB: Int, progress: @escaping (Double) -> Void) throws -> URL {
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) else { throw Failure.message("找不到檔案") }
        let videoTypes = Set(["mp4","mkv","mov","m4v","avi","webm","ts"])
        let video = !dir.boolValue && (mode == .video || (mode == .automatic && videoTypes.contains(url.pathExtension.lowercased())))
        return video ? try transcode(url, codec: codec, speed: speed, targetMB: targetMB, progress: progress) : try archive(url, targetMB: targetMB, progress: progress)
    }
    private func unique(_ input: URL, suffix: String, ext: String) -> URL {
        let folder = input.deletingLastPathComponent(), base = input.deletingPathExtension().lastPathComponent + suffix
        var out = folder.appendingPathComponent(base).appendingPathExtension(ext), i = 2
        while FileManager.default.fileExists(atPath: out.path) || FileManager.default.fileExists(atPath: out.path + ".001") {
            out = folder.appendingPathComponent(base + "-\(i)").appendingPathExtension(ext); i += 1
        }
        return out
    }
    private func transcode(_ url: URL, codec: String, targetMB: Int, progress: @escaping (Double) -> Void) throws -> URL {
        guard let ffmpeg = Self.find("ffmpeg"), let ffprobe = Self.find("ffprobe") else { throw Failure.message("請先安裝 FFmpeg（包含 ffprobe）") }
        let info = try run(ffprobe, ["-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",url.path])
        guard let seconds = Double(info.trimmingCharacters(in: .whitespacesAndNewlines)), seconds > 0 else { throw Failure.message("影片時長無效") }
        let budget = Int64(targetMB) * 1_000_000
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
        if bytes > 0 && bytes <= budget { progress(1); return url }
        let output = unique(url, suffix: "-telegram", ext: "mp4")
        var bitrate = Int(Double(budget) * 0.94 * 8 / seconds / 1000 - 128)
        guard bitrate >= 90 else { throw Failure.message("檔案過長，請改用無損分卷") }
        for attempt in 1...3 {
            try? FileManager.default.removeItem(at: output)
            var remainder = ""
            do {
                let args = ["-hide_banner","-loglevel","error","-progress","pipe:1","-nostats","-y","-i",url.path,
                            "-map","0:v:0","-map","0:a:0?","-c:v",codec,"-b:v","\(bitrate)k",
                            "-pix_fmt","yuv420p","-preset",speed,"-c:a","aac","-b:a","128k",
                            "-movflags","+faststart",output.path]
                _ = try run(ffmpeg, args) { chunk in
                    remainder += chunk
                    let parts = remainder.components(separatedBy: "\n")
                    remainder = parts.last ?? ""
                    for line in parts.dropLast() {
                        if line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
                            if let micros = Double(line.split(separator: "=").last ?? "") {
                                progress(min(0.98, micros / 1_000_000 / seconds * 0.98))
                            }
                        } else if line.hasPrefix("out_time=") {
                            let time = line.dropFirst("out_time=".count).split(separator: ":")
                            if time.count == 3, let h = Double(time[0]), let m = Double(time[1]), let s = Double(time[2]) {
                                progress(min(0.98, (h * 3600 + m * 60 + s) / seconds * 0.98))
                            }
                        }
                    }
                }
            } catch { try? FileManager.default.removeItem(at: output); throw error }
            let actual = ((try? FileManager.default.attributesOfItem(atPath: output.path)[.size]) as? NSNumber)?.int64Value ?? 0
            if actual > 0 && actual <= budget { progress(1); return output }
            bitrate = max(90, Int(Double(bitrate) * Double(budget) / Double(max(1,actual)) * 0.88))
            if attempt == 3 { break }
        }
        try? FileManager.default.removeItem(at: output)
        throw Failure.message("仍然超過設定容量；請改用無損分卷")
    }
    private func archive(_ url: URL, targetMB: Int, progress: @escaping (Double) -> Void) throws -> URL {
        guard let seven = Self.sevenZip() else { throw Failure.message("請先安裝 7-Zip（7zz）") }
        let target = unique(url, suffix: "-parts", ext: "7z")
        let volume = Int64(targetMB) * 1_000_000
        do {
            _ = try run(seven, ["a","-t7z","-mx=3","-v\(volume)b","-y",target.path,url.lastPathComponent], directory: url.deletingLastPathComponent())
        } catch { throw error }
        let first = URL(fileURLWithPath: target.path + ".001")
        guard FileManager.default.fileExists(atPath: first.path) else { throw Failure.message("7z 分卷未產生") }
        progress(1)
        return first
    }
}
