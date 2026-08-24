import Foundation

enum MenuBarStatus: Equatable {
    case running
    case working
    case attention
    case partial
    case stopped

    static func resolve(
        isBusy: Bool,
        needsAttention: Bool,
        allRunning: Bool,
        anyRunning: Bool
    ) -> MenuBarStatus {
        if needsAttention { return .attention }
        if isBusy { return .working }
        if allRunning { return .running }
        if anyRunning { return .partial }
        return .stopped
    }

    var label: String {
        switch self {
        case .running: return "All services running"
        case .working: return "Working"
        case .attention: return "Needs attention"
        case .partial: return "Some services running"
        case .stopped: return "Services stopped"
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "bolt.horizontal.circle.fill"
        case .working: return "hourglass.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .stopped: return "circle"
        }
    }
}
