import Combine
import Foundation

@MainActor
final class AppNavigation: ObservableObject {
    @Published var section: AppSection? = .overview
    @Published private(set) var newWordPressRequest: UUID?

    func show(_ section: AppSection) {
        self.section = section
    }

    func requestNewWordPress() {
        section = .sites
        newWordPressRequest = UUID()
    }

    func consumeNewWordPressRequest(_ request: UUID) {
        if newWordPressRequest == request {
            newWordPressRequest = nil
        }
    }
}
