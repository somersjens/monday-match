import SwiftUI
import XCTest
@testable import Stop_Swiping

@MainActor
final class PrivacyFlowTests: XCTestCase {
    private func completedState() -> ProfileCreationState {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        state.completedAt = Date()
        return state
    }

    func testNextActionsRequireNameThenPrivacyThenUnderstanding() {
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: completedState()), repository: nil)
        XCTAssertEqual(model.state.nextAction, .name)
        model.acceptPrivacy(.profile)
        XCTAssertFalse(model.state.hasAcceptedProfilePrivacy, "A name is required before acceptance.")
        model.setDisplayName("Alex")
        XCTAssertEqual(model.state.nextAction, .privacy)
        XCTAssertFalse(model.state.canShareProfile)
        model.acknowledgeExplanation()
        model.acceptPrivacy(.matching)
        XCTAssertEqual(model.state.nextAction, .privacy)
        XCTAssertFalse(model.state.hasAcceptedMatchingPrivacy)
        model.acceptPrivacy(.profile)
        XCTAssertEqual(model.state.nextAction, .explanation)
        XCTAssertTrue(model.state.canShareProfile)
        model.acknowledgeExplanation()
        XCTAssertEqual(model.state.nextAction, .matching)
        XCTAssertFalse(model.state.autoMatching.isEnabled)
    }

    func testAutoMatchingRequiresAnAccountBeforeCheckingNotifications() {
        for permission: NotificationPermissionState? in [nil, .notDetermined, .authorized, .denied] {
            XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: false, notificationState: permission), .account)
        }
    }

    func testAutoMatchingWaitsForNotificationSettingsAndOnlyAsksOnce() {
        XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: true, notificationState: nil), .loading)
        XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: true, notificationState: .notDetermined), .notifications)
        XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: true, notificationState: .authorized), .matching)
        XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: true, notificationState: .denied), .matching)
    }

    func testFirstConsentCannotEnableMatchingAndSecondConsentIsRequired() {
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: completedState()), repository: InMemoryProfileRepository())
        model.setDisplayName("Alex")
        model.setOwnAttractiveness(7)
        model.setPartnerMinimumAttractiveness(6)
        XCTAssertFalse(model.joinAutoMatching())
        model.acceptPrivacy(.profile)
        model.acknowledgeExplanation()
        XCTAssertFalse(model.joinAutoMatching())
        model.acceptPrivacy(.matching)
        XCTAssertFalse(model.state.autoMatching.isEnabled, "Accepting only unlocks the final join button.")
        XCTAssertTrue(model.joinAutoMatching())
        model.leaveAutoMatching()
        XCTAssertTrue(model.resumeAutoMatching())
    }

    func testConsentReceiptsAndProgressSurviveRelaunch() throws {
        let originalLanguage = AppLanguageSettings.shared.language
        defer { AppLanguageSettings.shared.language = originalLanguage }
        AppLanguageSettings.shared.language = .dutch
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = InMemoryProfileCreationStore(state: completedState())
        let model = ProfileCreationViewModel(store: store, repository: nil, now: { now })
        model.setDisplayName("Alex")
        model.acceptPrivacy(.profile)
        model.acknowledgeExplanation()
        model.acceptPrivacy(.matching)
        model.markDemoCompleted()
        let stored = try JSONDecoder().decode(ProfileCreationState.self, from: JSONEncoder().encode(XCTUnwrap(store.load())))
        let relaunched = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: stored), repository: nil)
        XCTAssertEqual(relaunched.state.nextAction, .matching)
        XCTAssertEqual(stored.profilePrivacyConsent?.acceptedAt, now)
        XCTAssertEqual(stored.profilePrivacyConsent?.languageCode, "nl")
        XCTAssertEqual(stored.autoMatching.privacyConsent?.version, PrivacyConsentKind.matching.version)
        XCTAssertFalse(stored.showsPhoneHint)
    }

    func testOldProfilesDefaultToNoConsentAndCannotResumeMatching() throws {
        var state = completedState()
        state.displayName = "Alex"
        state.autoMatching.ownAttractiveness = 7
        state.autoMatching.partnerMinimumAttractiveness = 6
        state.autoMatching.hasCompletedSetup = true
        state.autoMatching.isEnabled = true
        let decoded = try JSONDecoder().decode(ProfileCreationState.self, from: JSONEncoder().encode(state))
        XCTAssertFalse(decoded.autoMatching.isEnabled)
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: decoded), repository: nil)
        XCTAssertEqual(model.state.nextAction, .privacy)
        XCTAssertFalse(model.resumeAutoMatching())
        XCTAssertFalse(model.state.canShareProfile)
    }

    func testOutdatedConsentDoesNotPermitSharingOrMatching() {
        var state = completedState()
        state.displayName = "Alex"
        state.profilePrivacyConsent = PrivacyConsentReceipt(version: "old", acceptedAt: Date(), languageCode: "en")
        state.autoMatching.privacyConsent = PrivacyConsentReceipt(version: "old", acceptedAt: Date(), languageCode: "en")
        state.autoMatching.isEnabled = true
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
        XCTAssertEqual(model.state.nextAction, .privacy)
        XCTAssertFalse(model.state.canShareProfile)
        XCTAssertFalse(model.state.autoMatching.isEnabled)
    }

    func testExchangeServiceRefusesToAdvertiseWithoutConsent() {
        var state = completedState()
        state.displayName = "Alex"
        let session = ProfileExchangeSession()
        session.start(profile: state)
        XCTAssertFalse(session.isActive)
        XCTAssertTrue(session.people.isEmpty)
    }

    func testConsentAndTutorialHistoryNeverLeaveThePhone() {
        var state = completedState()
        state.displayName = "Alex"
        state.profilePrivacyConsent = PrivacyConsentReceipt(version: PrivacyConsentKind.profile.version, acceptedAt: Date(), languageCode: "en")
        state.hasUnderstoodExplanation = true
        state.hasCompletedDemo = true
        state.hasUsedProfileExchange = true
        let shared = state.sharedCopy(today: .today())
        XCTAssertNil(shared.profilePrivacyConsent)
        XCTAssertNil(shared.hasCompletedDemo)
        XCTAssertNil(shared.hasUsedProfileExchange)
        XCTAssertNil(shared.hasUnderstoodExplanation)
    }

    func testPhoneHintDisappearsOnlyAfterACompletedDemoOrExchange() {
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: completedState()), repository: nil)
        XCTAssertTrue(model.state.showsPhoneHint)
        model.setDisplayName("Alex")
        model.acceptPrivacy(.profile)
        model.acknowledgeExplanation()
        XCTAssertTrue(model.state.showsPhoneHint, "Skipping the demo must keep the hint.")
        model.markProfileExchangeUsed()
        XCTAssertFalse(model.state.showsPhoneHint)
        let demoModel = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: completedState()), repository: nil)
        demoModel.markDemoCompleted()
        XCTAssertFalse(demoModel.state.showsPhoneHint)
    }

    func testClearingNameRestartsAllNextActionsAndPersistsAfterRelaunch() throws {
        var original = completedState()
        original.displayName = "Alex"
        original.dateOfBirth = .init(year: 1996, month: 4, day: 21)
        original.heightCentimeters = 182
        original.profilePrivacyConsent = .init(version: PrivacyConsentKind.profile.version, acceptedAt: Date(), languageCode: "en")
        original.hasUnderstoodExplanation = true
        original.hasCompletedDemo = true
        original.hasUsedProfileExchange = true
        original.autoMatching.privacyConsent = .init(version: PrivacyConsentKind.matching.version, acceptedAt: Date(), languageCode: "en")
        original.autoMatching.ownAttractiveness = 7
        original.autoMatching.partnerMinimumAttractiveness = 6
        original.autoMatching.hasCompletedSetup = true
        original.autoMatching.isEnabled = true
        var draft = ProfileDraft()
        draft.displayName = "Alex"
        draft.autoMatching = original.autoMatching
        let repository = InMemoryProfileRepository(profile: draft)
        let store = InMemoryProfileCreationStore(state: original)
        let model = ProfileCreationViewModel(store: store, repository: repository)

        XCTAssertTrue(model.setDisplayName("   ", allowsEmpty: true))
        XCTAssertEqual(model.state.displayName, "")
        XCTAssertEqual(model.state.nextAction, .name)
        XCTAssertNil(model.state.profilePrivacyConsent)
        XCTAssertNil(model.state.autoMatching.privacyConsent)
        XCTAssertNil(model.state.hasUnderstoodExplanation)
        XCTAssertTrue(model.state.showsPhoneHint)
        XCTAssertFalse(model.state.autoMatching.isEnabled)
        XCTAssertFalse(model.state.autoMatching.hasCompletedSetup)
        XCTAssertFalse(model.state.canShareProfile)
        XCTAssertFalse(model.canResumeAutoMatching)
        XCTAssertEqual(model.state.dateOfBirth, original.dateOfBirth)
        XCTAssertEqual(model.state.heightCentimeters, original.heightCentimeters)
        XCTAssertEqual(model.state.completedAt, original.completedAt)
        XCTAssertEqual(model.state.autoMatching.ownAttractiveness, 7)
        XCTAssertEqual(try repository.loadProfile()?.displayName, "")
        XCTAssertEqual(try repository.loadProfile()?.autoMatching.isEnabled, false)
        XCTAssertNil(try repository.loadProfile()?.autoMatching.privacyConsent)

        let stored = try JSONDecoder().decode(ProfileCreationState.self, from: JSONEncoder().encode(XCTUnwrap(store.load())))
        let relaunched = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: stored), repository: repository)
        XCTAssertEqual(relaunched.state.nextAction, .name)
        XCTAssertTrue(relaunched.setDisplayName("Sam"))
        XCTAssertEqual(relaunched.state.nextAction, .privacy)
        XCTAssertFalse(relaunched.joinAutoMatching())
        relaunched.acceptPrivacy(.profile)
        XCTAssertEqual(relaunched.state.nextAction, .explanation)
        relaunched.acknowledgeExplanation()
        XCTAssertEqual(relaunched.state.nextAction, .matching)
        XCTAssertFalse(relaunched.canResumeAutoMatching)
        XCTAssertFalse(relaunched.joinAutoMatching())
        relaunched.acceptPrivacy(.matching)
        XCTAssertTrue(relaunched.joinAutoMatching())
    }

    func testRenamingKeepsConsentAndInitialNameEntryRejectsAnEmptyName() {
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: completedState()), repository: nil)
        model.setDisplayName("Alex")
        model.acceptPrivacy(.profile)
        model.acknowledgeExplanation()
        model.acceptPrivacy(.matching)
        let consent = model.state.profilePrivacyConsent
        XCTAssertFalse(model.setDisplayName(" "))
        XCTAssertTrue(model.setDisplayName("Sam"))
        XCTAssertEqual(model.state.nextAction, .matching)
        XCTAssertEqual(model.state.profilePrivacyConsent, consent)
        XCTAssertTrue(model.state.hasAcceptedMatchingPrivacy)
    }

    func testCancellingAnAnswerEditDoesNotRestoreAClearedNameOrConsent() {
        var state = completedState()
        state.displayName = "Alex"
        state.profilePrivacyConsent = .init(version: PrivacyConsentKind.profile.version, acceptedAt: Date(), languageCode: "en")
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
        model.beginEditing(.height)
        model.setDisplayName("", allowsEmpty: true)
        model.cancelEditing()
        XCTAssertEqual(model.state.displayName, "")
        XCTAssertNil(model.state.profilePrivacyConsent)
        XCTAssertEqual(model.state.nextAction, .name)
    }

    func testBothApprovalScreensIncludeTheSuppliedCopyAndFullPolicies() {
        for language in AppLanguage.allCases {
            for kind in [PrivacyConsentKind.profile, .matching] {
                let copy = PrivacyContent.approval(kind, language: language)
                XCTAssertFalse(copy.title.isEmpty)
                XCTAssertTrue(copy.summary.contains("- "))
                XCTAssertTrue(copy.details.contains("#### 8."))
                XCTAssertFalse(copy.acknowledgement.isEmpty)
            }
            let policy = PrivacyContent.policy(language: language)
            XCTAssertTrue(policy.contains("## 13."))
            XCTAssertFalse(policy.contains("**Publication check:**"))
            XCTAssertFalse(policy.contains("**Publicatiecontrole:**"))
        }
    }
}
