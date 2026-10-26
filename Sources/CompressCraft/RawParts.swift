import Foundation
enum RawParts {
    static func split(_ url: URL, mb: Int, cancelled: () -> Bool, progress: (Double) -> Void) throws -> URL {
        let fm = FileManager.default
        let total = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard total > 0 else { throw NSError(domain:"CompressCraft",code:1,userInfo:[NSLocalizedDescriptionKey:"無法讀取檔案大小"]) }
        let maxSize = Int64(mb) * 1_000_000
        let folder = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-parts-" + UUID().uuidString.prefix(6))
        try fm.createDirectory(at: folder, withIntermediateDirectories:true)
        let input = try FileHandle(forReadingFrom:url)
        defer { try? input.close() }
        var count = 0
        var done:Int64 = 0
        do {
            while done < total {
                if cancelled() { throw NSError(domain:"CompressCraft",code:2,userInfo:[NSLocalizedDescriptionKey:"已取消"]) }
                count += 1
                let part = folder.appendingPathComponent(url.lastPathComponent + String(format: ".part%03d",count))
                fm.createFile(atPath:part.path,contents:nil)
                let out = try FileHandle(forWritingTo:part)
                var size:Int64 = 0
                do {
                    while size < maxSize && done < total {
                        if cancelled() { throw NSError(domain:"CompressCraft",code:2,userInfo:[NSLocalizedDescriptionKey:"已取消"]) }
                        let bytes = try input.read(upToCount:Int(min(4_194_304,maxSize-size,total-done))) ?? Data()
                        guard !bytes.isEmpty else { throw NSError(domain:"CompressCraft",code:3,userInfo:[NSLocalizedDescriptionKey:"讀取中斷"]) }
                        try out.write(contentsOf:bytes)
                        size += Int64(bytes.count)
                        done += Int64(bytes.count)
                        progress(Double(done)/Double(total))
                    }
                    try out.close()
                } catch { try? out.close(); throw error }
            }
            return folder
        } catch { try? fm.removeItem(at:folder); throw error }
    }
    static func benchmark(_ url: URL, mb: Int, cancelled: () -> Bool, report: (String) -> Void) throws -> String {
        let fm = FileManager.default
        let total = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard total > 0 else { throw NSError(domain:"CompressCraft",code:20,userInfo:[NSLocalizedDescriptionKey:"無法讀取檔案"]) }
        let sampleSize = min(total, Int64(128_000_000))
        let temp = fm.temporaryDirectory.appendingPathComponent("CompressCraft-benchmark-" + UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let sample = temp.appendingPathComponent("sample.bin")
        let source = try FileHandle(forReadingFrom: url)
        fm.createFile(atPath: sample.path, contents: nil)
        let dest = try FileHandle(forWritingTo: sample)
        var left = sampleSize
        while left > 0 {
            if cancelled() { throw NSError(domain:"CompressCraft",code:21,userInfo:[NSLocalizedDescriptionKey:"已取消"]) }
            let data = try source.read(upToCount: Int(min(left, 4_194_304))) ?? Data()
            if data.isEmpty { break }
            try dest.write(contentsOf: data)
            left -= Int64(data.count)
        }
        try source.close()
        try dest.close()
        func digest(_ file: URL) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath:"/usr/bin/shasum")
            p.arguments = ["-a","256",file.path]
            let pipe = Pipe(); p.standardOutput = pipe
            try p.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw NSError(domain:"CompressCraft",code:22) }
            return String(decoding:output,as:UTF8.self).split(separator:" ").first.map(String.init) ?? ""
        }
        let originalHash = try digest(sample)
        let startSwift = Date()
        let swiftFolder = try split(sample, mb: mb, cancelled: cancelled, progress: { _ in })
        let swiftTime = Date().timeIntervalSince(startSwift)
        report("Swift 完成，正在測試系統 split")
        let prefix = temp.appendingPathComponent("system-").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/split")
        process.arguments = ["-b","\\(Int64(mb)*1_000_000)",sample.path,prefix]
        let startSystem = Date()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain:"CompressCraft",code:23,userInfo:[NSLocalizedDescriptionKey:"系統 split 執行失敗"]) }
        let systemTime = Date().timeIntervalSince(startSystem)
        let swiftFiles = try fm.contentsOfDirectory(at:swiftFolder,includingPropertiesForKeys:nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let systemFiles = try fm.contentsOfDirectory(at:temp,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("system-") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        func verify(_ parts:[URL]) throws -> Bool {
            let combined = temp.appendingPathComponent("check-" + UUID().uuidString)
            fm.createFile(atPath:combined.path,contents:nil)
            let writer = try FileHandle(forWritingTo:combined)
            for part in parts {
                let reader = try FileHandle(forReadingFrom:part)
                while let data = try reader.read(upToCount:4_194_304), !data.isEmpty { try writer.write(contentsOf:data) }
                try reader.close()
            }
            try writer.close()
            return try digest(combined) == originalHash
        }
        guard try verify(swiftFiles), try verify(systemFiles) else { throw NSError(domain:"CompressCraft",code:24,userInfo:[NSLocalizedDescriptionKey:"SHA-256 驗證失敗"]) }
        let mbSize = Double(sampleSize-left)/1_000_000
        let swiftSpeed = mbSize / max(swiftTime,0.001)
        let systemSpeed = mbSize / max(systemTime,0.001)
        let winner = swiftTime <= systemTime ? "Swift" : "macOS split"
        return String(format:"測試 %.0f MB｜Swift %.2fs (%.1f MB/s)｜split %.2fs (%.1f MB/s)｜較快：%@｜SHA-256 全部通過",mbSize,swiftTime,swiftSpeed,systemTime,systemSpeed,winner)
    }
    static func join(_ first: URL, cancelled: () -> Bool, progress: (Double) -> Void) throws -> URL {
        let name = first.lastPathComponent
        guard name.hasSuffix(".part001") else { throw NSError(domain:"CompressCraft",code:10,userInfo:[NSLocalizedDescriptionKey:"請先選擇 .part001"]) }
        let base = String(name.dropLast(8))
        let folder = first.deletingLastPathComponent()
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath:folder.path).filter { $0.hasPrefix(base + ".part") }
        var parts:[URL] = []
        for i in 1...999 {
            let n = base + String(format:".part%03d",i)
            if !names.contains(n) { break }
            parts.append(folder.appendingPathComponent(n))
        }
        guard !parts.isEmpty && parts.count == names.count else {
            throw NSError(domain:"CompressCraft",code:11,userInfo:[NSLocalizedDescriptionKey:"有分卷遺漏，請放齊 .part001、.part002 等全部檔案"])
        }
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        var output = folder.appendingPathComponent(stem + "-restored" + (ext.isEmpty ? "" : "." + ext))
        var suffix = 2
        while fm.fileExists(atPath:output.path) {
            output = folder.appendingPathComponent(stem + "-restored-\(suffix)" + (ext.isEmpty ? "" : "." + ext))
            suffix += 1
        }
        let total = try parts.reduce(Int64(0)) { count, part in
            count + ((try fm.attributesOfItem(atPath:part.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
        fm.createFile(atPath:output.path,contents:nil)
        let writer = try FileHandle(forWritingTo:output)
        defer { try? writer.close() }
        var done:Int64 = 0
        do {
            for part in parts {
                let reader = try FileHandle(forReadingFrom:part)
                defer { try? reader.close() }
                while true {
                    if cancelled() { throw NSError(domain:"CompressCraft",code:12,userInfo:[NSLocalizedDescriptionKey:"已取消"]) }
                    let bytes = try reader.read(upToCount:4_194_304) ?? Data()
                    if bytes.isEmpty { break }
                    try writer.write(contentsOf:bytes)
                    done += Int64(bytes.count)
                    progress(Double(done)/Double(max(1,total)))
                }
            }
            return output
        } catch { try? fm.removeItem(at:output); throw error }
    }
}
