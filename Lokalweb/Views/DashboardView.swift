import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    PageHeader(
                        title: "Local development, under control.",
                        subtitle: "A focused PHP and WordPress stack that belongs to Lokalweb."
                    )
                    Spacer()
                    controlButton
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(ManagedService.allCases) { service in
                        serviceCard(service)
                    }
                }

                HStack(spacing: 16) {
                    metricCard(value: "\(model.sites.count)", label: model.sites.count == 1 ? "configured site" : "configured sites", icon: "globe")
                    metricCard(value: ":\(model.configuration.httpPort)", label: "HTTP port", icon: "network")
                    metricCard(value: "\(model.phpRuntimePlan.instances.count)", label: "active PHP runtime plans", icon: "chevron.left.forwardslash.chevron.right")
                }

                if model.sites.isEmpty {
                    ContentUnavailableView(
                        "Add your first site",
                        systemImage: "folder.badge.plus",
                        description: Text("Choose an existing WordPress or PHP project folder from the Sites screen.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sites").font(.title2.bold())
                        ForEach(model.sites.prefix(5)) { site in
                            HStack {
                                Image(systemName: "globe").foregroundStyle(.tint)
                                VStack(alignment: .leading) {
                                    Text(site.name).fontWeight(.semibold)
                                    Text(site.url(configuration: model.configuration)?.absoluteString ?? site.slug)
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Text("\(site.webServer.label) · \(RuntimeConfiguration.phpLabel(for: site.phpFormula ?? model.configuration.phpFormula))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Open") { model.open(site) }.disabled(!model.allRunning)
                            }
                            .padding(12)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(32)
        }
        .toolbar {
            Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        }
    }

    private var controlButton: some View {
        Button {
            model.anyRunning ? model.stopAll() : model.startAll()
        } label: {
            Label(model.anyRunning ? "Stop All" : "Start All", systemImage: model.anyRunning ? "stop.fill" : "play.fill")
                .frame(minWidth: 90)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(model.anyRunning ? .red : .accentColor)
        .disabled(model.isBusy)
    }

    private func serviceCard(_ service: ManagedService) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: serviceIcon(service)).font(.title2).foregroundStyle(.tint)
                Spacer()
                ServiceBadge(state: model.serviceStates[service] ?? .stopped)
            }
            Text(service.rawValue).font(.headline)
            Text(serviceDetail(service)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metricCard(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading) {
                Text(value).font(.title3.bold()).lineLimit(1)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func serviceIcon(_ service: ManagedService) -> String {
        switch service {
        case .webServer: return "network"
        case .apache: return "server.rack"
        case .php: return "chevron.left.forwardslash.chevron.right"
        case .database: return "cylinder.split.1x2"
        }
    }

    private func serviceDetail(_ service: ManagedService) -> String {
        switch service {
        case .webServer: return "127.0.0.1:\(model.configuration.httpPort)"
        case .apache: return "Private backend · 127.0.0.1:\(model.configuration.apachePort)"
        case .php:
            return model.phpRuntimePlan.instances
                .map { "\(RuntimeConfiguration.phpLabel(for: $0.formula)) :\($0.port)" }
                .joined(separator: " · ")
        case .database: return "127.0.0.1:\(model.configuration.databasePort)"
        }
    }
}
