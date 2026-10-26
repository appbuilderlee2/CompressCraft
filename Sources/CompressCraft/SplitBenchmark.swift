import Foundation
import CryptoKit

enum SplitBenchmark {
    struct Result {
        let swiftSeconds: Double
        let systemSeconds: Double
        let bytes: Int64
        let valid: Bool
        var recommendation: String { swiftSeconds <= systemSeconds ? "Swift" : "macOS split" }
        var text: String {
            let mb = Double(bytes)/1_000_000
            return String(format:"測試 %.0f MB｜Swift %.1f MB/s (%.2fs)｜split %.1f MB/s (%.2fs)｜SHA-256 %@｜推薦 %@",
                          mb,mb/max(0.001,swiftSeconds),swiftSeconds,mb/max(0.001,systemSeconds),systemSeconds,
                          valid ? "一致 ✓" : "不一致 ✗",valid ? recommendation : "無")
        }
    }
    static func sha(_ urls: [URL]) throws -> String {
        var hash = SHA256()
        for url in urls {
            let file = try FileHandle(forReadingFrom:url)
            defer { try? file.close() }
            while let data = try file.read(upToCount: 4_194_304), !data.isEmpty { hash.update(data:data) }
        }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    static func test(_ original: URL) throws -> Result {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CompressCraft-benchmark-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let source = folder.appendingPathComponent("sample.dat")
        let input = try FileHandle(forReadingFrom:original)
        defer { try? input.close() }
        FileManager.default.createFile(atPath:source.path,contents:nil)
        let writer = try FileHandle(forWritingTo:source)
        defer { try? writer.close() }
        var bytes:Int64 = 0
        while bytes < 128_000_000 {
            guard let data = try input.read(upToCount:Int(min(4_194_304,128_000_000-bytes))), !data.isEmpty else { break }
            try writer.write(contentsOf:data)
            bytes += Int64(data.count)
        }
        try writer.close()
        guard bytes > 0 else { throw NSError(domain:"CompressCraft",code:40,userInfo:[NSLocalizedDescriptionKey:"檔案不可讀"]) }
        let startSwift = Date()
        let swiftFolder = try RawParts.split(source,mb:32,cancelled:{false},progress:{_ in})
        let swiftSeconds = Date().timeIntervalSince(startSwift)
        let systemFolder = folder.appendingPathComponent("system")
        try FileManager.default.createDirectory(at:systemFolder,withIntermediateDirectories:true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath:"/usr/bin/split")
        proc.arguments = ["-b","32000000",source.path,systemFolder.appendingPathComponent("part").path]
        let startSystem = Date()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw NSError(domain:"CompressCraft",code:41,userInfo:[NSLocalizedDescriptionKey:"系統 split 執行失敗"]) }
        let systemSeconds = Date().timeIntervalSince(startSystem)
        let swiftParts = try FileManager.default.contentsOfDirectory(at:swiftFolder,includingPropertiesForKeys:nil).sorted{$0.lastPathComponent < $1.lastPathComponent}
        let systemParts = try FileManager.default.contentsOfDirectory(at:systemFolder,includingPropertiesForKeys:nil).sorted{$0.lastPathComponent < $1.lastPathComponent}
        let originalHash = try sha([source])
        return Result(swiftSeconds:swiftSeconds,systemSeconds:systemSeconds,bytes:bytes,
                      valid:originalHash == (try sha(swiftParts)) && originalHash == (try sha(systemParts)))
    }
    static func systemSplit(_ url: URL, mb: Int) throws -> URL {
        let folder = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent+"-parts-"+UUID().uuidString.prefix(6))
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath:"/usr/bin/split")
        proc.arguments = ["-b",String(Int64(mb)*1_000_000),"-a","3",url.path,folder.appendingPathComponent(url.lastPathComponent+".part").path]
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { throw NSError(domain:"CompressCraft",code:42,userInfo:[NSLocalizedDescriptionKey:"split 執行失敗"]) }
            let names = try FileManager.default.contentsOfDirectory(atPath:folder.path).sorted()
            for (i,name) in names.enumerated() {
                let old = folder.appendingPathComponent(name)
                let temp = folder.appendingPathComponent(String(format:"rename-%03d",i+1))
                try FileManager.default.moveItem(at:old,to:temp)
            }
            for i in names.indices {
                try FileManager.default.moveItem(at:folder.appendingPathComponent(String(format:"rename-%03d",i+1)),
                    to:folder.appendingPathComponent(url.lastPathComponent+String(format:".part%03d",i+1)))
            }
            return folder
        } catch {
            if proc.isRunning { proc.terminate() }
            try? FileManager.default.removeItem(at:folder)
            throw error
        }
    }
}
