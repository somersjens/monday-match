import Foundation
import Supabase

struct SupabaseCloudProfileRepository: CloudProfileRepository {
    let client: SupabaseClient

    private struct Row: Codable {
        let id: String
        let profile: CloudProfile
    }

    func loadProfile(userID: String) async throws -> CloudProfile? {
        let rows: [Row] = try await client.from("profiles").select("id,profile")
            .eq("id", value: userID).limit(1).execute().value
        return rows.first?.profile
    }

    func saveProfile(_ profile: CloudProfile, userID: String) async throws {
        try await client.from("profiles").upsert(Row(id: userID, profile: profile), onConflict: "id")
            .execute()
    }
}
