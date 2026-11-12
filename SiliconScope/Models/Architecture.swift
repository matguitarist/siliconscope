import SwiftUI

/// What CPU architecture(s) a binary supports, or is currently running as.
enum Architecture: String, CaseIterable, Comparable {
    case intel
    case universal
    case appleSilicon
    case unknown

    /// Sort order that surfaces the most actionable items (Intel-only) first.
    private static let sortOrder: [Architecture] = [.intel, .universal, .appleSilicon, .unknown]

    static func < (lhs: Architecture, rhs: Architecture) -> Bool {
        guard let l = sortOrder.firstIndex(of: lhs), let r = sortOrder.firstIndex(of: rhs) else { return false }
        return l < r
    }

    var label: String {
        switch self {
        case .appleSilicon: return "Apple Silicon"
        case .intel: return "Intel"
        case .universal: return "Universal"
        case .unknown: return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .appleSilicon: return "cpu"
        case .intel: return "exclamationmark.triangle.fill"
        case .universal: return "checkmark.seal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .appleSilicon: return .green
        case .intel: return .orange
        case .universal: return .blue
        case .unknown: return .gray
        }
    }
}
