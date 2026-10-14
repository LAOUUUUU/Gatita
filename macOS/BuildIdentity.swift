//
//  BuildIdentity.swift
//  Gatita
//

#if os(macOS)
import Foundation
import Security

/// Which build of Gatita is running, as macOS sees it. macOS keeps Input Monitoring and Screen Recording for one
/// code identity. A build signed ad hoc (with no certificate) is its own identity, so every rebuild loses both
/// permissions, and a "ask once, ever" flag then keeps the prompts from coming back.
nonisolated enum BuildIdentity {
    /// The running app's designated requirement, which is what macOS compares. For an ad-hoc build it holds the
    /// build's hash and changes on every rebuild; for a build signed with a certificate it stays the same.
    static func current() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    /// Whether to ask macOS for a permission again: it was never asked, or it was asked by a build with another
    /// identity. When this build's identity can't be read, a permission is asked for only once.
    static func shouldAsk(lastAskedFor: String?, current: String?) -> Bool {
        guard let current else { return lastAskedFor == nil }
        return lastAskedFor != current
    }

    /// True when the permission called `key` should be asked for now, and remembers that this build asked.
    static func askOnce(_ key: String, defaults: UserDefaults = .standard, current: String? = BuildIdentity.current()) -> Bool {
        let ask = shouldAsk(lastAskedFor: defaults.string(forKey: key), current: current)
        defaults.set(current ?? "unknown", forKey: key)
        return ask
    }
}
#endif
