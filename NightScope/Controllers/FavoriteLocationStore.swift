import Foundation
import os

private let logger = Logger(subsystem: "com.nightscope", category: "FavoriteLocationStore")

protocol FavoriteLocationStoring: AnyObject, Sendable {
    func loadAll() -> [FavoriteLocation]
    func save(_ favorites: [FavoriteLocation])
}

// UserDefaults はスレッドセーフ（Apple ドキュメント保証）なため @unchecked Sendable が安全。
// 変更可能な内部状態への直接アクセスは持たない。
final class FavoriteLocationStore: FavoriteLocationStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key = "favorites.locations"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadAll() -> [FavoriteLocation] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([FavoriteLocation].self, from: data)
        } catch {
            logger.error("Failed to decode favorites: \(error)")
            return []
        }
    }

    func save(_ favorites: [FavoriteLocation]) {
        do {
            let data = try JSONEncoder().encode(favorites)
            userDefaults.set(data, forKey: key)
        } catch {
            logger.error("Failed to encode favorites: \(error)")
        }
    }
}
