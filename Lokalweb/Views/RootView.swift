import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case sites = "Sites"
    case services = "Services"
    case logs = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .sites: return "globe"
        case .services: return "server.rack"
        case .logs: return "doc.text.magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $navigation.section) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Lokalweb")
            .safeAreaInset(edge: .bottom) {
                SidebarStatusView()
                    .environmentObject(model)
                    .padding(12)
            }
        } detail: {
            Group {
                switch navigation.section ?? .overview {
                case .overview: DashboardView()
                case .sites: SitesView()
                case .services: ServicesView()
                case .logs: LogsView()
                case .settings: SettingsView()
                }
            }
            .environmentObject(model)
        }
    }
}

private struct SidebarStatusView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(model.allRunning ? Color.green : model.anyRunning ? Color.orange : Color.secondary)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.allRunning ? "All services running" : model.anyRunning ? "Partially running" : "Services stopped")
                    .font(.caption.weight(.semibold))
                Text(model.activity)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
