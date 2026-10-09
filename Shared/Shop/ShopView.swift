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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Shop")
                    .font(.title2.weight(.semibold))
                Text("Everything here is free and bundled with the app. Adding one shows what it does first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Category", selection: $category) {
                    ForEach(ShopCategory.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
        .background(Theme.background)
        .confirmationDialog("Add this?",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible,
                            presenting: pending) { item in
            Button("Add \(item.name)") { add(item) }
        } message: { item in
            Text(Shop.permissions(of: item).joined(separator: "\n"))
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
                    .buttonStyle(.bordered)
            } else {
                Button("Get") { pending = item }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
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
