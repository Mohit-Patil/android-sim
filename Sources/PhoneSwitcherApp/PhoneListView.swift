import PhoneCore
import SwiftUI

struct PhoneListView: View {
    @Bindable var model: AppModel
    @State private var editing: Phone?
    @State private var confirmReset: Phone?
    @State private var confirmDelete: Phone?
    @State private var addCount = 1
    /// Off only for `--render`, since ImageRenderer can't draw scroll views.
    var scrolls = true

    private var overview: Overview { model.overview }
    private var canSwitch: Bool { overview.storageConnected && overview.foreignRunning.isEmpty && !model.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            banners
            if overview.storageConnected && overview.baseExists && overview.rows.isEmpty {
                emptyState
            } else {
                if scrolls {
                    ScrollView { grid }
                } else {
                    grid
                    Spacer(minLength: 0)
                }
            }
            Divider()
            footer
        }
        .sheet(item: $editing) { phone in
            PhoneEditSheet(phone: phone) { label, notes in model.relabel(phone.id, label: label, notes: notes) }
        }
        .confirmationDialog(confirmReset.map { "Reset \($0.label)?" } ?? "", isPresented: .constant(confirmReset != nil), presenting: confirmReset) { phone in
            Button("Reset phone", role: .destructive) { model.reset(phone.id); confirmReset = nil }
            Button("Cancel", role: .cancel) { confirmReset = nil }
        } message: { phone in
            Text("This erases Phone \(phone.number) back to a fresh phone. Its Google sign-in and app data will be lost.")
        }
        .confirmationDialog(confirmDelete.map { "Delete \($0.label)?" } ?? "", isPresented: .constant(confirmDelete != nil), presenting: confirmDelete) { phone in
            Button("Delete phone", role: .destructive) { model.delete(phone.id); confirmDelete = nil }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: { phone in
            Text("Phone \(phone.number) and everything on it will be deleted.")
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 20)], spacing: 24) {
            ForEach(overview.rows) { row in
                PhoneTile(row: row, enabled: canSwitch || row.status == .running)
                    .onTapGesture { tap(row) }
                    .contextMenu { menu(for: row.phone) }
            }
        }
        .padding(24)
    }

    private func tap(_ row: PhoneRow) {
        if row.status == .running { model.bringToFront(row.id) } else if canSwitch { model.switchTo(row.id) }
    }

    @ViewBuilder private func menu(for phone: Phone) -> some View {
        Button("Switch to this phone") { model.switchTo(phone.id) }.disabled(!canSwitch)
        Button("Show window") { model.bringToFront(phone.id) }
        Divider()
        Button("Rename…") { editing = phone }
        Button("Reset…") { confirmReset = phone }.disabled(model.isBusy)
        Button("Delete…") { confirmDelete = phone }.disabled(model.isBusy)
    }

    // MARK: Banners

    @ViewBuilder private var banners: some View {
        VStack(spacing: 0) {
            if !overview.storageConnected {
                Banner(style: .error, text: overview.storageError ?? "Storage isn't available.")
            } else {
                if let error = overview.loadError { Banner(style: .error, text: error) }
                if !overview.baseExists {
                    Banner(style: .info, text: "Set up the base phone once. It starts offline for about 3 minutes, then every new phone is copied from it.") {
                        Button("Set up base phone") { model.setupBase() }.disabled(model.isBusy)
                    }
                }
                ForEach(overview.foreignRunning, id: \.self) { name in
                    Banner(style: .warning, text: "Close \(name) to switch phones. Only one emulator runs at a time.")
                }
                if overview.buildStampMismatch {
                    Banner(style: .warning, text: "The emulator was updated since these phones were made. Each phone will do one slow start (about a minute); logins are kept.")
                }
                if let storage = overview.storage, storage.overWarning {
                    Banner(style: .warning, text: "Phones are using more than \(storage.warningBytes.formatted(.byteCount(style: .file))). Delete phones you no longer need to free space.")
                }
            }
            if let error = model.errorMessage { Banner(style: .error, text: error) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.gen3").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No phones yet").font(.title3.weight(.semibold))
            Text("Add a phone, switch to it, and sign in with its Google account.").foregroundStyle(.secondary)
            Button("Add phone") { model.add(count: 1) }.buttonStyle(.borderedProminent).disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Stepper(value: $addCount, in: 1...15) {
                Button(addCount == 1 ? "Add phone" : "Add \(addCount) phones") { model.add(count: addCount) }
            }
            .disabled(!overview.storageConnected || !overview.baseExists || model.isBusy)
            if overview.rows.contains(where: { $0.status == .running }) {
                Button("Save and stop") { model.stop() }.disabled(model.isBusy)
            }
            Spacer()
            if let message = model.busyMessage {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            } else if let seconds = model.lastSwitchSeconds {
                Text(String(format: "Last switch took %.0f s", seconds)).foregroundStyle(.secondary)
            }
            if let storage = overview.storage {
                Text("Phones use up to \(storage.phonesBytes.formatted(.byteCount(style: .file))), \(storage.freeBytes.formatted(.byteCount(style: .file))) free")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct PhoneTile: View {
    let row: PhoneRow
    let enabled: Bool
    @State private var hovering = false

    private var isRunning: Bool { row.status == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(9 / 19.5, contentMode: .fit)
                .overlay { screen }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isRunning ? Color.accentColor : Color.primary.opacity(hovering && enabled ? 0.35 : 0.12),
                                      lineWidth: isRunning ? 3 : 1)
                }
                .overlay(alignment: .topLeading) {
                    Text(row.phone.number)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            Text(row.phone.label).font(.headline).lineLimit(1).truncationMode(.middle)
            if !row.phone.notes.isEmpty {
                Text(row.phone.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Label(statusText, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(isRunning ? Color.accentColor : row.status == .broken ? .red : .secondary)
        }
        .opacity(enabled || isRunning ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(isRunning ? "Running — click to show its window" : "Click to switch to this phone")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var screen: some View {
        if let url = row.screenshot, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.primary.opacity(0.05)
                Image(systemName: row.status == .broken ? "exclamationmark.triangle" : "iphone.gen3")
                    .font(.system(size: 30)).foregroundStyle(.tertiary)
            }
        }
    }

    private var statusText: String {
        switch row.status {
        case .running: "Running"
        case .saved: "Saved"
        case .neverStarted: "Not started yet"
        case .broken: "Files missing — reset it"
        }
    }

    private var statusIcon: String {
        switch row.status {
        case .running: "play.circle.fill"
        case .saved: "pause.circle"
        case .neverStarted: "circle.dashed"
        case .broken: "exclamationmark.triangle"
        }
    }
}

struct Banner<Accessory: View>: View {
    enum Style { case info, warning, error }
    let style: Style
    let text: String
    @ViewBuilder var accessory: () -> Accessory

    init(style: Style, text: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.style = style
        self.text = text
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: style == .info ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(color.opacity(0.12))
    }

    private var color: Color {
        switch style {
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }
}

extension Banner where Accessory == EmptyView {
    init(style: Style, text: String) {
        self.init(style: style, text: text) { EmptyView() }
    }
}
