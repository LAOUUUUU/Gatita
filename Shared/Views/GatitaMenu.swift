//
//  GatitaMenu.swift
//  Gatita
//

import Observation
import SwiftUI

/// Gatita's own dropdown menus. The system's menus draw in the OS style (glass on recent macOS), which looks out of
/// place on the near-black app, so these draw a dark card like the prompt box's panels instead.
///
/// A screen adds `.gatitaMenuHost()` once at its root; any `GatitaMenuButton` inside it opens its menu there,
/// over everything, and a click outside or Escape closes it.
struct GatitaMenuItem: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var isSelected = false
    var isDestructive = false
    /// Draws a line above this item, to start a new group.
    var startsSection = false
    let action: () -> Void
}

/// Where a menu card goes, kept apart from the views so it can be tested.
nonisolated enum GatitaMenuLayout {
    static let gap: CGFloat = 6
    static let margin: CGFloat = 8

    /// The card's top-left corner: under the button when it fits, otherwise above it, and inside the window.
    static func origin(for card: CGSize, under button: CGRect, in window: CGSize, alignTrailing: Bool) -> CGPoint {
        let preferredX = alignTrailing ? button.maxX - card.width : button.minX
        let x = min(max(margin, preferredX), max(margin, window.width - card.width - margin))
        let below = button.maxY + gap
        let y = below + card.height <= window.height - margin
            ? below
            : max(margin, button.minY - gap - card.height)
        return CGPoint(x: x, y: y)
    }
}

/// The menu on screen, if any. Shared through the environment by the host.
@Observable
@MainActor
final class GatitaMenuCenter {
    nonisolated static let space = "gatitaMenuHost"

    struct Menu: Identifiable {
        let id: String
        let title: String?
        let items: [GatitaMenuItem]
        let anchor: CGRect
        let alignTrailing: Bool
        let width: CGFloat
    }

    private(set) var menu: Menu?

    /// Opens the menu, or closes it when the same button opened the menu on screen.
    func toggle(_ menu: Menu) {
        self.menu = self.menu?.id == menu.id ? nil : menu
    }

    func dismiss() {
        menu = nil
    }
}

extension View {
    /// Lets the `GatitaMenuButton`s inside this view open their menus, drawn over this view.
    func gatitaMenuHost() -> some View {
        modifier(GatitaMenuHost())
    }
}

private struct GatitaMenuHost: ViewModifier {
    @State private var center = GatitaMenuCenter()
    @State private var cardSize: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: GatitaMenuCenter.space)
            .environment(center)
            .overlay {
                if let menu = center.menu {
                    GeometryReader { proxy in
                        let size = CGSize(width: menu.width, height: cardSize.height > 0 ? cardSize.height : 120)
                        let origin = GatitaMenuLayout.origin(for: size, under: menu.anchor, in: proxy.size,
                                                             alignTrailing: menu.alignTrailing)
                        ZStack(alignment: .topLeading) {
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture { center.dismiss() }
                            GatitaMenuCard(menu: menu, close: { center.dismiss() })
                                .frame(width: menu.width)
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                                .offset(x: origin.x, y: origin.y)
                                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        }
                    }
                    .id(menu.id)
                }
            }
            .animation(.easeOut(duration: 0.12), value: center.menu?.id)
            .claimsEscape(center.menu != nil)
    }
}

/// A button that opens a Gatita menu. The items are made when it is pressed, so they show the current choice.
struct GatitaMenuButton<Label: View>: View {
    let id: String
    var title: String? = nil
    var alignTrailing = true
    var width: CGFloat = 250
    let items: () -> [GatitaMenuItem]
    @ViewBuilder let label: Label
    @Environment(GatitaMenuCenter.self) private var center: GatitaMenuCenter?
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            center?.toggle(.init(id: id, title: title, items: items(), anchor: frame,
                                 alignTrailing: alignTrailing, width: width))
        } label: {
            label
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GatitaMenuCenter.space)) } action: { frame = $0 }
    }
}

/// The card: a small title, then one row per item. The chosen item has an orange check.
private struct GatitaMenuCard: View {
    let menu: GatitaMenuCenter.Menu
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = menu.title {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
            ForEach(menu.items) { item in
                if item.startsSection {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                }
                GatitaMenuRow(item: item) {
                    close()
                    item.action()
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.09)))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .background {
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}

/// One row of a Gatita menu. Also used for lists drawn in place, such as the quick panel's skills.
struct GatitaMenuRow: View {
    let item: GatitaMenuItem
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 9) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.isDestructive ? Color.red : item.isSelected ? Theme.accent : .secondary)
                        .frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.callout)
                        .foregroundStyle(item.isDestructive ? Color(red: 1, green: 0.45, blue: 0.45) : .primary)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if item.isSelected { return Theme.accent.opacity(hovering ? 0.2 : 0.14) }
        return hovering ? Color.white.opacity(0.07) : .clear
    }
}
