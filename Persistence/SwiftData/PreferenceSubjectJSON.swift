import Foundation

/// Walks `PreferenceRuleEntity.subjectJSON` for garment UUIDs (D-69 / D-70).
enum PreferenceSubjectJSON {
    enum Removal: Equatable {
        /// No garment ids — style-level rule; leave untouched.
        case styleLevel
        /// Subject named only this garment (or rewrite left no garment ids).
        case deleteRule
        case rewritten(Data)
    }

    static func garmentIDs(in data: Data?) -> Set<UUID> {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found = Set<UUID>()
        collectUUIDs(from: json, into: &found)
        return found
    }

    static func removing(_ id: UUID, from data: Data?) -> Removal {
        let ids = garmentIDs(in: data)
        if ids.isEmpty { return .styleLevel }
        if ids == [id] { return .deleteRule }
        if !ids.contains(id) { return .styleLevel }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data),
              let stripped = strip(id, from: json),
              let out = try? JSONSerialization.data(withJSONObject: stripped) else {
            return .deleteRule
        }
        if garmentIDs(in: out).isEmpty { return .deleteRule }
        return .rewritten(out)
    }

    static func namesAnyGarment(_ data: Data?) -> Bool {
        !garmentIDs(in: data).isEmpty
    }

    private static func collectUUIDs(from json: Any, into set: inout Set<UUID>) {
        if let string = json as? String, let uuid = UUID(uuidString: string) {
            set.insert(uuid)
        } else if let array = json as? [Any] {
            for element in array { collectUUIDs(from: element, into: &set) }
        } else if let dict = json as? [String: Any] {
            for value in dict.values { collectUUIDs(from: value, into: &set) }
        }
    }

    private static func strip(_ id: UUID, from json: Any) -> Any? {
        let needle = id.uuidString
        if let string = json as? String {
            if UUID(uuidString: string) == id || string.caseInsensitiveCompare(needle) == .orderedSame {
                return nil
            }
            return string
        }
        if let array = json as? [Any] {
            return array.compactMap { strip(id, from: $0) }
        }
        if let dict = json as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict {
                if let stripped = strip(id, from: value) {
                    out[key] = stripped
                }
            }
            return out
        }
        return json
    }
}
