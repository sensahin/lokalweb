import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageHeader(title: "Logs", subtitle: "Recent nginx, Apache, PHP-FPM, and MariaDB output.")
                Spacer()
                Button("Reveal Logs") { model.revealLogs() }
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(model.logs)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
        }
        .padding(32)
    }
}
