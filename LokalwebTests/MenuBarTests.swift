import XCTest
@testable import Lokalweb

final class MenuBarTests: XCTestCase {
    func testMenuBarStatusPrecedenceAndLabels() {
        XCTAssertEqual(
            MenuBarStatus.resolve(
                isBusy: true,
                needsAttention: true,
                allRunning: true,
                anyRunning: true
            ),
            .attention
        )
        XCTAssertEqual(
            MenuBarStatus.resolve(
                isBusy: true,
                needsAttention: false,
                allRunning: false,
                anyRunning: false
            ),
            .working
        )
        XCTAssertEqual(
            MenuBarStatus.resolve(
                isBusy: false,
                needsAttention: false,
                allRunning: true,
                anyRunning: true
            ),
            .running
        )
        XCTAssertEqual(
            MenuBarStatus.resolve(
                isBusy: false,
                needsAttention: false,
                allRunning: false,
                anyRunning: true
            ),
            .partial
        )
        XCTAssertEqual(
            MenuBarStatus.resolve(
                isBusy: false,
                needsAttention: false,
                allRunning: false,
                anyRunning: false
            ),
            .stopped
        )
        XCTAssertEqual(MenuBarStatus.attention.label, "Needs attention")
        XCTAssertNotEqual(MenuBarStatus.running.systemImage, MenuBarStatus.stopped.systemImage)
    }

    @MainActor
    func testDashboardNavigationCarriesNewWordPressRequest() throws {
        let navigation = AppNavigation()
        navigation.requestNewWordPress()

        XCTAssertEqual(navigation.section, .sites)
        let request = try XCTUnwrap(navigation.newWordPressRequest)
        navigation.consumeNewWordPressRequest(UUID())
        XCTAssertEqual(navigation.newWordPressRequest, request)
        navigation.consumeNewWordPressRequest(request)
        XCTAssertNil(navigation.newWordPressRequest)
    }

    @MainActor
    func testDashboardLaunchPolicyKeepsFirstLaunchAndAttentionVisible() {
        XCTAssertTrue(LokalwebAppDelegate.shouldKeepDashboardVisibleOnLaunch(
            hasLaunchedBefore: false,
            needsAttention: false,
            environment: [:]
        ))
        XCTAssertTrue(LokalwebAppDelegate.shouldKeepDashboardVisibleOnLaunch(
            hasLaunchedBefore: true,
            needsAttention: true,
            environment: [:]
        ))
        XCTAssertFalse(LokalwebAppDelegate.shouldKeepDashboardVisibleOnLaunch(
            hasLaunchedBefore: true,
            needsAttention: false,
            environment: [:]
        ))
    }

    @MainActor
    func testHostedTestsDoNotApplyDashboardLaunchPolicy() {
        let environment = ["XCTestConfigurationFilePath": "/tmp/LokalwebTests.xctestconfiguration"]
        XCTAssertFalse(LokalwebAppDelegate.shouldApplyDashboardLaunchPolicy(environment: environment))
        XCTAssertTrue(LokalwebAppDelegate.shouldKeepDashboardVisibleOnLaunch(
            hasLaunchedBefore: true,
            needsAttention: false,
            environment: environment
        ))
    }
}
