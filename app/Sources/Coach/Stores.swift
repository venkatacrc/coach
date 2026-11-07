import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppFolder {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coach", isDirectory: true)
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var content: CoachContent?
    @Published var state = CoachState()
    @Published var errorMessage: String?

    static var stateURL: URL { AppFolder.url.appendingPathComponent("state.json") }
    private var saveTask: DispatchWorkItem?

    init() {
        loadContent()
        if let data = try? Data(contentsOf: Self.stateURL) {
            do {
                state = try JSONDecoder().decode(CoachState.self, from: data)
            } catch {
                errorMessage = "Could not read state.json: \(error.localizedDescription)"
            }
        }
    }

    var coach: Coach? { content.map { Coach(content: $0, state: state) } }

    /// The copy inside the .app first, then the SwiftPM resource bundle (used by `swift run`).
    func loadContent() {
        let url = Bundle.main.url(forResource: "content", withExtension: "json")
            ?? Bundle.module.url(forResource: "content", withExtension: "json")
        guard let url else { errorMessage = "content.json is missing"; return }
        do {
            content = try JSONDecoder().decode(CoachContent.self, from: Data(contentsOf: url))
        } catch {
            errorMessage = "Could not read content.json: \(error)"
        }
    }

    // MARK: Edits

    func editDay(_ key: String, _ change: (inout DayLog) -> Void) {
        var d = state.days[key] ?? DayLog()
        change(&d)
        d.updated = nowMillis
        state.days[key] = d
        scheduleSave()
    }

    func toggleStep(_ key: String, day: String) {
        editDay(day) { d in
            if let i = d.done.firstIndex(of: key) { d.done.remove(at: i) } else { d.done.append(key) }
        }
    }

    func editWeek(_ key: String, _ change: (inout WeekLog) -> Void) {
        var w = state.weeks[key] ?? WeekLog()
        change(&w)
        w.updated = nowMillis
        state.weeks[key] = w
        scheduleSave()
    }

    func editLesson(_ id: String, _ change: (inout LessonLog) -> Void) {
        var l = state.lessons[id] ?? LessonLog()
        change(&l)
        l.updated = nowMillis
        state.lessons[id] = l
        scheduleSave()
    }

    func saveGoal(_ goal: Goal) {
        var g = goal
        g.updated = nowMillis
        state.goals[g.id] = g
        scheduleSave()
    }

    func setFamilyName(_ id: String, _ name: String) {
        state.settings.family[id] = name
        state.settings.updated = nowMillis
        scheduleSave()
    }

    func editCustom(_ change: (inout Custom) -> Void) {
        var c = state.custom
        change(&c)
        c.updated = nowMillis
        state.custom = c
        scheduleSave()
    }

    func setHabit(_ id: String, off: Bool? = nil, target: Int?? = nil) {
        editCustom { c in
            var h = c.habits[id] ?? HabitSetting()
            if let off { h.off = off ? true : nil }
            if let target { h.target = target }
            if h.off == nil && h.target == nil { c.habits[id] = nil } else { c.habits[id] = h }
        }
    }

    func resetPlan() {
        let alert = NSAlert()
        alert.messageText = "Go back to the default plan?"
        alert.informativeText = "This undoes all your changes to blocks, steps and habits. Your ticks and reviews stay."
        alert.addButton(withTitle: "Reset Plan")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        editCustom { $0 = Custom() }
    }

    // MARK: Bindings

    func day<T>(_ key: String, _ path: WritableKeyPath<DayLog, T>) -> Binding<T> {
        Binding(get: { (self.state.days[key] ?? DayLog())[keyPath: path] },
                set: { v in self.editDay(key) { $0[keyPath: path] = v } })
    }

    func week<T>(_ key: String, _ path: WritableKeyPath<WeekLog, T>) -> Binding<T> {
        Binding(get: { (self.state.weeks[key] ?? WeekLog())[keyPath: path] },
                set: { v in self.editWeek(key) { $0[keyPath: path] = v } })
    }

    func lessonNote(_ id: String) -> Binding<String> {
        Binding(get: { self.state.lessons[id]?.note ?? "" },
                set: { v in self.editLesson(id) { $0.note = v } })
    }

    // MARK: Saving, backup and merge

    private func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }

    func saveNow() {
        do {
            try FileManager.default.createDirectory(at: AppFolder.url, withIntermediateDirectories: true)
            try encoded().write(to: Self.stateURL, options: .atomic)
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(state)
    }

    func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "Export Coach backup"
        panel.nameFieldStringValue = "coach-backup-\(Day.key(Date())).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try encoded().write(to: url, options: .atomic)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "Import a Coach backup (from the phone or another Mac)"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try JSONDecoder().decode(CoachState.self, from: Data(contentsOf: url))
            let n = merge(incoming)
            errorMessage = "Imported: \(n) entries updated."
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Newer record wins, per day, lesson, week and goal.
    @discardableResult
    func merge(_ incoming: CoachState) -> Int {
        var n = 0
        for (k, v) in incoming.days where v.updated > (state.days[k]?.updated ?? -1) { state.days[k] = v; n += 1 }
        for (k, v) in incoming.lessons where v.updated > (state.lessons[k]?.updated ?? -1) { state.lessons[k] = v; n += 1 }
        for (k, v) in incoming.weeks where v.updated > (state.weeks[k]?.updated ?? -1) { state.weeks[k] = v; n += 1 }
        for (k, v) in incoming.goals where v.updated > (state.goals[k]?.updated ?? -1) { state.goals[k] = v; n += 1 }
        if incoming.settings.updated > state.settings.updated { state.settings = incoming.settings; n += 1 }
        if incoming.custom.updated > state.custom.updated { state.custom = incoming.custom; n += 1 }
        saveNow()
        return n
    }

    func reset() {
        let alert = NSAlert()
        alert.messageText = "Erase all progress, reviews and goals?"
        alert.informativeText = "Export a backup first if you're not sure."
        alert.addButton(withTitle: "Erase")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state = CoachState()
        saveNow()
    }

    // MARK: Opening the other apps

    /// The installed app if there is one (Applications, ~/Applications, or the repo's build folder), else the web app.
    func open(_ app: CoachApp) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        if let mac = app.mac {
            let name = (mac as NSString).lastPathComponent
            let candidates = [
                URL(fileURLWithPath: "/Applications/\(name)"),
                home.appendingPathComponent("Applications/\(name)"),
                home.appendingPathComponent("code/\(app.repo)/\(mac)"),
            ]
            if let url = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        if let url = URL(string: app.web ?? "https://github.com/venkatacrc/\(app.repo)") {
            NSWorkspace.shared.open(url)
        }
    }
}
