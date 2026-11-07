import SwiftUI

/// Writes one override field for a scope ("default" or a weekday), dropping it when it matches what it overrides.
func setOverride<T: Equatable>(_ m: inout DayMap<T>?, _ scope: String, _ value: T, _ base: T) {
    var map = m ?? [:]
    if scope == "default" {
        map = [:]
        if value != base { map["default"] = value }
    } else if value == (map["default"] ?? base) {
        map[scope] = nil
    } else {
        map[scope] = value
    }
    m = map.isEmpty ? nil : map
}

@MainActor
final class BlockDraft: ObservableObject {
    struct Row: Identifiable {
        let id: String
        let original: ResolvedStep?
        var text: String
        var app: String
        var habit: String
        var hidden: Bool
    }

    @Published var everyDay: Bool
    @Published var title: String
    @Published var area: String
    @Published var start: Date
    @Published var end: Date
    @Published var hidden: Bool
    @Published var rows: [Row]
    @Published var removed: Set<String> = []

    init(coach: Coach, ref: BlockRef) {
        let cur = ref.block.flatMap { id in coach.blocks(for: ref.day, all: true).first { $0.id == id } }
        let midnight = Day.start(ref.day)
        func time(_ m: Int) -> Date { midnight.addingTimeInterval(Double(m * 60)) }
        everyDay = cur.map { !$0.custom || ($0.days ?? []).isEmpty } ?? true
        title = cur?.title ?? ""
        area = cur?.area ?? "health"
        start = time(cur?.start ?? 19 * 60 + 30)
        end = time(cur?.end ?? 20 * 60)
        hidden = cur?.hidden ?? false
        rows = (cur?.steps ?? []).map { s in
            Row(id: s.sid, original: s, text: s.text, app: s.app ?? "", habit: BlockDraft.rawHabit(coach, ref, s), hidden: s.hidden)
        }
    }

    /// The habit a step links to, even while that habit is turned off, so saving doesn't drop it.
    static func rawHabit(_ coach: Coach, _ ref: BlockRef, _ s: ResolvedStep) -> String {
        guard let blockId = ref.block else { return "" }
        let tid = coach.templateId(for: ref.day), wd = Day.weekday(ref.day)
        if s.custom { return coach.custom.addedSteps["\(tid)/\(blockId)"]?.first { $0.id == s.sid }?.habit ?? "" }
        if let o = coach.custom.steps["\(tid)/\(blockId)/\(s.sid)"]?.habit?.on(wd) { return o }
        return coach.template(for: ref.day).blocks.first { $0.id == blockId }?.steps.first { $0.id == s.sid }?.habit ?? ""
    }

    func minutes(_ d: Date) -> Int { Day.nowMinutes(d) }
}

struct BlockEditor: View {
    @EnvironmentObject var store: Store
    let coach: Coach
    let ref: BlockRef
    let done: () -> Void
    @StateObject private var draft: BlockDraft

    init(coach: Coach, ref: BlockRef, done: @escaping () -> Void) {
        self.coach = coach
        self.ref = ref
        self.done = done
        self._draft = StateObject(wrappedValue: BlockDraft(coach: coach, ref: ref))
    }

    private var wd: String { Day.weekday(ref.day) }
    private var tid: String { coach.templateId(for: ref.day) }
    private var key: String? { ref.block.map { "\(tid)/\($0)" } }
    private var spec: BlockSpec? { ref.block.flatMap { id in coach.template(for: ref.day).blocks.first { $0.id == id } } }
    private var isCustom: Bool { spec == nil }
    private var current: ResolvedBlock? { ref.block.flatMap { id in coach.blocks(for: ref.day, all: true).first { $0.id == id } } }
    private static let dayNames = ["mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday",
                                   "fri": "Friday", "sat": "Saturday", "sun": "Sunday"]

    var body: some View {
        let tdays = coach.templateDays(tid)
        VStack(alignment: .leading, spacing: 12) {
            Text(ref.block == nil ? "New block" : "Adjust block").font(.title2.bold())
            if tdays.count > 1 {
                Picker("", selection: $draft.everyDay) {
                    Text("Every \(coach.template(for: ref.day).title.lowercased()) (\(tdays.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: ", ")))").tag(true)
                    Text("Only \(Self.dayNames[wd] ?? wd)s").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } else {
                Text("Applies to every \(Self.dayNames[wd] ?? wd).").font(.caption).foregroundStyle(.secondary)
            }
            SectionTitle("Block")
            TextField("e.g. Evening walk", text: $draft.title).textFieldStyle(.roundedBorder)
            HStack {
                DatePicker("From", selection: $draft.start, displayedComponents: .hourAndMinute)
                DatePicker("to", selection: $draft.end, displayedComponents: .hourAndMinute)
                Picker("", selection: $draft.area) {
                    ForEach(coach.content.rhythm.areas) { Text("\($0.icon) \($0.title)").tag($0.id) }
                }
                .labelsHidden()
            }
            if !isCustom {
                Toggle(tdays.count > 1 ? "Skip this block (for the days chosen above)" : "Skip this block", isOn: $draft.hidden)
                    .toggleStyle(.checkbox)
            }
            SectionTitle("Steps")
            Text("Link a step to a habit to count it, or to an app to open it from Today.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach($draft.rows) { $row in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("What will you do?", text: $row.text).textFieldStyle(.roundedBorder)
                            HStack {
                                Picker("", selection: $row.app) {
                                    Text("No app").tag("")
                                    ForEach(coach.content.apps) { Text("\($0.icon) \($0.name)").tag($0.id) }
                                }
                                .labelsHidden()
                                Picker("", selection: $row.habit) {
                                    Text("No habit").tag("")
                                    ForEach(coach.content.rhythm.habits) { Text("\($0.icon) \($0.title)").tag($0.id) }
                                }
                                .labelsHidden()
                                if let o = row.original, !o.custom {
                                    Toggle("skip", isOn: $row.hidden).toggleStyle(.checkbox)
                                } else {
                                    Button("Remove", role: .destructive) {
                                        draft.removed.insert(row.id)
                                        draft.rows.removeAll { $0.id == row.id }
                                    }
                                        .buttonStyle(.link)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 320)
            Button("+ Add step") {
                draft.rows.append(.init(id: "c\(String(Int(nowMillis), radix: 36))\(draft.rows.count)", original: nil,
                                        text: "", app: "", habit: "", hidden: false))
            }
            HStack {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.minutes(draft.end) <= draft.minutes(draft.start))
                    .keyboardShortcut(.defaultAction)
                if !isCustom, hasChanges {
                    Button("Reset to Default") { reset() }
                }
                if isCustom, ref.block != nil {
                    Button("Delete Block", role: .destructive) { remove() }
                }
                Spacer()
                Button("Cancel") { done() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private var hasChanges: Bool {
        guard let key else { return false }
        let c = coach.custom
        return c.blocks[key] != nil || c.addedSteps[key] != nil || c.steps.keys.contains { $0.hasPrefix(key + "/") }
    }

    private func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    private func save() {
        let scope = coach.templateDays(tid).count > 1 && !draft.everyDay ? wd : "default"
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        let start = hhmm(draft.minutes(draft.start)), end = hhmm(draft.minutes(draft.end))
        let cur = current, spec = spec, tid = tid, wd = wd
        store.editCustom { c in
            let bid = ref.block ?? "c\(String(Int(nowMillis), radix: 36))"
            if let spec, let cur {
                var o = c.blocks["\(tid)/\(bid)"] ?? BlockOverride()
                if title != cur.title { setOverride(&o.title, scope, title, spec.title) }
                if start != hhmm(cur.start) { setOverride(&o.start, scope, start, spec.start) }
                if end != hhmm(cur.end) { setOverride(&o.end, scope, end, spec.end) }
                if draft.area != cur.area { setOverride(&o.area, scope, draft.area, spec.area) }
                if draft.hidden != cur.hidden { setOverride(&o.hidden, scope, draft.hidden, false) }
                c.blocks["\(tid)/\(bid)"] = o.isEmpty ? nil : o
            } else {
                var list = c.addedBlocks[tid] ?? []
                let rec = AddedBlock(id: bid, start: start, end: end, title: title, area: draft.area,
                                     days: scope == "default" ? nil : [wd])
                if let i = list.firstIndex(where: { $0.id == bid }) { list[i] = rec } else { list.append(rec) }
                c.addedBlocks[tid] = list
            }

            let bkey = "\(tid)/\(bid)"
            var added = c.addedSteps[bkey] ?? []
            added.removeAll { draft.removed.contains($0.id) }
            for row in draft.rows {
                let text = row.text.trimmingCharacters(in: .whitespaces)
                if let o = row.original, !o.custom, let sspec = spec?.steps.first(where: { $0.id == o.sid }) {
                    let skey = "\(bkey)/\(o.sid)"
                    var so = c.steps[skey] ?? StepOverride()
                    let nowHabit = BlockDraft.rawHabit(coach, ref, o)
                    if !text.isEmpty, text != o.text { setOverride(&so.text, scope, text, coach.fill(sspec.text.resolve(wd) ?? "")) }
                    if row.app != (o.app ?? "") { setOverride(&so.app, scope, row.app, sspec.app?.resolve(wd) ?? "") }
                    if row.habit != nowHabit { setOverride(&so.habit, scope, row.habit, sspec.habit ?? "") }
                    if row.hidden != o.hidden { setOverride(&so.hidden, scope, row.hidden, false) }
                    c.steps[skey] = so.isEmpty ? nil : so
                    continue
                }
                let i = added.firstIndex { $0.id == row.id }
                if text.isEmpty {
                    if let i { added.remove(at: i) }
                    continue
                }
                let rec = AddedStep(id: row.id, text: text, habit: row.habit, app: row.app,
                                    days: row.original?.days ?? (scope == "default" ? nil : [wd]))
                if let i { added[i] = rec } else { added.append(rec) }
            }
            c.addedSteps[bkey] = added.isEmpty ? nil : added
        }
        done()
    }

    private func reset() {
        guard let key else { return }
        store.editCustom { c in
            c.blocks[key] = nil
            c.addedSteps[key] = nil
            for k in c.steps.keys where k.hasPrefix(key + "/") { c.steps[k] = nil }
        }
        done()
    }

    private func remove() {
        guard let key, let id = ref.block else { return }
        store.editCustom { c in
            c.addedBlocks[tid]?.removeAll { $0.id == id }
            if c.addedBlocks[tid]?.isEmpty == true { c.addedBlocks[tid] = nil }
            c.addedSteps[key] = nil
        }
        done()
    }
}
