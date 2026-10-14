//
//  ShopView.swift
//  Gatita
//

import SwiftUI

/// Free connectors, plugins, and skills. Adding one shows what it does before it is added.
struct ShopView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var pending: ShopItem?
    @State private var message = ""
    @State private var category: ShopCategory = .plugins
    @State private var dialog: GatitaDialogSpec?
    /// Set when the shop is a sheet: the header then has a close button.
    var onClose: (() -> Void)? = nil

    private static let intro = "Everything here is free and bundled with the app. Adding one shows what it does first."

    var body: some View {
        VStack(spacing: 0) {
            if let onClose {
                GatitaSheetHeader(title: "Shop", subtitle: Self.intro, escapeCloses: dialog == nil, onClose: onClose)
            }
            list
        }
        .background(Theme.background)
        .gatitaDialog($dialog) {
            if let pending { add(pending) }
            pending = nil
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if onClose == nil {
                    Text("Shop")
                        .font(.title2.weight(.semibold))
                    Text(Self.intro)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                GatitaTabs(options: ShopCategory.allCases, selection: $category, title: \.title)
                Text(category.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Shop.items.filter { $0.kind == category.kind && HostPolicy.allows($0) }) { item in
                    itemRow(item)
                }

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// Asks before adding, and says what the item will be allowed to do.
    private func ask(_ item: ShopItem) {
        pending = item
        dialog = GatitaDialogSpec(icon: icon(for: item), title: "Add \(item.name)?",
                                  message: Shop.permissions(of: item).joined(separator: "\n"), confirm: "Add")
    }

    private func icon(for item: ShopItem) -> String {
        switch item.kind {
        case .plugin: "puzzlepiece.extension"
        case .skill: "slider.horizontal.3"
        case .connector: "point.3.connected.trianglepath.dotted"
        }
    }

    private func itemRow(_ item: ShopItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                Text(item.summary)
                    .font(.callout)
                ForEach(Shop.permissions(of: item), id: \.self) { line in
                    Text("• " + line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if isInstalled(item) {
                Button("Remove") { remove(item) }
                    .buttonStyle(GatitaButtonStyle(.secondary))
            } else {
                Button("Get") { ask(item) }
                    .buttonStyle(GatitaButtonStyle(.primary))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06)))
    }

    private func isInstalled(_ item: ShopItem) -> Bool {
        switch item.kind {
        case .connector:
            return viewModel.connectors.contains(item.connectorID ?? "")
        case .plugin, .skill:
            return Shop.isInstalled(item, in: Plugins.defaultDirectory)
        }
    }

    private func add(_ item: ShopItem) {
        do {
            switch item.kind {
            case .connector:
                viewModel.connectors.insert(item.connectorID ?? "")
            case .plugin, .skill:
                try Shop.install(item, into: Plugins.defaultDirectory)
                viewModel.reloadPlugins()
            }
            message = "Added \(item.name)."
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove(_ item: ShopItem) {
        do {
            switch item.kind {
            case .connector:
                viewModel.connectors.remove(item.connectorID ?? "")
            case .plugin, .skill:
                try Shop.remove(item, from: Plugins.defaultDirectory)
                viewModel.reloadPlugins()
            }
            message = "Removed \(item.name)."
        } catch {
            message = error.localizedDescription
        }
    }
}
