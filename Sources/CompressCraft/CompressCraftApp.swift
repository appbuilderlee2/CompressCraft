import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main struct CompressCraftApp: App {
    @StateObject private var model = CompressionModel()
    var body: some Scene {
        WindowGroup {
            MainView().environmentObject(model).frame(minWidth: 690, minHeight: 520)
        }
    }
}
enum JobMode: String, CaseIterable, Identifiable {
    case automatic = "自動判斷", video = "影片壓縮", archive = "無損分卷"
    var id: String { rawValue }
}
struct WorkItem: Identifiable {
    let id = UUID()
    let url: URL
    var status = "等待中"
    var progress = 0.0
    var output: URL?
}
struct MainView: View {
    @EnvironmentObject var model: CompressionModel
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "shippingbox.fill").font(.system(size: 32))
                VStack(alignment: .leading) {
                    HStack(spacing: 8) { Text("CompressCraft").font(.title.bold()); Text("v0.3.1").font(.caption).foregroundColor(.secondary) }
                    Text("影片壓縮＋檔案分卷 · Telegram Ready").foregroundColor(.secondary)
                }
                Spacer()
                Button("檢查依賴") { model.checkTools() }
            }
            HStack {
                Picker("模式", selection: $model.mode) {
                    ForEach(JobMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("目標容量", selection: $model.preset) {
                    Text("Telegram 免費 1900MB").tag(1900)
                    Text("Premium 3800MB").tag(3800)
                    Text("自訂").tag(0)
                }
                if model.preset == 0 { TextField("MB", value: $model.customMB, format: .number).frame(width: 85) }
            }
            Picker("影片編碼", selection: $model.codec) {
                Text("H.264（兼容）").tag("libx264")
                Text("H.265（較細）").tag("libx265")
            }.frame(width: 300)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill").font(.largeTitle)
                Text("拖放檔案／資料夾到這裏").font(.headline)
                Button("加入檔案／資料夾") { choose() }
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .background(hover ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            .cornerRadius(12)
            .onDrop(of: [UTType.fileURL], isTargeted: $hover) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url { DispatchQueue.main.async { model.add([url]) } }
                    }
                }
                return !providers.isEmpty
            }
            List {
                ForEach(model.items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.url.lastPathComponent).lineLimit(1)
                            Text(item.status).font(.caption).foregroundColor(.secondary)
                            if item.progress > 0 && item.progress < 1 { ProgressView(value: item.progress) }
                        }
                        Spacer()
                        if let url = item.output {
                            Button("顯示檔案") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                    }
                }
            }
            HStack {
                Text(model.tools).font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("清除") { model.clear() }.disabled(model.running)
                if model.running { Button("停止") { model.cancel() } }
                else { Button("開始處理") { model.start() }.buttonStyle(.borderedProminent).disabled(model.items.isEmpty || model.targetMB < 100) }
            }
        }.padding(20).onAppear { model.checkTools() }
    }
    private func choose() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = true
        p.begin { result in if result == .OK { model.add(p.urls) } }
    }
}
