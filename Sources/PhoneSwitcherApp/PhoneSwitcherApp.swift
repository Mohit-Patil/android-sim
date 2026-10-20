import AppKit
import SwiftUI

@main
struct PhoneSwitcherApp: App {
    @State private var model = AppModel()

    init() {
        // `--render <png>` draws the main view with live data to an image and exits (layout check).
        if let index = CommandLine.arguments.firstIndex(of: "--render"), index + 1 < CommandLine.arguments.count {
            renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        // Launched as a bare SwiftPM binary we still want a normal Dock app with a window.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Phone Switcher", id: "main") {
            PhoneListView(model: model)
                .frame(minWidth: 560, minHeight: 480)
                .onAppear {
                    model.startRefreshing()
                    NSApplication.shared.activate()
                }
                .onDisappear { model.stopRefreshing() }
        }
        .defaultSize(width: 880, height: 640)
    }
}

@MainActor
private func renderPreview(to url: URL) {
    let model = AppModel()
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        await model.refresh()
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let renderer = ImageRenderer(content: PhoneListView(model: model, scrolls: false).frame(width: 880, height: 640).background(Color(nsColor: .windowBackgroundColor)))
    renderer.scale = 2
    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
    exit(0)
}
