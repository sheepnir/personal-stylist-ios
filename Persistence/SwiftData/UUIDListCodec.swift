import Foundation

enum UUIDListCodec {
    static func encode(_ ids: [UUID]) -> Data {
        (try? JSONEncoder().encode(ids.map(\.uuidString))) ?? Data()
    }

    static func decode(_ data: Data?) -> [UUID] {
        guard let data, !data.isEmpty,
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return strings.compactMap(UUID.init(uuidString:))
    }
}
