import SwiftUI

struct ArchitectureBadge: View {
    let architecture: Architecture
    var overrideLabel: String?

    var body: some View {
        Label(overrideLabel ?? architecture.label, systemImage: architecture.symbolName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(architecture.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(architecture.tint)
            .fixedSize()
    }
}

/// A stat pill. When `action` is provided it acts as a toggleable filter button;
/// otherwise it's purely informational.
struct SummaryChip: View {
    let count: Int
    let label: String
    let tint: Color
    var isSelected: Bool = false
    var action: (() -> Void)?
    @State private var isHovered = false

    private var fill: Color {
        if isSelected { return tint.opacity(isHovered ? 0.28 : 0.22) }
        return Color.secondary.opacity(isHovered ? 0.18 : 0.12)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        let chip = HStack(spacing: 6) {
            Text("\(count)")
                .font(.headline)
                .foregroundStyle(tint)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill, in: shape)
        .overlay(shape.stroke(isSelected ? tint : .clear, lineWidth: 1.5))

        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            chip
        }
    }
}
