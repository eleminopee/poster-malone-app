import SwiftUI

struct ColumnVisibilityManager: View {
    @Environment(ColumnSettings.self) var columnSettings

    var body: some View {
        @Bindable var columnSettings = columnSettings

        List {
            ForEach(columnSettings.allOrdered) { config in
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .font(.caption)

                    Toggle(isOn: Binding(
                        get: { config.isVisible },
                        set: { _ in columnSettings.toggle(config.id) }
                    )) {
                        Text(config.id.rawValue)
                            .font(.body)
                    }
                }
            }
            .onMove { source, destination in
                columnSettings.move(from: source, to: destination)
            }
        }
        .frame(minHeight: 300)
        .scrollContentBackground(.hidden)
    }
}
