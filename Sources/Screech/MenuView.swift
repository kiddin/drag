import ScreechDSP
import SwiftUI

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            materials
            Text(model.material.blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            tryIt
            Divider()
            controls
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Screech").font(.headline)
                status
            }
            Spacer()
            Toggle("Enabled", isOn: $model.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.statusMode == .idle ? Color.secondary.opacity(0.4) : Color.green)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if !model.enabled { return "Off" }
        let app = model.statusApp.isEmpty ? "" : " · \(model.statusApp)"
        switch model.statusMode {
        case .idle: return "Listening for window drags"
        case .drag: return "Dragging \(Int(model.statusSpeed)) pt/s\(app)"
        case .resize: return "Resizing \(Int(model.statusSpeed)) pt/s\(app)"
        }
    }

    private var materials: some View {
        HStack(spacing: 6) {
            ForEach(Materials.all) { m in
                let selected = m.id == model.materialID
                Button {
                    model.materialID = m.id
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: m.symbol)
                            .font(.system(size: 17))
                            .frame(height: 20)
                        Text(m.name).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(m.blurb)
            }
        }
    }

    private var tryIt: some View {
        HStack(spacing: 8) {
            Button {
                model.preview(.drag)
            } label: {
                Label("Try drag", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            Button {
                model.preview(.resize)
            } label: {
                Label("Try resize", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity)
            }
        }
        .controlSize(.regular)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRow("Volume", value: $model.volume, low: "speaker.fill", high: "speaker.wave.3.fill")
            sliderRow("Ring", value: $model.ring, low: "hand.draw", high: "bell.fill")
                .help("How much the material resonates: left is a dry scrape, right rings like the material")
            sliderRow("Reverb", value: $model.reverb, low: "square", high: "square.stack.3d.up.fill")
            Toggle("Drag sounds", isOn: $model.dragSounds)
            Toggle("Resize sounds", isOn: $model.resizeSounds)
            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if let error = model.loginItemError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, low: String, high: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 54, alignment: .leading)
            Image(systemName: low).foregroundStyle(.secondary).frame(width: 16)
            Slider(value: value, in: 0...1)
            Image(systemName: high).foregroundStyle(.secondary).frame(width: 18)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit Screech") { model.quit() }
                .keyboardShortcut("q")
        }
    }
}
