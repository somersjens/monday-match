import CoreLocation
import Foundation
import Supabase
import XCTest
@testable import Stop_Swiping

@MainActor
final class SupabaseIntegrationTests: XCTestCase {
    private let projectURL = URL(string: "https://supabase.test")!
    private let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    override func tearDown() {
        SupabaseTestURLProtocol.handler = nil
        super.tearDown()
    }

    func testConfigurationRejectsSecretKeysAndInvalidURLs() {
        XCTAssertNil(SupabaseConfiguration(values: ["SUPABASE_URL": "http://project.test", "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test"]))
        XCTAssertNil(SupabaseConfiguration(values: ["SUPABASE_URL": "https://project.test", "SUPABASE_PUBLISHABLE_KEY": "sb_secret_test"]))
        XCTAssertNotNil(SupabaseConfiguration.bundled)
        XCTAssertTrue(DependencyContainer.live.authService is SupabaseAuthService)
    }

    func testBackupExcludesPhotoBytesAndExactCoordinatesButPreservesAnswers() throws {
        var state = completedState()
        state.heightCentimeters = 181
        state.location = .init(coordinate: .init(latitude: 52.123456, longitude: 4.654321), source: .map)
        var draft = ProfileDraft()
        draft.matchLocation = MatchLocation(coordinate: state.location!.coordinate, radiusKilometers: 25)
        draft.photos = [.init(imageData: Data([1, 2, 3]), order: 0)]
        let backup = SupabaseProfileBackup(state: state, draft: draft)
        XCTAssertTrue(backup.draft.photos.isEmpty)
        XCTAssertEqual(backup.photos.first?.id, draft.photos.first?.id)
        XCTAssertEqual(backup.state.heightCentimeters, 181)
        XCTAssertEqual(backup.state.location?.latitude, 52.12)
        XCTAssertEqual(backup.draft.matchLocation?.longitude, 4.65)
        let restored = try JSONDecoder().decode(SupabaseProfileBackup.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(restored, backup)
    }

    func testAppleSignInPassesIDTokenAndRawNonceAndSavesProfile() async throws {
        let response = try sessionData()
        let requests = SupabaseTestRequests()
        SupabaseTestURLProtocol.handler = { request in
            requests.append(request)
            if request.url!.path == "/auth/v1/token" { return (200, response) }
            if request.httpMethod == "GET" { return (200, Data("[]".utf8)) }
            return (201, Data())
        }
        let (client, _) = makeClient()
        let suite = "supabase-test.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = completedState()
        let store = InMemoryProfileCreationStore(state: state)
        var draft = ProfileDraft()
        draft.displayName = state.displayName
        draft.profileCreationCompletedAt = state.completedAt
        let repository = InMemoryProfileRepository(profile: draft)
        let sync = SupabaseProfileSync(client: client, projectURL: projectURL, repository: repository, store: store, defaults: defaults)
        let auth = SupabaseAuthService(client: client, profileSync: sync)
        let result = try await auth.signInWithApple(payload: .init(identityToken: "apple-id-token", rawNonce: "raw-nonce", fullName: nil))
        guard case .signedIn = result else { return XCTFail("A completed local profile must reach the profile home.") }
        let tokenRequest = try XCTUnwrap(requests.all.first { $0.url?.path == "/auth/v1/token" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: tokenRequest.bodyData) as? [String: Any])
        XCTAssertEqual(body["provider"] as? String, "apple")
        XCTAssertEqual(body["id_token"] as? String, "apple-id-token")
        XCTAssertEqual(body["nonce"] as? String, "raw-nonce")
        let save = try XCTUnwrap(requests.all.first { $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "POST" })
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: save.bodyData) as? [String: Any])
        XCTAssertEqual(row["id"] as? String, userID.uuidString.lowercased())
        XCTAssertNotNil(row["backup"])
        XCTAssertTrue(save.value(forHTTPHeaderField: "Prefer")?.contains("resolution=merge-duplicates") == true)
        guard case .signedIn = try await auth.restoreSession() else { return XCTFail("The Supabase session must restore.") }
    }

    func testGoogleOAuthUsesPKCEAndSavesTheProfileAfterTheCallback() async throws {
        let response = try sessionData()
        let requests = SupabaseTestRequests()
        SupabaseTestURLProtocol.handler = { request in
            requests.append(request)
            if request.url!.path == "/auth/v1/token" { return (200, response) }
            return request.httpMethod == "GET" ? (200, Data("[]".utf8)) : (201, Data())
        }
        let (client, _) = makeClient()
        let suite = "supabase-test.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = completedState()
        let store = InMemoryProfileCreationStore(state: state)
        var draft = ProfileDraft()
        draft.displayName = state.displayName
        draft.profileCreationCompletedAt = state.completedAt
        let sync = SupabaseProfileSync(client: client, projectURL: projectURL,
            repository: InMemoryProfileRepository(profile: draft), store: store, defaults: defaults)
        let auth = SupabaseAuthService(client: client, profileSync: sync) { url in
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(url.path, "/auth/v1/authorize")
            XCTAssertEqual(query["provider"], "google")
            XCTAssertEqual(query["redirect_to"], SupabaseConfiguration.authRedirectURL.absoluteString)
            XCTAssertEqual(query["prompt"], "select_account")
            XCTAssertEqual(query["code_challenge_method"]?.lowercased(), "s256")
            XCTAssertFalse(query["code_challenge"]?.isEmpty ?? true)
            return URL(string: "stopswiping://auth/callback?code=google-auth-code")!
        }
        guard case .signedIn = try await auth.signInWithGoogle() else {
            return XCTFail("Google must unlock the same completed-profile flow as Apple.")
        }
        let token = try XCTUnwrap(requests.all.first { $0.url?.path == "/auth/v1/token" })
        XCTAssertTrue(token.url!.query!.contains("grant_type=pkce"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: token.bodyData) as? [String: Any])
        XCTAssertEqual(body["auth_code"] as? String, "google-auth-code")
        XCTAssertFalse((body["code_verifier"] as? String)?.isEmpty ?? true)
        XCTAssertTrue(requests.all.contains { $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "POST" })
    }

    func testCancelledGoogleFlowDoesNotCreateASessionOrUploadAProfile() async throws {
        let requests = SupabaseTestRequests()
        SupabaseTestURLProtocol.handler = { request in
            requests.append(request)
            return (500, Data())
        }
        let (client, _) = makeClient()
        let sync = SupabaseProfileSync(client: client, projectURL: projectURL,
            repository: InMemoryProfileRepository(), store: InMemoryProfileCreationStore(state: completedState()))
        let auth = SupabaseAuthService(client: client, profileSync: sync) { _ in throw CancellationError() }
        do {
            _ = try await auth.signInWithGoogle()
            XCTFail("Cancellation must leave the account step open.")
        } catch is CancellationError {
            XCTAssertTrue(requests.all.isEmpty)
            XCTAssertNil(client.auth.currentSession)
        }
    }

    func testReturningAccountRestoresCloudProfileBeforeSaving() async throws {
        let response = try sessionData()
        var remoteState = completedState()
        remoteState.displayName = "Remote Alex"
        var draft = ProfileDraft()
        draft.displayName = remoteState.displayName
        draft.profileCreationCompletedAt = remoteState.completedAt
        let row = SupabaseProfileSync.Row(id: userID.uuidString.lowercased(),
            profile: CloudProfile(draft: draft, photoURLs: []), backup: .init(state: remoteState, draft: draft))
        let rows = try PostgrestClient.Configuration.jsonEncoder.encode([row])
        let requests = SupabaseTestRequests()
        SupabaseTestURLProtocol.handler = { request in
            requests.append(request)
            return request.url!.path == "/auth/v1/token" ? (200, response) : (200, rows)
        }
        let (client, _) = makeClient()
        let suite = "supabase-test.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = InMemoryProfileCreationStore(state: completedState())
        let repository = InMemoryProfileRepository()
        let sync = SupabaseProfileSync(client: client, projectURL: projectURL, repository: repository, store: store, defaults: defaults)
        _ = try await SupabaseAuthService(client: client, profileSync: sync)
            .signInWithApple(payload: .init(identityToken: "apple-id-token", rawNonce: "nonce", fullName: nil))
        XCTAssertEqual(store.load()?.displayName, "Remote Alex")
        XCTAssertEqual(try repository.loadProfile()?.displayName, "Remote Alex")
        XCTAssertFalse(requests.all.contains { $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "POST" })
    }

    func testCloudFailureDoesNotAdvanceSignUpOrEraseTheLocalProfile() async throws {
        let response = try sessionData()
        SupabaseTestURLProtocol.handler = { request in
            if request.url!.path == "/auth/v1/token" { return (200, response) }
            return (503, Data("{\"message\":\"unavailable\"}".utf8))
        }
        let (client, _) = makeClient()
        let state = completedState()
        let store = InMemoryProfileCreationStore(state: state)
        let repository = InMemoryProfileRepository()
        let sync = SupabaseProfileSync(client: client, projectURL: projectURL, repository: repository, store: store)
        do {
            _ = try await SupabaseAuthService(client: client, profileSync: sync)
                .signInWithApple(payload: .init(identityToken: "apple-id-token", rawNonce: "nonce", fullName: nil))
            XCTFail("Cloud errors must remain retryable in the account step.")
        } catch {
            XCTAssertEqual(store.load(), state)
        }
    }

    func testPhotoUploadUsesPrivateUserPathAndKeepsDisplayOrder() async throws {
        let requests = SupabaseTestRequests()
        SupabaseTestURLProtocol.handler = { request in
            requests.append(request)
            return (200, Data("{\"Id\":\"test-photo\",\"Key\":\"profile-photos/test.jpg\"}".utf8))
        }
        let (client, _) = makeClient()
        let first = ProfilePhoto(imageData: Data([1]), order: 0)
        let second = ProfilePhoto(imageData: Data([2]), order: 1)
        let uploader = SupabaseProfilePhotoUploader(client: client, projectURL: projectURL)
        let urls = try await uploader.uploadPhotos([second, first], userID: userID.uuidString)
        XCTAssertEqual(urls.map(\.lastPathComponent), [first, second].map { $0.id.uuidString.lowercased() + ".jpg" })
        XCTAssertTrue(urls.allSatisfy { $0.path.contains("/object/authenticated/profile-photos/") })
        XCTAssertTrue(requests.all.allSatisfy { $0.url!.path.contains(userID.uuidString.lowercased()) })
        let upload = try XCTUnwrap(requests.all.first)
        XCTAssertTrue(upload.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
        XCTAssertTrue(String(decoding: upload.bodyData, as: UTF8.self).contains("image/jpeg"))
    }

    private func completedState() -> ProfileCreationState {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        state.completedAt = Date()
        state.displayName = "Local Alex"
        state.profilePrivacyConsent = .init(version: PrivacyConsentKind.profile.version, acceptedAt: Date(), languageCode: "en")
        return state
    }

    private func sessionData() throws -> Data {
        let now = Date()
        let user = User(id: userID, appMetadata: [:], userMetadata: [:], aud: "authenticated", createdAt: now, updatedAt: now)
        let session = Session(accessToken: "test-access-token", tokenType: "bearer", expiresIn: 3600,
                              expiresAt: now.timeIntervalSince1970 + 3600, refreshToken: "test-refresh-token", user: user)
        return try AuthClient.Configuration.jsonEncoder.encode(session)
    }

    private func makeClient() -> (SupabaseClient, SupabaseTestAuthStorage) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SupabaseTestURLProtocol.self]
        let storage = SupabaseTestAuthStorage()
        let client = SupabaseClient(supabaseURL: projectURL, supabaseKey: "sb_publishable_test",
            options: .init(auth: .init(storage: storage, autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: config))))
        return (client, storage)
    }
}

nonisolated private final class SupabaseTestRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var all: [URLRequest] { lock.withLock { requests } }
}

nonisolated private final class SupabaseTestAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) { lock.withLock { values[key] = value } }
    func retrieve(key: String) -> Data? { lock.withLock { values[key] } }
    func remove(key: String) { lock.withLock { values[key] = nil } }
}

nonisolated private final class SupabaseTestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var captured = request
            captured.httpBody = request.bodyData
            let (code, data) = try Self.handler!(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

nonisolated private extension URLRequest {
    var bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}
