import SwiftUI

/// Einfaches Fließlayout für Auswahl-Chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

struct Chip: View {
    let title: String
    let isSelected: Bool
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(Capsule().fill(isSelected ? tint : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Einfachauswahl mit Abwahl durch erneutes Tippen
struct SingleChipPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T?
    let label: (T) -> String
    var tint: Color = Theme.accent

    var body: some View {
        FlowLayout {
            ForEach(options, id: \.self) { o in
                Chip(title: label(o), isSelected: selection == o, tint: tint) {
                    selection = selection == o ? nil : o
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Mehrfachauswahl
struct MultiChipPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: Set<T>
    let label: (T) -> String
    var tint: Color = Theme.accent

    var body: some View {
        FlowLayout {
            ForEach(options, id: \.self) { o in
                Chip(title: label(o), isSelected: selection.contains(o), tint: tint) {
                    if selection.contains(o) { selection.remove(o) } else { selection.insert(o) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
