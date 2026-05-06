import SwiftUI

struct FilterBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Extension:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(".pdf", text: Binding(
                    get: { appState.filterExtension },
                    set: { appState.filterExtension = $0; appState.performSearch() }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Picker("Type", selection: Binding(
                    get: { appState.filterFileType },
                    set: { appState.filterFileType = $0; appState.performSearch() }
                )) {
                    ForEach(FileTypeFilter.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .frame(width: 120)

                Text("Size:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Min", value: Binding(
                    get: { appState.filterSizeMin },
                    set: { appState.filterSizeMin = $0; appState.performSearch() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                Text("-")
                TextField("Max", value: Binding(
                    get: { appState.filterSizeMax },
                    set: { appState.filterSizeMax = $0; appState.performSearch() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Text("Modified after:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: Binding(
                    get: { appState.filterModifiedAfter ?? Date.distantPast },
                    set: { appState.filterModifiedAfter = $0; appState.performSearch() }
                ), displayedComponents: .date)
                .labelsHidden()
                .frame(width: 120)

                Picker("Sort", selection: Binding(
                    get: { appState.sortBy },
                    set: { appState.sortBy = $0; appState.performSearch() }
                )) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.label).tag(field)
                    }
                }
                .frame(width: 90)

                Button(action: { appState.sortAscending.toggle(); appState.performSearch() }) {
                    Image(systemName: appState.sortAscending ? "arrow.up" : "arrow.down")
                }
                .buttonStyle(.plain)
                .help(appState.sortAscending ? "Ascending" : "Descending")

                if appState.isFiltering {
                    Button("Clear") { appState.clearFilters() }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}
