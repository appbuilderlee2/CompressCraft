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
}