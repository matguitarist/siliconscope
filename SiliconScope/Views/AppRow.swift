import SwiftUI

struct AppRow: View {
    @Environment(AppModel.self) private var model
    let app: AppItem

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(path: app.path, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(app.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if app.architecture == .intel, let state = model.check(for: app) {
                NativeCheckLabel(state: state)
                    .font(.caption)
            }
            if let version = app.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            AppActions(app: app)
        }
    }
}
