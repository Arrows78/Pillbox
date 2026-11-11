import Foundation

/// Localised string for text built in code (SwiftUI literals localise themselves).
func localized(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func localized(_ key: String, _ args: CVarArg...) -> String { String(format: NSLocalizedString(key, comment: ""), arguments: args) }
