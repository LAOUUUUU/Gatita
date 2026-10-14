//
//  QuickPanel.swift
//  Gatita
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// The quick panel: a floating Gatita box, like Spotlight, that opens over any app with ⌃⌘G. Ask, read the
/// answer, and press Escape. "Open in Gatita" keeps the question and answer as a saved chat.
@Observable
@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()
    static let width: CGFloat = 660

    @ObservationIgnored private var panel: QuickPanelWindow?
    @ObservationIgnored private var model: QuickPanelModel?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var doubleTap: CommandDoubleTap?
    /// The screenshot picker while it is on screen.
    @ObservationIgnored private var selection: ScreenSelection?
    /// Whether pressing ⌘ twice works now, for Settings.
    private(set) var doubleTapStatus: CommandDoubleTap.Status = .off
    /// Brings the main window back, even after it was closed. Set by the app, which can open windows.
    @ObservationIgnored var openMainWindow: () -> Void = {}

    /// Registers ⌃⌘G once, and starts watching for ⌘ pressed twice when that is on. Safe to call each time a
    /// window appears.
    func start(viewModel: ChatViewModel) {
        // Tests run inside the app; they must not watch keys or bring up permission prompts.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // macOS is asked for Input Monitoring once on its own. A Debug build loses the permission each time it is
        // rebuilt, and asking on every launch would nag, so after that Settings shows how to turn it back on.
        let askedKey = "askedForInputMonitoring"
        let ask = !UserDefaults.standard.bool(forKey: askedKey)
        UserDefaults.standard.set(true, forKey: askedKey)
        setDoubleCommand(viewModel.doubleCommandOpensPanel, viewModel: viewModel, ask: ask)
        guard hotKey == nil else { return }
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_G, modifiers: cmdKey | controlKey) { [weak self] in
            self?.toggle(viewModel)
        }
        if hotKey == nil {
            viewModel.log.info("the quick panel shortcut is taken by another app")
        }
    }

    /// Turns "press ⌘ twice" on or off. With `ask`, macOS asks for Input Monitoring if Gatita does not have it.
    func setDoubleCommand(_ on: Bool, viewModel: ChatViewModel, ask: Bool = true) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if on {
            let watcher = doubleTap ?? CommandDoubleTap { [weak self] in self?.doubleCommand(viewModel) }
            doubleTap = watcher
            watcher.start(ask: ask)
            if watcher.status == .needsPermission {
                viewModel.log.info("press ⌘ twice needs Input Monitoring permission")
            }
        } else {
            doubleTap?.stop()
        }
        refreshStatus()
    }

    /// Reads the watcher's status again, such as after permission was given in System Settings.
    func refreshStatus() {
        if doubleTap?.status == .needsPermission { doubleTap?.start() }
        doubleTapStatus = doubleTap?.status ?? .off
    }

    /// ⌘ pressed twice. During a screenshot it skips the screenshot. Otherwise it closes the panel when it is open,
    /// or opens it, starting the screenshot picker when that is on (as Claude's quick entry does).
    func doubleCommand(_ viewModel: ChatViewModel) {
        if let selection {
            selection.finish(.cancelled)
        } else if let panel, panel.isVisible {
            hide()
        } else {
            show(viewModel)
            if viewModel.doubleCommandTakesScreenshot { startScreenshot(viewModel) }
        }
    }

    /// Shows the panel and, over the screens, Gatita's screenshot picker: drag an area or click a window. The panel
    /// stays on screen and is left out of the picture. Without Screen Recording permission the panel says so instead.
    func startScreenshot(_ viewModel: ChatViewModel) {
        guard selection == nil else { return }
        if panel?.isVisible != true { show(viewModel) }
        guard let model else { return }
        guard ScreenCapture.isAllowed else {
            // Ask macOS once on its own; after that the panel's note opens the right page.
            let askedKey = "askedForScreenRecording"
            if !UserDefaults.standard.bool(forKey: askedKey) {
                UserDefaults.standard.set(true, forKey: askedKey)
                ScreenCapture.requestPermission()
            }
            model.needsScreenPermission = true
            return
        }
        model.needsScreenPermission = false
        let picker = ScreenSelection(panelFrame: { [weak self] in self?.panel?.frame }) { [weak self] result in
            guard let self else { return }
            self.selection = nil
            self.panel?.makeKeyAndOrderFront(nil)
            model.focusRequests += 1
            let target: ScreenCapture.Target
            switch result {
            case .area(let rect): target = .area(rect)
            case .window(let id): target = .window(id)
            case .cancelled: return
            }
            model.isCapturing = true
            Task {
                if let shot = await ScreenCapture.capture(target) {
                    model.attach(shot)
                    viewModel.analytics.count("quick_panel_screenshot")
                } else {
                    viewModel.log.info("quick panel screenshot failed")
                }
                model.isCapturing = false
            }
        }
        selection = picker
        picker.begin()
    }

    func toggle(_ viewModel: ChatViewModel) {
        if let panel, panel.isVisible {
            hide()
        } else {
            show(viewModel)
        }
    }

    /// Opens the panel with text selected in another app attached, from "Ask Gatita" in the Services menu.
    func show(_ viewModel: ChatViewModel, selection: String) {
        show(viewModel)
        model?.selection = String(selection.prefix(20_000))
        NSApp.activate()
    }

    func show(_ viewModel: ChatViewModel) {
        let model = self.model ?? QuickPanelModel(viewModel: viewModel)
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        if !panel.isVisible {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let top = screen.maxY - screen.height * 0.22
            panel.setFrame(NSRect(x: screen.midX - Self.width / 2, y: top - panel.frame.height,
                                  width: Self.width, height: panel.frame.height), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        model.focusRequests += 1
        viewModel.analytics.count("quick_panel")
    }

    func hide() {
        selection?.finish(.cancelled)
        panel?.orderOut(nil)
    }

    private func makePanel(model: QuickPanelModel) -> QuickPanelWindow {
        let panel = QuickPanelWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120))
        let view = QuickPanelView(model: model,
                                  onClose: { [weak self] in self?.hide() },
                                  onOpenInApp: { [weak self] in
                                      model.openInApp()
                                      self?.hide()
                                      self?.openMainWindow()
                                      NSApp.activate()
                                  },
                                  onResize: { [weak panel] height in panel?.keepTop(height: height) })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}

/// A borderless floating panel that takes typing without bringing Gatita's main window forward.
final class QuickPanelWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape closes the panel.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// Grows or shrinks to the content's height with its top edge where it was, as Spotlight does.
    func keepTop(height: CGFloat) {
        let height = ceil(height)
        guard abs(frame.height - height) > 0.5 else { return }
        var next = frame
        next.origin.y = frame.maxY - height
        next.size.height = height
        setFrame(next, display: true, animate: false)
    }
}

/// What the quick panel asks and shows. One question and one answer at a time.
@Observable
@MainActor
final class QuickPanelModel {
    var question = ""
    private(set) var asked = ""
    private(set) var answer = ""
    private(set) var isStreaming = false
    private(set) var error: String?
    /// Sends the clipboard's text along as context.
    var useClipboard = false
    /// Text selected in another app, sent with the next question. From "Ask Gatita" in the Services menu.
    var selection: String?
    /// Screenshots to send with the next question. Each shows as a thumbnail that can be taken out.
    private(set) var images: [ChatImage] = []
    /// True when a screenshot was asked for but Screen Recording is not allowed.
    var needsScreenPermission = false
    /// True while a screenshot is being taken, after the area or window was picked.
    var isCapturing = false
    var skillID = Skills.none
    /// Bumped each time the panel opens, so the view puts the cursor in the box.
    var focusRequests = 0
    let viewModel: ChatViewModel
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by each question and by reset, so a reply that was replaced can't write into the panel.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sentContext = ""
    private(set) var sentImages: [ChatImage] = []

    func attach(_ image: ChatImage) {
        images.append(image)
        needsScreenPermission = false
    }

    func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        images.remove(at: index)
    }

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    var clipboardPreview: String? {
        guard let text = Clipboard.text()?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }

    func ask() {
        var text = QuickPanelContext.question(typed: question, hasSelection: selection != nil)
        if text.isEmpty, !images.isEmpty { text = "What is in this screenshot?" }
        guard !text.isEmpty, !isStreaming else { return }
        guard viewModel.connectivity.isOnline else {
            error = NoInternet.headline + " " + NoInternet.detail
            return
        }
        guard let client = viewModel.quickPanelClient(skillID: skillID) else {
            error = "Add your Gatita API key in Settings first."
            return
        }
        error = nil
        answer = ""
        asked = text
        question = ""
        isStreaming = true
        let clip = useClipboard ? Clipboard.text().map { String($0.prefix(20_000)) } : nil
        sentContext = QuickPanelContext.text(selected: selection, clipboard: clip)
        selection = nil
        // The clipboard goes with one question only, so something copied later is never sent by mistake.
        useClipboard = false
        sentImages = images
        images = []
        let message = ChatMessage(role: "user", content: text, attachedContext: sentContext,
                                  images: sentImages.isEmpty ? nil : sentImages)
        generation += 1
        let mine = generation
        task = Task {
            var safetyStopped = false
            var failure: String?
            do {
                try await client.stream(messages: [message]) { event in
                    guard self.generation == mine else { return }
                    switch event {
                    case .text(let piece): self.answer += piece
                    case .safetyStop: safetyStopped = true
                    default: break
                    }
                }
            } catch {
                if !Task.isCancelled, (error as? URLError)?.code != .cancelled {
                    failure = NoInternet.matches(error, online: self.viewModel.connectivity.isOnline)
                        ? NoInternet.headline
                        : error.localizedDescription
                }
            }
            guard self.generation == mine else { return }
            self.error = QuickAnswer.problem(answer: self.answer, error: failure, safetyStopped: safetyStopped,
                                             stopped: Task.isCancelled)
            self.isStreaming = false
        }
    }

    func stop() {
        task?.cancel()
    }

    /// Clears the answer for a new question.
    func reset() {
        stop()
        generation += 1
        isStreaming = false
        asked = ""
        answer = ""
        error = nil
        sentImages = []
    }

    /// Keeps the question and answer as a saved chat in Gatita Chat, and opens it.
    func openInApp() {
        guard !asked.isEmpty else { return }
        viewModel.adoptQuickChat(question: ChatMessage(role: "user", content: asked, attachedContext: sentContext,
                                                       images: sentImages.isEmpty ? nil : sentImages),
                                 answer: answer)
        reset()
    }
}

/// What goes with a quick-panel question: the text selected in another app and the clipboard, each in a fence.
nonisolated enum QuickPanelContext {
    static func text(selected: String?, clipboard: String?) -> String {
        var parts: [String] = []
        if let selected, !selected.isEmpty { parts.append("The text the user selected:\n```\n\(selected)\n```") }
        if let clipboard, !clipboard.isEmpty { parts.append("The user's clipboard:\n```\n\(clipboard)\n```") }
        return parts.joined(separator: "\n\n")
    }

    /// The question as typed, or "Explain this text." when only a selection was sent.
    static func question(typed: String, hasSelection: Bool) -> String {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty && hasSelection ? "Explain this text." : typed
    }
}

/// What the quick panel says under a reply that has no answer, or was cut short. Kept apart so it can be tested.
nonisolated enum QuickAnswer {
    static func problem(answer: String, error: String?, safetyStopped: Bool, stopped: Bool) -> String? {
        if let error { return error }
        if safetyStopped { return "Gatita stopped this reply for safety." }
        guard answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return stopped ? "Stopped." : "Gatita ended the reply without writing an answer."
    }
}

/// The quick panel's look: Gatita's near-black card with an orange accent, rounded like the prompt box.
struct QuickPanelView: View {
    @Bindable var model: QuickPanelModel
    let onClose: () -> Void
    let onOpenInApp: () -> Void
    let onResize: (CGFloat) -> Void
    @FocusState private var focused: Bool
    @State private var copied = false
    /// The skill list, drawn inside the panel: a menu would be cut off by the panel's edge.
    @State private var showingSkills = false
    /// The screenshot shown large, after a click on its thumbnail.
    @State private var previewIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
            if let selection = model.selection {
                selectionChip(selection)
            }
            if !model.images.isEmpty || model.needsScreenPermission || model.isCapturing {
                attachmentRow
            }
            if showingSkills {
                Divider().overlay(Color.white.opacity(0.06))
                skillList
            }
            if model.isStreaming || !model.answer.isEmpty || model.error != nil {
                Divider().overlay(Color.white.opacity(0.06))
                answerArea
                Divider().overlay(Color.white.opacity(0.06))
                footer
            }
        }
        .frame(width: QuickPanelController.width)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onResize($0) }
        .preferredColorScheme(.dark)
        .onExitCommand(perform: onClose)
        .onChange(of: model.focusRequests, initial: true) { _, _ in focused = true }
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image("GatitaLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.accent)
            TextField(model.selection != nil ? "Ask about the selected text, or press Return to explain it"
                      : model.images.isEmpty
                      ? (model.asked.isEmpty ? "Ask Gatita anything" : "Ask a follow-up in a new question")
                      : "Ask about the screenshot",
                      text: $model.question)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit(model.ask)
            if model.isStreaming {
                Button(action: model.stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                optionsMenu
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// The screenshot button, the clipboard switch, and the skill.
    private var optionsMenu: some View {
        HStack(spacing: 8) {
            Button {
                QuickPanelController.shared.startScreenshot(model.viewModel)
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.surface.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help("Take a screenshot: drag over an area, or click a window. Escape skips it.")

            Button {
                model.useClipboard.toggle()
            } label: {
                Image(systemName: model.useClipboard ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(model.useClipboard ? Theme.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(model.useClipboard ? Theme.accent.opacity(0.15) : Theme.surface.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help(model.clipboardPreview.map { "Send the clipboard along: \($0)" } ?? "The clipboard has no text")

            Button {
                showingSkills.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(model.viewModel.skills.first { $0.id == model.skillID }?.name ?? "Skill")
                        .font(.caption.weight(.medium))
                    Image(systemName: showingSkills ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(model.skillID == Skills.none ? .secondary : Theme.accent)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Theme.surface.opacity(0.6)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Pick a skill")
        }
    }

    /// The text from another app that goes with the next question, with a button to take it out.
    private func selectionChip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "text.quote")
                .foregroundStyle(Theme.accent)
            Text(text.replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                model.selection = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Don't send this text")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface.opacity(0.6)))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    /// The screenshots to send, each with a button to take it out, or a note when Screen Recording is not allowed.
    private var attachmentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.needsScreenPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Screenshots need Screen Recording permission. Turn Gatita on in the list, then try again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Open Screen Recording") {
                        ScreenCapture.requestPermission()
                        ScreenCapture.openPrivacySettings()
                    }
                    .buttonStyle(GatitaButtonStyle(.primary))
                    .controlSize(.small)
                }
            }
            if model.isCapturing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Taking the screenshot…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            if !model.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.images.enumerated()), id: \.offset) { index, image in
                            ImageThumbnail(data: image.data, side: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(previewIndex == index ? Theme.accent : Color.white.opacity(0.12),
                                            lineWidth: previewIndex == index ? 2 : 1))
                                .onTapGesture { previewIndex = previewIndex == index ? nil : index }
                                .help("Click to see it larger")
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        previewIndex = nil
                                        model.removeImage(at: index)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.black.opacity(0.75)))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                    .help("Take this screenshot out")
                                }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
                if let index = previewIndex, model.images.indices.contains(index),
                   let picture = NSImage(data: model.images[index].data) {
                    Image(nsImage: picture)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1)))
                        .onTapGesture { previewIndex = nil }
                        .help("Click to close")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var skillList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                GatitaMenuRow(item: GatitaMenuItem(title: "No skill", isSelected: model.skillID == Skills.none) {}) {
                    model.skillID = Skills.none
                    showingSkills = false
                }
                ForEach(model.viewModel.skills) { skill in
                    GatitaMenuRow(item: GatitaMenuItem(title: skill.name, subtitle: "/" + skill.id,
                                                       isSelected: model.skillID == skill.id) {}) {
                        model.skillID = skill.id
                        showingSkills = false
                        focused = true
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 260)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var answerArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.asked)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !model.answer.isEmpty {
                    MarkdownText(source: model.answer)
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                } else if model.answer.isEmpty {
                    WaveDots(size: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("esc to close")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                Clipboard.copy(model.answer)
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(GatitaButtonStyle(.secondary))
            .disabled(model.answer.isEmpty)
            Button("Open in Gatita", action: onOpenInApp)
                .buttonStyle(GatitaButtonStyle(.primary))
                .disabled(model.isStreaming || model.answer.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: model.answer) { _, _ in copied = false }
    }
}
#endif

#if os(macOS)
/// Starts the quick panel's shortcut when the main window first appears, and tells the panel how to bring the
/// main window back: the one that is open, or a new one when it was closed.
struct QuickPanelStarter: ViewModifier {
    let viewModel: ChatViewModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            let controller = QuickPanelController.shared
            controller.openMainWindow = {
                if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            }
            controller.start(viewModel: viewModel)
        }
    }
}
#endif
