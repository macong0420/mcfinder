import SwiftUI

struct ResultRowView: View {
    let item: SearchResultItem
    let isSelected: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopyPath: () -> Void
    let onQuickLook: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: FileTypeDetector.systemIcon(for: URL(fileURLWithPath: item.path)))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(item.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(kindLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(sizeLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
                .monospacedDigit()

            Text(dateLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(count: 1, perform: onQuickLook)
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Show in Finder") { onReveal() }
            Button("Copy Path") { onCopyPath() }
            Divider()
            Button("Quick Look") { onQuickLook() }
        }
    }

    private var kindLabel: String {
        if item.isDirectory { return "Folder" }
        return FileTypeDetector.detect(extension: item.extension).rawValue
    }

    private var sizeLabel: String {
        if item.isDirectory {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(item.modifiedAt) || calendar.isDateInYesterday(item.modifiedAt) {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        }
        return formatter.string(from: item.modifiedAt)
    }
}
