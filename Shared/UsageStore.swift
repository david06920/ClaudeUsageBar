import Foundation

enum UsageStore {
    static let appGroupID = "group.com.davidrensmann.claudeusagebar"

    private static let sessionKey = "usage.session"
    private static let weekKey = "usage.week"
    private static let updatedKey = "usage.updatedAt"
    private static let errorKey = "usage.error"

    struct Snapshot {
        let session: Int
        let week: Int
        let updatedAt: Date?
        let hasError: Bool
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(session: Int, week: Int, hasError: Bool) {
        guard let d = defaults else { return }
        d.set(session, forKey: sessionKey)
        d.set(week, forKey: weekKey)
        d.set(Date(), forKey: updatedKey)
        d.set(hasError, forKey: errorKey)
    }

    static func load() -> Snapshot {
        guard let d = defaults else {
            return Snapshot(session: 0, week: 0, updatedAt: nil, hasError: true)
        }
        return Snapshot(
            session: d.integer(forKey: sessionKey),
            week: d.integer(forKey: weekKey),
            updatedAt: d.object(forKey: updatedKey) as? Date,
            hasError: d.bool(forKey: errorKey)
        )
    }
}
