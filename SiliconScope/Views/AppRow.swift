import SwiftUI

struct AppRow: View {
    let app: AppItem

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(app.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let version = app.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
            }
            Button("Reveal in Finder") {
                FileActions.revealInFinder(path: app.path)
            }
            Button("Copy Path") {
                FileActions.copyToPasteboard(app.path)
            }
        }
    }
}
