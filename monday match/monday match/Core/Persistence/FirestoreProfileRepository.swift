import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore

struct FirestoreProfileRepository: CloudProfileRepository {
    private let database: Firestore
    private let collectionName: String

    init(
        database: Firestore = Firestore.firestore(),
        collectionName: String = "profiles"
    ) {
        self.database = database
        self.collectionName = collectionName
    }

    func loadProfile(
        userID: String
    ) async throws -> CloudProfile? {
        let snapshot = try await database
            .collection(collectionName)
            .document(userID)
            .getDocument()

        guard snapshot.exists else {
            return nil
        }

        return try snapshot.data(
            as: CloudProfile.self
        )
    }

    func saveProfile(
        _ profile: CloudProfile,
        userID: String
    ) async throws {
        try database
            .collection(collectionName)
            .document(userID)
            .setData(
                from: profile,
                merge: true
            )
    }
}
#endif
