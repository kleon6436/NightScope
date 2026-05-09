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

// MARK: - iCloudFavoriteLocationStore

private let iCloudLogger = Logger(subsystem: "com.nightscope", category: "iCloudFavoriteLocationStore")

/// NSUbiquitousKeyValueStore を使って iCloud にお気に入り地点を同期する実装。
/// iCloud が利用不可のときは UserDefaults にフォールバックする。
@MainActor
final class iCloudFavoriteLocationStore: ObservableObject, @preconcurrency FavoriteLocationStoring {
    // MARK: - Constants

    private static let iCloudKey = "favorites.locations.v1"
    private static let localFallbackKey = "favorites.locations.icloud.fallback"
    /// KV ストアの実用上限（Apple の 64KB 制限に対して余裕を持たせる）
    private static let maxDataSize = 60 * 1_024

    // MARK: - State

    @Published private(set) var locations: [FavoriteLocation]
    private let kvStore: NSUbiquitousKeyValueStore
    private let fallbackDefaults: UserDefaults

    // MARK: - Init

    init(kvStore: NSUbiquitousKeyValueStore = .default,
         fallbackDefaults: UserDefaults = .standard) {
        self.kvStore = kvStore
        self.fallbackDefaults = fallbackDefaults
        self.locations = Self.loadFromKVStore(kvStore) ?? Self.loadFromFallback(fallbackDefaults)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(kvStoreDidChangeExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
        kvStore.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - FavoriteLocationStoring

    var locationsPublisher: AnyPublisher<[FavoriteLocation], Never> {
        $locations.eraseToAnyPublisher()
    }

    func loadAll() -> [FavoriteLocation] {
        locations
    }

    func save(_ favorites: [FavoriteLocation]) {
        do {
            let data = try JSONEncoder().encode(favorites)
            if data.count > Self.maxDataSize {
                iCloudLogger.warning(
                    "Favorites data (\(data.count) bytes) exceeds 60 KB limit; skipping iCloud write."
                )
                // サイズ超過時はローカル UserDefaults のみ更新してリターン
                fallbackDefaults.set(data, forKey: Self.localFallbackKey)
                locations = favorites
                return
            }
            kvStore.set(data, forKey: Self.iCloudKey)
            kvStore.synchronize()
            locations = favorites
        } catch {
            iCloudLogger.error("Failed to encode favorites for iCloud: \(error)")
        }
    }

    // MARK: - External Change Notification

    @objc private func kvStoreDidChangeExternally(_ notification: Notification) {
        MainActor.assumeIsolated {
            let userInfo = notification.userInfo
            let reasonValue = userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let reason = reasonValue.flatMap { NSUbiquitousKeyValueStore.ChangeReason(rawValue: $0) }

            // アカウント変更の場合もリロード（最新書き込み優先）
            iCloudLogger.debug("iCloud KVStore changed externally (reason: \(String(describing: reason)))")
            if let updated = Self.loadFromKVStore(kvStore) {
                locations = updated
            }
        }
    }

    // MARK: - Private Helpers

    private static func loadFromKVStore(_ kvStore: NSUbiquitousKeyValueStore) -> [FavoriteLocation]? {
        guard let data = kvStore.data(forKey: iCloudKey) else { return nil }
        do {
            return try JSONDecoder().decode([FavoriteLocation].self, from: data)
        } catch {
            iCloudLogger.error("Failed to decode favorites from iCloud KVStore: \(error)")
            return nil
        }
    }

    private static func loadFromFallback(_ defaults: UserDefaults) -> [FavoriteLocation] {
        guard let data = defaults.data(forKey: localFallbackKey) else { return [] }
        do {
            return try JSONDecoder().decode([FavoriteLocation].self, from: data)
        } catch {
            iCloudLogger.error("Failed to decode favorites from fallback UserDefaults: \(error)")
            return []
        }
    }
}

// MARK: - NSUbiquitousKeyValueStore.ChangeReason

private extension NSUbiquitousKeyValueStore {
    enum ChangeReason: Int {
        case serverChange = 0
        case initialSyncChange = 1
        case quotaViolationChange = 2
        case accountChange = 3
    }
}
