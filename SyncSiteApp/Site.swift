import Foundation

struct Site: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var projectPath: String
    var modifiedAfter: Date?

    var projectURL: URL {
        URL(fileURLWithPath: projectPath)
    }

    init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        modifiedAfter: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.modifiedAfter = modifiedAfter
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case projectPath
        case modifiedAfter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        modifiedAfter = try container.decodeIfPresent(Date.self, forKey: .modifiedAfter)
    }
}

enum SiteStore {
    private static let key = "configuredSites"
    private static let selectedKey = "selectedSiteID"

    static func loadSites() -> [Site] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let sites = try? JSONDecoder().decode([Site].self, from: data)
        else {
            return []
        }

        return sites
    }

    static func saveSites(_ sites: [Site]) {
        guard let data = try? JSONEncoder().encode(sites) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }

    static func loadSelectedID() -> UUID? {
        guard
            let value = UserDefaults.standard.string(forKey: selectedKey)
        else {
            return nil
        }

        return UUID(uuidString: value)
    }

    static func saveSelectedID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: selectedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedKey)
        }
    }
}
