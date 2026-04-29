import Foundation
import os
import Combine

private let logger = Logger(subsystem: "com.nightscope", category: "FavoriteLocationStore")

/// 保存済み地点の永続化と読込を抽象化する。
protocol FavoriteLocationStoring: AnyObject, Sendable {
    var locationsPublisher: AnyPublisher<[FavoriteLocation], Never> { get }
    func loadAll() -> [FavoriteLocation]
    func save(_ favorites: [FavoriteLocation])
}

extension FavoriteLocationStoring {
    var locationsPublisher: AnyPublisher<[FavoriteLocation], Never> {
        Just(loadAll()).eraseToAnyPublisher()
    }
}

// UserDefaults はスレッドセーフ（Apple ドキュメント保証）なため @unchecked Sendable が安全。
// 変更可能な内部状態への直接アクセスは持たない。
/// UserDefaults に保存済み地点を保持する実装。
final class FavoriteLocationStore: ObservableObject, FavoriteLocationStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key = "favorites.locations"
    @Published private(set) var locations: [FavoriteLocation]

    /// 既存の保存データを復元して初期化する。
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.locations = Self.loadFavorites(userDefaults: userDefaults, key: key)
    }

    /// 現在の保存済み地点を返す。
    func loadAll() -> [FavoriteLocation] {
        locations
    }

    var locationsPublisher: AnyPublisher<[FavoriteLocation], Never> {
        $locations.eraseToAnyPublisher()
    }

    /// 保存済み地点を JSON で永続化する。
    func save(_ favorites: [FavoriteLocation]) {
        do {
            let data = try JSONEncoder().encode(favorites)
            userDefaults.set(data, forKey: key)
            locations = favorites
        } catch {
            logger.error("Failed to encode favorites: \(error)")
        }
    }

    private static func loadFavorites(userDefaults: UserDefaults, key: String) -> [FavoriteLocation] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([FavoriteLocation].self, from: data)
        } catch {
            logger.error("Failed to decode favorites: \(error)")
            return []
        }
    }
}
