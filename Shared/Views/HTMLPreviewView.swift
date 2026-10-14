//
//  HTMLPreviewView.swift
//  Gatita
//

import SwiftUI
import WebKit

/// The block-everything content rule list, compiled once and shared by every preview.
@MainActor
enum PreviewRules {
    private static var compiled: WKContentRuleList?

    static func list() async -> WKContentRuleList? {
        if let compiled { return compiled }
        let list = try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "GatitaPreviewBlockAll", encodedContentRuleList: HTMLPreview.blockRules)
        compiled = list
        return list
    }
}

/// A sheet with a code block's page or picture, live. See `HTMLPreview` for what keeps it off the network.
struct HTMLPreviewSheet: View {
    let language: String
    let code: String
    @Environment(\.dismiss) private var dismiss
    @State private var rules: WKContentRuleList?
    @State private var ready = false

    var body: some View {
        VStack(spacing: 0) {
            GatitaSheetHeader(title: "Preview", subtitle: "Scripts run, and the network is blocked.", onClose: { dismiss() })
            Group {
                if ready, rules != nil {
                    PreviewWebView(html: HTMLPreview.document(language: language, code: code), rules: rules)
                } else if ready {
                    // Without the rules that block every load, the page is not shown at all.
                    Label("The preview could not start safely, so it is not shown.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding([.horizontal, .bottom], 16)
        }
        .background(Theme.background)
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 960, minHeight: 520, idealHeight: 680)
        #endif
        .task {
            rules = await PreviewRules.list()
            ready = true
        }
    }
}

/// The web view: nothing is stored between previews, every load is blocked, and links go nowhere.
struct PreviewWebView {
    let html: String
    let rules: WKContentRuleList?

    /// A configuration that keeps nothing and blocks every load.
    static func configuration(rules: WKContentRuleList?) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let rules { configuration.userContentController.add(rules) }
        return configuration
    }

    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: Self.configuration(rules: rules))
        view.navigationDelegate = coordinator
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            HTMLPreview.allowsNavigation(to: action.request.url) ? .allow : .cancel
        }
    }
}

#if os(macOS)
extension PreviewWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
extension PreviewWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
