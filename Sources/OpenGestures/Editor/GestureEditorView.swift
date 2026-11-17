import AppKit
import OpenGesturesCore
import SwiftUI
import UniformTypeIdentifiers

struct GestureEditorView: View {
    @ObservedObject var model: GestureEditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                GestureList(model: model)
                    .frame(width: 250)
                Divider()
                Group {
                    if let gesture = model.selection {
                        GestureDetail(model: model, gesture: gesture)
                            .id("\(model.device.rawValue)/\(gesture.rawValue)")
                    } else {
                        Text("No gesture selected")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            GeneralSettingsBar(model: model)
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}

// MARK: - List

private struct GestureList: View {
    @ObservedObject var model: GestureEditorModel

    var body: some View {
        VStack(spacing: 10) {
            Picker("Device", selection: $model.device) {
                ForEach(DeviceKind.allCases, id: \.self) { device in
                    Text(Titles.device(device)).tag(device)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)

            SearchField(text: $model.search)
                .padding(.horizontal, 12)

            List(selection: $model.selection) {
                let bound = model.boundGestures
                if !bound.isEmpty {
                    Section("In use") {
                        ForEach(bound, id: \.self) { row($0) }
                    }
                }
                ForEach(Gesture.Category.allCases, id: \.self) { category in
                    let gestures = model.gestures(in: category)
                    if !gestures.isEmpty {
                        Section(Titles.category(category)) {
                            ForEach(gestures, id: \.self) { row($0) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 12)
    }

    private func row(_ gesture: Gesture) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Titles.gesture(gesture))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let summary = model.summary(for: gesture) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
        .tag(gesture)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Detail

private struct GestureDetail: View {
    @ObservedObject var model: GestureEditorModel
    let gesture: Gesture

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                GestureDiagram(gesture: gesture, device: model.device, slideAxis: slideAxis)
                    .frame(width: 132, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Titles.gesture(gesture))
                        .font(.title3.weight(.semibold))
                    Text(gesture.rawValue)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let problem = model.problem {
                Notice(
                    text: String(localized: "The configuration file has an error, so editing is paused until it is fixed."),
                    detail: problem,
                    button: String(localized: "Open Configuration File"),
                    action: model.openConfigurationFile
                )
            } else {
                Group {
                    if gesture.isContinuous {
                        SlideEditor(model: model, gesture: gesture)
                    } else {
                        ActionEditor(model: model, gesture: gesture)
                    }
                }

                let overlaps = model.overlaps(for: gesture)
                if !overlaps.isEmpty {
                    let features = ListFormatter.localizedString(byJoining: overlaps.map(Titles.feature))
                    Notice(
                        text: String(localized: "macOS also responds to this gesture (\(features)). Turn that off, or both will run."),
                        button: String(localized: "Open Trackpad Settings"),
                        action: model.openTrackpadSettings
                    )
                }
            }

            if let error = model.writeError {
                Notice(text: String(localized: "The change was not saved."), detail: error)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var slideAxis: Axis? {
        guard case .preset(let preset, _) = model.slide(for: gesture) else { return nil }
        return preset.actions.keys.first?.axis
    }
}

/// A problem or caveat stated inline, with the one thing to do about it.
private struct Notice: View {
    let text: String
    var detail: String?
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let button, let action {
                    Button(button, action: action)
                        .buttonStyle(.link)
                }
            }
        }
        .font(.callout)
    }
}

// MARK: - Discrete actions

private enum ActionChoice: Hashable {
    case none
    case shortcut
    case application
    case url
    case text
    case builtIn(BuiltInAction)
    case custom

    init(_ draft: ActionDraft) {
        switch draft {
        case .none: self = .none
        case .shortcut: self = .shortcut
        case .application: self = .application
        case .url: self = .url
        case .text: self = .text
        case .builtIn(let action): self = .builtIn(action)
        case .custom: self = .custom
        }
    }
}

private struct ActionEditor: View {
    @ObservedObject var model: GestureEditorModel
    let gesture: Gesture

    /// A kind picked from the menu that still needs a value before it can
    /// be saved, such as a shortcut not yet recorded.
    @State private var pending: ActionChoice?
    @State private var field = ""
    @FocusState private var fieldFocused: Bool

    private var draft: ActionDraft { model.action(for: gesture) }
    private var choice: ActionChoice { pending ?? ActionChoice(draft) }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 14) {
            GridRow {
                label("Action")
                Picker("Action", selection: Binding(get: { choice }, set: { choose($0) })) {
                    Text("None").tag(ActionChoice.none)
                    Divider()
                    Text("Keyboard Shortcut").tag(ActionChoice.shortcut)
                    Text("Open Application").tag(ActionChoice.application)
                    Text("Open Link").tag(ActionChoice.url)
                    Text("Type Text").tag(ActionChoice.text)
                    ForEach(Titles.actionGroups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.actions, id: \.self) { action in
                                Text(Titles.action(action)).tag(ActionChoice.builtIn(action))
                            }
                        }
                    }
                    if case .builtIn(let action) = draft,
                       !Titles.actionGroups.contains(where: { $0.actions.contains(action) }) {
                        Text(Titles.action(action)).tag(ActionChoice.builtIn(action))
                    }
                    if case .custom = draft {
                        Text("Custom").tag(ActionChoice.custom)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }
            valueRow
        }
        .onAppear(perform: loadField)
    }

    @ViewBuilder
    private var valueRow: some View {
        switch choice {
        case .shortcut:
            GridRow {
                label("Shortcut")
                ShortcutRecorder(shortcut: shortcut, startsRecording: pending == .shortcut) { keys in
                    pending = nil
                    model.set(.shortcut(keys), for: gesture)
                }
            }
        case .application:
            GridRow {
                label("Application")
                Button(action: chooseApplication) {
                    HStack(spacing: 6) {
                        if let reference = application {
                            if let icon = reference.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text(reference.displayName)
                        } else {
                            Text("Choose…")
                        }
                    }
                }
            }
        case .url, .text:
            GridRow {
                label(choice == .url ? "Link" : "Text")
                TextField(choice == .url ? "https://" : "", text: $field)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .focused($fieldFocused)
                    .onSubmit(commitField)
                    .onChange(of: fieldFocused) { focused in
                        if !focused { commitField() }
                    }
            }
        case .custom:
            if case .custom(let toml) = draft {
                GridRow {
                    label("Value")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(toml)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Written by hand in the configuration file.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Open Configuration File", action: model.openConfigurationFile)
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }
        case .none, .builtIn:
            EmptyView()
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private var shortcut: String? {
        if case .shortcut(let keys) = draft { return keys }
        return nil
    }

    private var application: ApplicationReference? {
        if case .application(let name) = draft { return ApplicationReference(name) }
        return nil
    }

    private func choose(_ choice: ActionChoice) {
        switch choice {
        case .none:
            pending = nil
            model.set(ActionDraft.none, for: gesture)
        case .builtIn(let action):
            pending = nil
            model.set(.builtIn(action), for: gesture)
        case .custom:
            pending = nil
        case .shortcut, .url, .text:
            pending = choice
            field = ""
            if choice != .shortcut {
                DispatchQueue.main.async { fieldFocused = true }
            }
        case .application:
            pending = choice
            chooseApplication()
        }
    }

    private func loadField() {
        switch draft {
        case .url(let address): field = address
        case .text(let text): field = text
        default: field = ""
        }
    }

    private func commitField() {
        let value = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch choice {
        case .url:
            let address = value.contains("://") ? value : "https://" + value
            field = address
            model.set(.url(address), for: gesture)
        case .text:
            model.set(.text(field), for: gesture)
        default:
            return
        }
        pending = nil
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else {
            if application == nil { pending = nil }
            return
        }
        let name = Bundle(url: url)?.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        pending = nil
        model.set(.application(name), for: gesture)
    }
}

// MARK: - Slides

private enum SlideChoice: Hashable {
    case none
    case preset(SlidePreset)
    case custom
}

private struct SlideEditor: View {
    @ObservedObject var model: GestureEditorModel
    let gesture: Gesture

    /// From -1 (least sensitive) to 1 (most), 0 being the preset's own step.
    @State private var sensitivity = 0.0

    private var draft: SlideDraft { model.slide(for: gesture) }

    private var choice: SlideChoice {
        switch draft {
        case .none: .none
        case .preset(let preset, _): .preset(preset)
        case .custom: .custom
        }
    }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 14) {
            GridRow {
                label("Action")
                Picker("Action", selection: Binding(get: { choice }, set: { choose($0) })) {
                    Text("None").tag(SlideChoice.none)
                    Divider()
                    ForEach(SlidePreset.allCases, id: \.self) { preset in
                        Text(Titles.preset(preset)).tag(SlideChoice.preset(preset))
                    }
                    if case .custom = draft {
                        Text("Custom").tag(SlideChoice.custom)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }

            switch draft {
            case .preset(let preset, _):
                GridRow {
                    label("Sensitivity")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Low").font(.caption).foregroundStyle(.secondary).fixedSize()
                            Slider(value: $sensitivity, in: -1...1) { editing in
                                if !editing { commit(preset) }
                            }
                            .frame(width: 200)
                            Text("High").font(.caption).foregroundStyle(.secondary).fixedSize()
                        }
                        Text(caption(for: preset))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            case .custom(let toml):
                GridRow {
                    label("Value")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(toml)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Configuration File", action: model.openConfigurationFile)
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            case .none:
                EmptyView()
            }
        }
        .onAppear(perform: loadSensitivity)
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func choose(_ choice: SlideChoice) {
        switch choice {
        case .none: model.set(SlideDraft.none, for: gesture)
        case .preset(let preset): model.set(.preset(preset, step: nil), for: gesture)
        case .custom: return
        }
        loadSensitivity()
    }

    // Each unit of sensitivity scales the step by 2^1.3, so the slider spans
    // from about 2.5 times the preset's step down to 0.4 times it.
    private static let range = 1.3

    private func baseStep(for preset: SlidePreset) -> Double {
        preset.step ?? model.settings.recognizer.slideStep
    }

    private func step(for preset: SlidePreset) -> Double {
        let raw = baseStep(for: preset) * pow(2, -sensitivity * Self.range)
        return min(max(raw, SlideBinding.stepRange.lowerBound), SlideBinding.stepRange.upperBound)
    }

    private func loadSensitivity() {
        guard case .preset(let preset, let step) = draft, let step else {
            sensitivity = 0
            return
        }
        sensitivity = min(max(-log2(step / baseStep(for: preset)) / Self.range, -1), 1)
    }

    private func commit(_ preset: SlidePreset) {
        // Snap to the preset's own step near the middle.
        if abs(sensitivity) < 0.06 { sensitivity = 0 }
        model.set(.preset(preset, step: sensitivity == 0 ? nil : step(for: preset)), for: gesture)
    }

    private func caption(for preset: SlidePreset) -> String {
        let step = step(for: preset)
        if let levels = preset.levels {
            let centimetres = (Double(levels) * step / 10).formatted(.number.precision(.fractionLength(1)))
            return String(localized: "Whole range in about \(centimetres) cm")
        }
        let millimetres = step.formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "One step every \(millimetres) mm")
    }
}

// MARK: - General settings

private struct GeneralSettingsBar: View {
    @ObservedObject var model: GestureEditorModel

    var body: some View {
        HStack(spacing: 24) {
            Toggle("Haptic feedback", isOn: Binding(
                get: { model.settings.hapticFeedback },
                set: { model.setHapticFeedback($0) }
            ))

            HStack(spacing: 12) {
                Text("Natural scrolling")
                    .foregroundStyle(.secondary)
                ForEach(DeviceKind.allCases, id: \.self) { device in
                    Toggle(device == .trackpad ? "Trackpad" : "Mouse", isOn: Binding(
                        get: { model.naturalScrolling(for: device) },
                        set: { model.setNaturalScrolling($0, for: device) }
                    ))
                }
            }

            Spacer(minLength: 0)

            Picker("Dominant hand", selection: Binding(
                get: { model.settings.recognizer.dominantHand },
                set: { model.setDominantHand($0) }
            )) {
                Text("Right").tag(Hand.right)
                Text("Left").tag(Hand.left)
            }
            .fixedSize()
        }
        .toggleStyle(.checkbox)
        .disabled(!model.isEditable)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
