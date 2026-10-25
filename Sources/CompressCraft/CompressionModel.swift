import Foundation
import Combine

@MainActor final class CompressionModel: ObservableObject {
    @Published var items: [WorkItem] = []
    @Published var mode: JobMode = .automatic
    @Published var codec = "libx264"
    @Published var speed = "veryfast"
    @Published var preset = 1900
    @Published var customMB = 1900
    @Published var tools = "檢查中…"
    @Published var running = false
    private let engine = CompressionEngine()
    var targetMB: Int { preset == 0 ? customMB : preset }
    func add(_ urls: [URL]) {
        for u in urls {
            let path = u.standardizedFileURL.path
            if !items.contains(where: { $0.url.path == path }) { items.append(WorkItem(url: u.standardizedFileURL)) }
        }
    }
    func clear() { if !running { items.removeAll() } }
    func checkTools() {
        let f = CompressionEngine.find("ffmpeg") != nil
        let p = CompressionEngine.find("ffprobe") != nil
        let z = CompressionEngine.sevenZip() != nil
        tools = "FFmpeg: \(f ? "✓" : "缺少")   FFprobe: \(p ? "✓" : "缺少")   7-Zip: \(z ? "✓" : "缺少")" + ((!f || !p || !z) ? "   · 請下載 All-In-One 版本" : "   · 工具已找到")
    }
    func cancel() { engine.cancel() }
    func start() {
        guard !running, !items.isEmpty, targetMB >= 100 else { return }
        running = true
        engine.reset()
        let jobs = items.map { ($0.id, $0.url) }
        let chosenMode = mode, chosenCodec = codec, chosenSpeed = speed, size = targetMB, worker = engine
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (id, url) in jobs {
                if worker.cancelled { break }
                self?.update(id: id, status: "處理中", progress: 0, output: nil)
                do {
                    let result = try worker.perform(url: url, mode: chosenMode, codec: chosenCodec, speed: chosenSpeed, targetMB: size) { v in
                        self?.update(id: id, status: "處理中 \(Int(v * 100))%", progress: v, output: nil)
                    }
                    self?.update(id: id, status: "完成", progress: 1, output: result)
                } catch {
                    self?.update(id: id, status: "失敗：\(error.localizedDescription)", progress: 0, output: nil)
                }
            }
            DispatchQueue.main.async { [weak self] in self?.running = false; self?.checkTools() }
        }
    }
    nonisolated private func update(id: UUID, status: String, progress: Double, output: URL?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[i].status = status
            self.items[i].progress = progress
            if let output = output { self.items[i].output = output }
        }
    }
}
