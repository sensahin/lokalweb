import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                PageHeader(title: "Settings", subtitle: "Networking, HTTPS, and the active PHP runtime.")
                    .padding(.bottom, 12)
            }

            Section("Network") {
                LabeledContent("HTTP port") {
                    portField($model.configuration.httpPort, accessibilityLabel: "HTTP port")
                }
                Toggle("Enable HTTPS", isOn: $model.configuration.httpsEnabled)
                if model.configuration.httpsEnabled {
                    LabeledContent("HTTPS port") {
                        portField($model.configuration.httpsPort, accessibilityLabel: "HTTPS port")
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(httpsIsReady ? "Trusted localhost certificate is ready." : "A trusted localhost certificate must be prepared before services can start.")
                            Text("Certificate setup uses mkcert and the login keychain; it never changes MAMP certificates.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(httpsIsReady ? "Refresh Certificate" : "Prepare HTTPS") { model.prepareHTTPS() }
                            .disabled(model.anyRunning || model.isBusy)
                    }
                }
                LabeledContent("PHP-FPM port") {
                    portField($model.configuration.phpPort, accessibilityLabel: "PHP-FPM port")
                }
                LabeledContent("Apache backend port") {
                    portField($model.configuration.apachePort, accessibilityLabel: "Apache backend port")
                }
                Text("Apache uses this private loopback port only for sites assigned to Apache; public site URLs continue to use the HTTP or HTTPS port above.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("MariaDB port") {
                    portField($model.configuration.databasePort, accessibilityLabel: "MariaDB port")
                }
            }

            Section("PHP") {
                Picker("Homebrew formula", selection: $model.configuration.phpFormula) {
                    ForEach(RuntimeConfiguration.supportedPHPFormulae, id: \.self) { formula in
                        Text(RuntimeConfiguration.phpLabel(for: formula)).tag(formula)
                    }
                }
                Text("PHP 8.3 is the conservative default. A site can override this value from its Manage screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Lifecycle and support") {
                Toggle("Stop Lokalweb services when the app quits", isOn: $model.configuration.stopServicesOnQuit)
                Text("Closing the dashboard keeps Lokalweb available in the menu bar. This setting determines the recommended choice when you explicitly quit the app.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnostic report")
                        Text("Exports runtime paths, service state, site configuration, PHP modules, and recent Lokalweb logs. It never reads wp-config.php passwords or database content.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Export Diagnostics…") { exportDiagnostics() }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text("App data: \(model.paths.root.path)")
                    Text("Runtime data: \(model.paths.runtimeRoot.path)")
                }
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("Save Settings") { model.saveConfiguration() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.anyRunning)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private var httpsIsReady: Bool {
        FileManager.default.fileExists(atPath: model.paths.certificate.path)
            && FileManager.default.fileExists(atPath: model.paths.certificateKey.path)
    }

    private func portField(_ value: Binding<Int>, accessibilityLabel: String) -> some View {
        TextField("", value: value, format: .number.grouping(.never))
            .labelsHidden()
            .frame(width: 76)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(accessibilityLabel)
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "lokalweb-diagnostics.txt"
        panel.canCreateDirectories = true
        panel.prompt = "Export Diagnostics"
        if panel.runModal() == .OK, let url = panel.url {
            model.exportDiagnostics(to: url)
        }
    }
}
