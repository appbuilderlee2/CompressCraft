import Foundation
import CryptoKit

enum SystemParts {
    static func size(_ u: URL) throws -> Int64 {
        ((try FileManager.default.attributesOfItem(atPath:u.path)[.size] as? NSNumber)?.int64Value) ?? 0
    }
    static func digest(_ url: URL, progress: ((Double)->Void)? = nil) throws -> String {
        let total = try size(url)
        let f = try FileHandle(forReadingFrom:url)
        defer { try? f.close() }
        var hash = SHA256()
        var read:Int64 = 0
        while let chunk = try f.read(upToCount:4_194_304), !chunk.isEmpty {
            hash.update(data:chunk)
            read += Int64(chunk.count)
            if total > 0 { progress?(Double(read)/Double(total)) }
        }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    static func call(_ exe:String, _ args:[String], cancelled:()->Bool) throws {
        if cancelled() { throw NSError(domain:"CompressCraft",code:70,userInfo:[NSLocalizedDescriptionKey:"已取消"]) }
        let p=Process()
        p.executableURL=URL(fileURLWithPath:exe)
        p.arguments=args
        let log=Pipe()
        p.standardError=log
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let message=String(data:log.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
            throw NSError(domain:"CompressCraft",code:Int(p.terminationStatus),userInfo:[NSLocalizedDescriptionKey:message.isEmpty ? "系統工具執行失敗" : message])
        }
        if cancelled() { throw NSError(domain:"CompressCraft",code:70,userInfo:[NSLocalizedDescriptionKey:"已取消"]) }
    }
    static func split(_ source:URL, mb:Int, cancelled:()->Bool, progress:@escaping(Double)->Void) throws -> URL {
        let fm=FileManager.default
        var dir:ObjCBool=false
        guard fm.fileExists(atPath:source.path,isDirectory:&dir), !dir.boolValue else {
            throw NSError(domain:"CompressCraft",code:71,userInfo:[NSLocalizedDescriptionKey:"請選擇單一檔案"])
        }
        let length=try size(source), bytes=Int64(mb)*1_000_000
        guard length>0 && bytes>0 else { throw NSError(domain:"CompressCraft",code:72,userInfo:[NSLocalizedDescriptionKey:"檔案為空或容量設定錯誤"]) }
        let folder=source.deletingLastPathComponent().appendingPathComponent(source.lastPathComponent+"-split-"+UUID().uuidString.prefix(6))
        try fm.createDirectory(at:folder,withIntermediateDirectories:false)
        let prefix=folder.appendingPathComponent(source.lastPathComponent+".part").path
        do {
            let originalHash=try digest(source,progress:{progress($0*0.15)})
            try call("/usr/bin/split",["-b",String(bytes),"-a","3",source.path,prefix],cancelled:cancelled)
            let parts=try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).sorted{$0.lastPathComponent<$1.lastPathComponent}
            guard !parts.isEmpty else { throw NSError(domain:"CompressCraft",code:73,userInfo:[NSLocalizedDescriptionKey:"未產生分卷"]) }
            var done:Int64=0
            var hash=SHA256()
            for part in parts {
                guard try size(part)<=bytes else { throw NSError(domain:"CompressCraft",code:74,userInfo:[NSLocalizedDescriptionKey:"分卷超過設定容量"]) }
                let handle=try FileHandle(forReadingFrom:part)
                defer { try? handle.close() }
                while let data=try handle.read(upToCount:4_194_304), !data.isEmpty {
                    if cancelled() { throw NSError(domain:"CompressCraft",code:70,userInfo:[NSLocalizedDescriptionKey:"已取消"]) }
                    hash.update(data:data)
                    done += Int64(data.count)
                    progress(0.15+0.85*Double(done)/Double(length))
                }
            }
            guard hash.finalize().map({String(format:"%02x",$0)}).joined()==originalHash else {
                throw NSError(domain:"CompressCraft",code:75,userInfo:[NSLocalizedDescriptionKey:"SHA-256 驗證失敗，請勿上傳"])
            }
            // Include a separately uploadable hash reference (not a part).
            try (originalHash+"  "+source.lastPathComponent+"\n").write(to:folder.appendingPathComponent("SHA256.txt"),atomically:true,encoding:.utf8)
            progress(1)
            return folder
        } catch {try? fm.removeItem(at:folder);throw error}
    }
    static func join(_ first:URL,cancelled:()->Bool,progress:@escaping(Double)->Void) throws -> URL {
        let fm=FileManager.default, name=first.lastPathComponent
        guard name.hasSuffix(".partaaa") else { throw NSError(domain:"CompressCraft",code:76,userInfo:[NSLocalizedDescriptionKey:"請選擇 .partaaa 第一卷"]) }
        let base=String(name.dropLast(3))
        let folder=first.deletingLastPathComponent()
        let parts=try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
            .filter{$0.lastPathComponent.hasPrefix(base)}
            .sorted{$0.lastPathComponent<$1.lastPathComponent}
        guard !parts.isEmpty else { throw NSError(domain:"CompressCraft",code:77,userInfo:[NSLocalizedDescriptionKey:"分卷不存在"]) }
        // Verify alpha suffix continuity before joining.
        for (i,part) in parts.enumerated() {
            var num=i, suffix=""
            for _ in 0..<3 {suffix=String(UnicodeScalar(97+num%26)!)+suffix;num/=26}
            guard part.lastPathComponent==base+suffix else {
                throw NSError(domain:"CompressCraft",code:78,userInfo:[NSLocalizedDescriptionKey:"分卷缺失或順序錯誤"])
            }
        }
        let originalName=String(base.dropLast(".part".count))
        let stem=(originalName as NSString).deletingPathExtension
        let ext=(originalName as NSString).pathExtension
        let suffix=ext.isEmpty ? "" : "."+ext
        var output=folder.appendingPathComponent(stem+"-restored"+suffix)
        var index=2
        while fm.fileExists(atPath:output.path) {output=folder.appendingPathComponent(stem+"-restored-"+String(index)+suffix);index+=1}
        let total=try parts.reduce(Int64(0)){$0+(try size($1))}
        // Execute native cat with stdout redirected into new file.
        fm.createFile(atPath:output.path,contents:nil)
        do {
            let process=Process()
            process.executableURL=URL(fileURLWithPath:"/bin/cat")
            process.arguments=parts.map{$0.path}
            let handle=try FileHandle(forWritingTo:output)
            process.standardOutput=handle
            let errorPipe=Pipe();process.standardError=errorPipe
            try process.run()
            while process.isRunning {
                if cancelled() {process.terminate();process.waitUntilExit();try? handle.close();throw NSError(domain:"CompressCraft",code:70,userInfo:[NSLocalizedDescriptionKey:"已取消"])}
                let written=(try? size(output)) ?? 0
                if total>0 {progress(min(0.8,0.8*Double(written)/Double(total)))}
                Thread.sleep(forTimeInterval:0.2)
            }
            process.waitUntilExit()
            try handle.close()
            guard process.terminationStatus==0 else {throw NSError(domain:"CompressCraft",code:79,userInfo:[NSLocalizedDescriptionKey:"cat 合併失敗"])}
            let actual=try digest(output,progress:{progress(0.8+0.2*$0)})
            let manifest=folder.appendingPathComponent("SHA256.txt")
            if fm.fileExists(atPath:manifest.path) {
                let expected=try String(contentsOf:manifest,encoding:.utf8).split(separator:" ").first.map(String.init) ?? ""
                guard actual==expected else {throw NSError(domain:"CompressCraft",code:80,userInfo:[NSLocalizedDescriptionKey:"SHA-256 不一致，還原失敗"])}
            } else {
                throw NSError(domain:"CompressCraft",code:81,userInfo:[NSLocalizedDescriptionKey:"缺少 SHA256.txt，無法驗證原始檔案"])
            }
            progress(1)
            return output
        } catch {try? fm.removeItem(at:output);throw error}
    }
}