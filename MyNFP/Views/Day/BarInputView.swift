import SwiftUI
import NFPCore

/// Eingabe für eine Zusatzleiste, abhängig von ihrem Typ.
struct BarInputView: View {
    let bar: BarDefinition
    @Binding var value: BarValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(bar.name, systemImage: bar.icon ?? "square.grid.2x2")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            switch bar.kind {
            case .singleChoice, .intensity:
                let options = bar.kind == .intensity ? BarKind.intensityLevels : bar.options
                SingleChipPicker(options: options, selection: Binding(
                    get: { value.selections.first },
                    set: { value.selections = $0.map { [$0] } ?? [] }
                ), label: { $0 })
            case .multiChoice:
                MultiChipPicker(options: bar.options, selection: Binding(
                    get: { Set(value.selections) },
                    set: { new in value.selections = bar.options.filter { new.contains($0) } }
                ), label: { $0 })
            case .textValue, .textIcon:
                TextField("Eingabe", text: Binding(
                    get: { value.text ?? "" },
                    set: { value.text = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            case .sliderRedGreen, .sliderGreenRed:
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { n in
                        Button {
                            value.number = value.number == n ? nil : n
                        } label: {
                            Text("\(n)")
                                .font(.headline)
                                .frame(width: 40, height: 40)
                                .foregroundStyle(value.number == n ? Color.white : Color.primary)
                                .background(Circle().fill(value.number == n
                                                          ? Theme.sliderColor(n, redToGreen: bar.kind == .sliderRedGreen)
                                                          : Theme.sliderColor(n, redToGreen: bar.kind == .sliderRedGreen).opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            case .goalReached, .done, .takenYes, .takenIcon:
                SingleChipPicker(options: [true, false], selection: Binding(
                    get: { value.flag },
                    set: { value.flag = $0 }
                ), label: { $0 ? "ja" : "nein" })
            }
        }
    }
}
