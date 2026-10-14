//
//  GatitaChrome.swift
//  Gatita
//

import SwiftUI

/// The Gatita dialogs and menus open on one screen. SwiftUI gives Escape to the first button that has it, even a
/// hidden one, so a sheet's close button and the hidden Stop button step aside while any is open, and Escape
/// reaches the dialog or menu instead. A screen puts one in the environment; dialogs and menus claim it.
@Observable
@MainActor
final class EscapeClaims {
    private var holders: Set<UUID> = []

    var isClaimed: Bool { !holders.isEmpty }

    func set(_ holder: UUID, claimed: Bool) {
        if claimed { holders.insert(holder) } else { holders.remove(holder) }
    }
}

private struct EscapeClaim: ViewModifier {
    let active: Bool
    @Environment(EscapeClaims.self) private var claims: EscapeClaims?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, now in claims?.set(id, claimed: now) }
            .onDisappear { claims?.set(id, claimed: false) }
    }
}

extension View {
    /// Tells the screen's `EscapeClaims` that this view wants Escape while `active`.
    func claimsEscape(_ active: Bool) -> some View {
        modifier(EscapeClaim(active: active))
    }
}

/// The top of a Gatita sheet: its title on the left and a round close button on the right. Escape closes it too.
struct GatitaSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    /// Off while a dialog is open on the sheet, so Escape cancels the dialog instead of closing the sheet.
    var escapeCloses = true
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Color.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(escapeCloses ? .cancelAction : nil)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

/// The explanation under a group of settings. A section footer in a macOS list is one line high and cuts longer
/// text short, so the words go in a row of their own at the end of the section, which grows to fit.
struct SettingsNote: View {
    let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .listRowSeparator(.hidden)
    }
}

/// Tabs in Gatita's look: a dark capsule with the chosen tab as an orange pill. Replaces the system's segmented
/// control, which draws in the OS style.
struct GatitaTabs<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let chosen = option == selection
                Button {
                    withAnimation(.spring(duration: 0.25)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.callout.weight(chosen ? .semibold : .medium))
                        .foregroundStyle(chosen ? Color.white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if chosen {
                                Capsule().fill(Theme.accent).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface.opacity(0.8)))
        .overlay(Capsule().stroke(Color.white.opacity(0.06)))
    }
}

/// What a Gatita dialog asks: a title, a few words, and the button that does it.
struct GatitaDialogSpec {
    var icon: String? = nil
    let title: String
    var message: String? = nil
    let confirm: String
    var role: GatitaButtonStyle.Role = .primary
    /// Whether a tap outside the card cancels. Off for dialogs you type in, so a stray tap never loses the text.
    var closesOnOutsideTap = true
}

/// A dialog in Gatita's look, over a dimmed window: a dark card with a Cancel pill and an orange or red one.
/// It replaces the system's confirmation dialogs and alerts, which look out of place on the near-black app.
struct GatitaDialog<Content: View>: View {
    let spec: GatitaDialogSpec
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { if spec.closesOnOutsideTap { onCancel() } }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if let icon = spec.icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(spec.role == .destructive ? Color.red : Theme.accent)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill((spec.role == .destructive ? Color.red : Theme.accent).opacity(0.15)))
                    }
                    Text(spec.title)
                        .font(.headline)
                }
                if let message = spec.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GatitaButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                    Button(spec.confirm, action: onConfirm)
                        .buttonStyle(GatitaButtonStyle(spec.role))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 400, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(24)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}

extension View {
    /// Shows a Gatita dialog while `spec` is set. Cancel or a tap outside clears it; the confirm button runs
    /// `onConfirm` and then clears it.
    func gatitaDialog<Content: View>(_ spec: Binding<GatitaDialogSpec?>, onConfirm: @escaping () -> Void,
                                     @ViewBuilder content: () -> Content = { EmptyView() }) -> some View {
        let inner = content()
        return overlay {
            if let shown = spec.wrappedValue {
                GatitaDialog(spec: shown,
                             onCancel: { withAnimation(.easeOut(duration: 0.15)) { spec.wrappedValue = nil } },
                             onConfirm: {
                                 onConfirm()
                                 withAnimation(.easeOut(duration: 0.15)) { spec.wrappedValue = nil }
                             },
                             content: { inner })
            }
        }
        .animation(.spring(duration: 0.25), value: spec.wrappedValue?.title)
        .claimsEscape(spec.wrappedValue != nil)
    }
}
