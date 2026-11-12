import SwiftUI

struct ProcessRow: View {
    let process: ProcessItem
    var onQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: process.isAppBundle ? "app.badge" : "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                Text(process.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text("\(process.id)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") {
                FileActions.revealInFinder(path: process.path)
            }
            Button("Copy Path") {
                FileActions.copyToPasteboard(process.path)
            }
            Divider()
            Button("Quit Process…", role: .destructive, action: onQuit)
        }
    }
}
