import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    PageHeader(title: "Services", subtitle: "Lokalweb-owned nginx, Apache, PHP, and database runtimes.")
                    Spacer()
                    Button { model.anyRunning ? model.stopAll() : model.startAll() } label: {
                        Label(model.anyRunning ? "Stop All" : "Start All", systemImage: model.anyRunning ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.anyRunning ? .red : .accentColor)
                    .disabled(model.isBusy)
                }

                if !model.missingRuntimeFormulae.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Runtime setup required", systemImage: "shippingbox")
                            .font(.headline)
                        Text("Missing: \(model.missingRuntimeFormulae.joined(separator: ", ")). Lokalweb installs these with Homebrew so they remain independent from MAMP.")
                            .foregroundStyle(.secondary)
                        Button("Install Missing Runtimes") { model.installMissingRuntimes() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || model.binaries.brew == nil)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }

                ForEach(ManagedService.allCases) { service in
                    HStack(spacing: 16) {
                        Image(systemName: icon(service)).font(.title).foregroundStyle(.tint).frame(width: 38)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(service.rawValue).font(.headline)
                            Text(binaryPath(service) ?? "Not installed")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        ServiceBadge(state: model.serviceStates[service] ?? unavailableState(service))
                    }
                    .padding(18)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("PHP compatibility").font(.title2.bold())
                    ForEach(model.phpDiagnostics) { diagnostic in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: diagnostic.installed ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(diagnostic.installed ? .green : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(RuntimeConfiguration.phpLabel(for: diagnostic.formula)).font(.headline)
                                Text(diagnostic.version.map { "Installed version \($0)" } ?? "Not installed")
                                    .font(.caption).foregroundStyle(.secondary)
                                if diagnostic.installed && !diagnostic.missingRecommendedExtensions.isEmpty {
                                    Text("Missing common WordPress extensions: \(diagnostic.missingRecommendedExtensions.joined(separator: ", "))")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                HStack(spacing: 14) {
                    Image(systemName: "w.circle").font(.title).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WP-CLI").font(.headline)
                        Text(model.binaries.wpCLI ?? "Optional WordPress command-line tools are not installed.")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    if model.binaries.wpCLI == nil {
                        Button("Install WP-CLI") { model.installWordPressTools() }
                            .disabled(model.isBusy || model.binaries.brew == nil)
                    } else {
                        Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .padding(18)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

                Text("Lokalweb never calls `brew services`. Each process uses Lokalweb-specific configuration and PID files, which prevents service controls from affecting unrelated projects.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }

    private func binaryPath(_ service: ManagedService) -> String? {
        switch service {
        case .webServer: return model.binaries.nginx
        case .apache: return model.binaries.apache
        case .php: return model.binaries.phpFPM
        case .database: return model.binaries.mariaDBServer
        }
    }

    private func unavailableState(_ service: ManagedService) -> ServiceState {
        binaryPath(service) == nil ? .unavailable(service.rawValue) : .stopped
    }

    private func icon(_ service: ManagedService) -> String {
        switch service {
        case .webServer: return "network"
        case .apache: return "server.rack"
        case .php: return "chevron.left.forwardslash.chevron.right"
        case .database: return "cylinder.split.1x2"
        }
    }
}
