//
//  PromptField.swift
//  Gatita
//

#if os(macOS)
import AppKit
import SwiftUI

/// The prompt box on the Mac: a multi-line text view that also takes files dropped on it.
/// A SwiftUI TextField hands a dropped file to its text view as a path, so the input bar never sees the drop.
struct PromptField: NSViewRepresentable {
    @Binding var text: String
    /// Return sends. Shift-Return adds a line.
    let onReturn: () -> Void
    let onDropFiles: ([URL]) -> Void
    /// A paste of `DroppedFile.pasteThreshold` characters or more. The text goes to an attachment, not the box.
    let onLargePaste: (String) -> Void
    /// True while a file is dragged over the field, so the input bar can highlight.
    let onDragTargeted: (Bool) -> Void

    /// The box grows to this many lines, then scrolls.
    private static let maxLines = 10

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? PromptTextView else { return }
        context.coordinator.text = $text
        textView.onReturn = onReturn
        textView.onDropFiles = onDropFiles
        textView.onLargePaste = onLargePaste
        textView.onDragTargeted = onDragTargeted
        if textView.string != text {
            textView.string = text
        }
    }

    /// As tall as its text, from one line up to `maxLines`.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let textView = scroll.documentView as? PromptTextView,
              let container = textView.textContainer,
              let layout = textView.layoutManager else { return nil }
        let width = max(proposal.width ?? 300, 80)
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let font = textView.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = layout.defaultLineHeight(for: font)
        let usedHeight = layout.usedRect(for: container).height
        let lines = min(max(Int(ceil(usedHeight / lineHeight)), 1), Self.maxLines)
        let inset = textView.textContainerInset.height * 2
        return CGSize(width: width, height: CGFloat(lines) * lineHeight + inset)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// The text view behind the prompt box. Return and file drops are handled here, before the text view inserts anything.
final class PromptTextView: NSTextView {
    var onReturn: (() -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    var onLargePaste: ((String) -> Void)?
    var onDragTargeted: ((Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        // While an input method is composing text, Return belongs to the input method.
        if isReturn && !event.modifierFlags.contains(.shift) && !hasMarkedText() {
            onReturn?()
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            guard pasted.count >= DroppedFile.pasteThreshold, let onLargePaste else { return super.paste(sender) }
            onLargePaste(pasted)
            return
        }
        // A picture on the clipboard, such as a screenshot, is attached like a dropped file.
        guard let picture = pictureFile(on: .general) else { return super.paste(sender) }
        attachPictureFile(picture)
    }

    private func droppedFileURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// A picture dragged from a web page or an app has no file behind it. It is saved to a temporary PNG
    /// so it can be read like any other dropped file.
    private func pictureFile(on pasteboard: NSPasteboard) -> URL? {
        guard let image = (pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Picture \(UUID().uuidString.prefix(6)).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return url
    }

    /// Hands the picture to the input bar, then removes the temporary copy. The input bar reads it right away.
    private func attachPictureFile(_ url: URL) {
        onDropFiles?([url])
        try? FileManager.default.removeItem(at: url)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let carriesPicture = sender.draggingPasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
        guard carriesPicture || !droppedFileURLs(sender).isEmpty else { return super.draggingEntered(sender) }
        onDragTargeted?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargeted?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !droppedFileURLs(sender).isEmpty
            || sender.draggingPasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
            || super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragTargeted?(false)
        let urls = droppedFileURLs(sender)
        if !urls.isEmpty {
            onDropFiles?(urls)
            return true
        }
        if let picture = pictureFile(on: sender.draggingPasteboard) {
            attachPictureFile(picture)
            return true
        }
        return super.performDragOperation(sender)
    }
}
#endif
