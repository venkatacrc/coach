import SwiftUI

// MARK: - Content (content.json, built by tools/build_content.py)

struct CoachContent: Decodable {
    let rhythm: Rhythm
    let categories: [AppCategory]
    let apps: [CoachApp]
    let tracks: [Track]
    let wisdom: [Saying]
    let coach: CoachText
    let goals: [GoalSuggestion]
    let version: String
}

struct Rhythm: Decodable {
    let wake: String
    let sleep: String
    let summary: String?
    let areas: [Area]
    let habits: [Habit]
    let family: [FamilyMember]
    let days: [String: String]
    let templates: [String: DayTemplate]
}

struct Area: Decodable, Identifiable {
    let id: String
    let title: String
    let color: String
    let icon: String
}

struct Habit: Decodable, Identifiable {
    let id: String
    let title: String
    let area: String
    let icon: String
}

struct FamilyMember: Decodable, Identifiable {
    let id: String
    let name: String
}

struct DayTemplate: Decodable {
    let title: String
    let blocks: [BlockSpec]
}

struct BlockSpec: Decodable {
    let id: String
    let start: String
    let end: String
    let title: String
    let area: String
    let why: String?
    let steps: [StepSpec]
}

struct StepSpec: Decodable {
    let id: String
    let text: ByDay
    let habit: String?
    let app: ByDay?
    let track: ByDay?
    let practice: String?
    let action: String?
}

/// A step field that is either one value or a `{weekday: value}` map.
enum ByDay: Decodable {
    case one(String)
    case byDay([String: String])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .one(s)
        } else {
            self = .byDay(try c.decode([String: String].self))
        }
    }

    func resolve(_ weekday: String) -> String? {
        switch self {
        case .one(let s): return s
        case .byDay(let m): return m[weekday] ?? m["default"]
        }
    }
}

struct Track: Decodable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let area: String
    let icon: String
    let lessons: [Lesson]
}

struct Lesson: Decodable, Identifiable {
    let id: String
    let title: String
    let idea: String
    let practice: String
    let ask: String
    let read: [Reading]?
}

struct Reading: Decodable, Hashable {
    let title: String
    let by: String?
    let url: String?
}

struct AppCategory: Decodable, Identifiable {
    let id: String
    let title: String
}

struct CoachApp: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String
    let icon: String
    let about: String
    let web: String?
    let repo: String
    let mac: String?
}

struct Saying: Decodable {
    let text: String
    let meaning: String?
    let source: String
}

struct CoachText: Decodable {
    let greetings: [String: String]
    let messages: [CoachMessageSpec]
}

struct CoachMessageSpec: Decodable {
    let rule: String
    let icon: String
    let title: String
    let text: String
}

struct GoalSuggestion: Decodable, Identifiable {
    let id: String
    let area: String
    let title: String
    let milestones: [String]
}

// MARK: - Saved state (state.json; the same shape as the web app's backup)

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

private func three<T>(_ xs: [T], _ fill: T) -> [T] {
    Array((xs + Array(repeating: fill, count: 3)).prefix(3))
}

struct CoachState: Codable {
    var version = 1
    var days: [String: DayLog] = [:]
    var lessons: [String: LessonLog] = [:]
    var weeks: [String: WeekLog] = [:]
    var goals: [String: Goal] = [:]
    var settings = Settings()
    var custom = Custom()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, 1)
        days = c.value(.days, [:])
        lessons = c.value(.lessons, [:])
        weeks = c.value(.weeks, [:])
        goals = c.value(.goals, [:])
        settings = c.value(.settings, Settings())
        custom = c.value(.custom, Custom())
    }
}

/// Your changes to the plan. Override fields are `{"default" | weekday: value}` maps; for app and
/// habit, "" means none. Block keys are "template/block", step keys "template/block/step".
struct Custom: Codable {
    var blocks: [String: BlockOverride] = [:]
    var steps: [String: StepOverride] = [:]
    var addedBlocks: [String: [AddedBlock]] = [:]
    var addedSteps: [String: [AddedStep]] = [:]
    var habits: [String: HabitSetting] = [:]
    var updated: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = c.value(.blocks, [:])
        steps = c.value(.steps, [:])
        addedBlocks = c.value(.addedBlocks, [:])
        addedSteps = c.value(.addedSteps, [:])
        habits = c.value(.habits, [:])
        updated = c.value(.updated, 0)
    }

    var changeCount: Int {
        blocks.count + steps.count + habits.count + addedBlocks.values.reduce(0) { $0 + $1.count }
            + addedSteps.values.reduce(0) { $0 + $1.count }
    }
}

typealias DayMap<T> = [String: T]

extension Dictionary where Key == String {
    func on(_ weekday: String) -> Value? { self[weekday] ?? self["default"] }
}

struct BlockOverride: Codable {
    var start: DayMap<String>?
    var end: DayMap<String>?
    var title: DayMap<String>?
    var area: DayMap<String>?
    var hidden: DayMap<Bool>?

    var isEmpty: Bool { start == nil && end == nil && title == nil && area == nil && hidden == nil }
}

struct StepOverride: Codable {
    var text: DayMap<String>?
    var app: DayMap<String>?
    var habit: DayMap<String>?
    var hidden: DayMap<Bool>?

    var isEmpty: Bool { text == nil && app == nil && habit == nil && hidden == nil }
}

struct AddedBlock: Codable {
    var id: String
    var start: String
    var end: String
    var title: String
    var area: String
    var days: [String]?
}

struct AddedStep: Codable {
    var id: String
    var text: String
    var habit: String = ""
    var app: String = ""
    var days: [String]?

    init(id: String, text: String, habit: String, app: String, days: [String]?) {
        (self.id, self.text, self.habit, self.app, self.days) = (id, text, habit, app, days)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        text = c.value(.text, "")
        habit = c.value(.habit, "")
        app = c.value(.app, "")
        days = c.value(.days, nil)
    }
}

struct HabitSetting: Codable {
    var off: Bool?
    var target: Int?
}

struct DayLog: Codable {
    var done: [String] = []
    var mood: Int?
    var energy: Int?
    var wins = ["", "", ""]
    var gratitude = ""
    var note = ""
    var focus = ["", "", ""]
    var focusDone = [false, false, false]
    var updated: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done = c.value(.done, [])
        mood = c.value(.mood, nil)
        energy = c.value(.energy, nil)
        wins = three(c.value(.wins, []), "")
        gratitude = c.value(.gratitude, "")
        note = c.value(.note, "")
        focus = three(c.value(.focus, []), "")
        focusDone = three(c.value(.focusDone, []), false)
        updated = c.value(.updated, 0)
    }
}

struct LessonLog: Codable {
    var done = false
    var doneOn: String?
    var note = ""
    var updated: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done = c.value(.done, false)
        doneOn = c.value(.doneOn, nil)
        note = c.value(.note, "")
        updated = c.value(.updated, 0)
    }
}

struct WeekLog: Codable {
    var wins = ""
    var learned = ""
    var drained = ""
    var family = ""
    var stop = ""
    var big3: [String: String] = [:]
    var updated: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wins = c.value(.wins, "")
        learned = c.value(.learned, "")
        drained = c.value(.drained, "")
        family = c.value(.family, "")
        stop = c.value(.stop, "")
        big3 = c.value(.big3, [:])
        updated = c.value(.updated, 0)
    }

    var isEmpty: Bool {
        [wins, learned, drained, family, stop].allSatisfy { $0.isEmpty } && big3.values.allSatisfy { $0.isEmpty }
    }
}

struct Milestone: Codable, Hashable {
    var text: String
    var done = false
}

struct Goal: Codable, Identifiable {
    var id: String
    var quarter: String
    var area: String
    var title: String
    var milestones: [Milestone] = []
    var from: String?
    var created: Double?
    var deleted: Bool?
    var updated: Double = 0

    init(id: String, quarter: String, area: String, title: String, milestones: [Milestone], from: String? = nil) {
        self.id = id
        self.quarter = quarter
        self.area = area
        self.title = title
        self.milestones = milestones
        self.from = from
        self.created = Date().timeIntervalSince1970 * 1000
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        quarter = c.value(.quarter, "")
        area = c.value(.area, "career")
        title = c.value(.title, "")
        milestones = c.value(.milestones, [])
        from = c.value(.from, nil)
        created = c.value(.created, nil)
        deleted = c.value(.deleted, nil)
        updated = c.value(.updated, 0)
    }
}

struct Settings: Codable {
    var family: [String: String] = [:]
    var updated: Double = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = c.value(.family, [:])
        updated = c.value(.updated, 0)
    }
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

var nowMillis: Double { Date().timeIntervalSince1970 * 1000 }
