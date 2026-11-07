import SwiftUI

struct PlanView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let coach: Coach
    @AppStorage("notifyBlocks") private var notifyBlocks = false

    private var quarter: String { nav.quarter }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 14) {
                    goals
                    adjust
                    habits
                    settings
                }
                .frame(minWidth: 360)
                VStack(spacing: 14) {
                    rhythm
                    apps
                }
                .frame(minWidth: 340)
            }
            .padding(20)
        }
        .navigationTitle("Plan")
        .sheet(item: $nav.editingGoal) { goal in
            GoalEditor(coach: coach, goal: goal, isNew: nav.editingGoalIsNew) { nav.editingGoal = nil }
        }
    }

    // MARK: Goals

    private var goals: some View {
        let list = store.state.goals.values.filter { $0.quarter == quarter && $0.deleted != true }
            .sorted { ($0.created ?? 0) < ($1.created ?? 0) }
        let used = Set(list.compactMap(\.from))
        let suggestions = coach.content.goals.filter { !used.contains($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Goals · \(quarter.replacingOccurrences(of: "-", with: " "))").font(.headline)
                Spacer()
                Button { shiftQuarter(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Button { shiftQuarter(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            }
            if list.isEmpty {
                Text("Pick 3 to 5 goals for the quarter, at most one or two per area. Start from a suggestion below or write your own.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(list) { g in
                let color = coach.color(g.area)
                let n = g.milestones.filter(\.done).count
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(alignment: .top) {
                        Text(coach.area(g.area)?.icon ?? "")
                        Text(g.title).bold().fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Edit") { nav.editingGoalIsNew = false; nav.editingGoal = g }.buttonStyle(.link)
                    }
                    Bar(value: g.milestones.isEmpty ? 0 : Double(n) / Double(g.milestones.count), color: color)
                    ForEach(Array(g.milestones.enumerated()), id: \.offset) { i, m in
                        Toggle(isOn: Binding(get: { m.done }, set: { v in
                            var copy = g
                            copy.milestones[i].done = v
                            store.saveGoal(copy)
                        })) {
                            Text(m.text).strikethrough(m.done).foregroundStyle(m.done ? .secondary : .primary)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            Button("+ New goal") {
                nav.editingGoalIsNew = true
                nav.editingGoal = Goal(id: "g\(Int(nowMillis))", quarter: quarter, area: "career", title: "", milestones: [])
            }
            if !suggestions.isEmpty {
                DisclosureGroup("Suggestions (\(suggestions.count))") {
                    ForEach(suggestions) { s in
                        HStack {
                            Text(coach.area(s.area)?.icon ?? "")
                            Text(s.title).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Add") {
                                store.saveGoal(Goal(id: "g\(Int(nowMillis))", quarter: quarter, area: s.area, title: s.title,
                                                    milestones: s.milestones.map { Milestone(text: $0) }, from: s.id))
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func shiftQuarter(_ n: Int) {
        let parts = quarter.components(separatedBy: "-Q").compactMap { Int($0) }
        let idx = parts[0] * 4 + parts[1] - 1 + n
        nav.quarter = "\(idx / 4)-Q\(idx % 4 + 1)"
    }

    // MARK: Rhythm

    private var rhythm: some View {
        let days = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        let date = Day.add(Day.monday(Date()), days.firstIndex(of: nav.rhythmDay) ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Weekly rhythm").font(.headline)
            Text(coach.content.rhythm.summary
                 ?? "Up at \(Day.clock(Day.minutes(coach.content.rhythm.wake))), lights out at \(Day.clock(Day.minutes(coach.content.rhythm.sleep))).")
                .foregroundStyle(.secondary)
            Text("Click ✎ to change a block's time, steps or apps to match how you actually practise.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $nav.rhythmDay) {
                ForEach(days, id: \.self) { Text($0.prefix(1).uppercased() + $0.dropFirst()).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ForEach(coach.blocks(for: date, all: true)) { b in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(coach.color(b.area)).frame(width: 4)
                    Text(Day.clock(b.start)).font(.callout.bold()).foregroundStyle(coach.color(b.area)).frame(width: 64, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(b.title).bold().strikethrough(b.hidden)
                            if b.hidden { Text("· skipped").font(.caption).foregroundStyle(.secondary) }
                            if b.custom { Text("· yours").font(.caption).foregroundStyle(.secondary) }
                        }
                        ForEach(b.steps.filter { !$0.hidden && ($0.habit != nil || $0.app != nil || $0.track != nil || $0.custom) }) { s in
                            Text("• \(s.text)").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Button { nav.editingBlock = BlockRef(day: date, block: b.id) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).help("Adjust \(b.title)")
                }
                .opacity(b.hidden ? 0.5 : 1)
            }
            Button("+ Add block") { nav.editingBlock = BlockRef(day: date, block: nil) }
        }
        .card()
    }

    // MARK: Adjusting to practice

    @ViewBuilder
    private var adjust: some View {
        let today = Day.start(Date())
        let skipped = Array(coach.skippedSteps(today: today).prefix(4))
        let ups = Array(coach.levelUps(today: today).prefix(3))
        if !skipped.isEmpty || !ups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("🔧 Adjust to your practice").font(.headline)
                Text("From the last 2–3 weeks of ticks. A plan you follow beats a perfect plan you skip.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(skipped, id: \.key) { s in
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.text).bold().fixedSize(horizontal: false, vertical: true)
                            Text("Done \(s.done) of \(s.planned) days").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Adjust") { nav.editingBlock = BlockRef(day: s.day, block: s.block) }
                    }
                }
                ForEach(ups, id: \.id) { u in
                    Divider()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(coach.habitById[u.id]?.icon ?? "") \(coach.habitById[u.id]?.title ?? u.id)").bold()
                        Text("\(u.pct)% for 3 weeks: ready for a bigger step?").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .card()
        }
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Habits").font(.headline)
            Text("Turn off a habit you aren't practising now; its steps stay in the plan but stop counting. A weekly target means fewer days still count as 100%.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(coach.content.rhythm.habits) { h in
                let on = coach.habitOn(h.id)
                HStack {
                    Toggle(isOn: Binding(get: { on }, set: { store.setHabit(h.id, off: !$0) })) {
                        Text("\(h.icon) \(h.title)").strikethrough(!on).foregroundStyle(on ? .primary : .secondary)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Picker("", selection: Binding(get: { coach.habitTarget(h.id) ?? 0 },
                                                  set: { store.setHabit(h.id, target: .some($0 == 0 ? nil : $0)) })) {
                        Text("Every planned day").tag(0)
                        ForEach(1...6, id: \.self) { Text("\($0)× a week").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(!on)
                }
            }
            let n = coach.custom.changeCount
            if n > 0 {
                HStack {
                    Text("\(n) change\(n == 1 ? "" : "s") to the default plan.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Plan…", role: .destructive) { store.resetPlan() }
                }
                .padding(.top, 4)
            }
        }
        .card()
    }

    // MARK: Apps

    private var apps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My apps").font(.headline)
            ForEach(coach.content.categories) { c in
                SectionTitle(c.title).padding(.top, 6)
                ForEach(coach.content.apps.filter { $0.category == c.id }) { a in
                    Button { store.open(a) } label: {
                        HStack(spacing: 10) {
                            Text(a.icon).font(.title3).frame(width: 34, height: 34)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).bold()
                                Text(a.about).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.headline)
            SectionTitle("Family names")
            Text("Used in the plan and the coach's messages.").font(.caption).foregroundStyle(.secondary)
            ForEach(coach.content.rhythm.family) { f in
                HStack {
                    Text(f.name).frame(width: 130, alignment: .leading)
                    TextField(f.name, text: Binding(get: { store.state.settings.family[f.id] ?? "" },
                                                    set: { store.setFamilyName(f.id, $0) }))
                        .textFieldStyle(.roundedBorder)
                }
            }
            SectionTitle("Reminders")
            Toggle("Notify me when each block starts", isOn: $notifyBlocks)
                .disabled(!Notifier.available)
                .onChange(of: notifyBlocks) { _, on in on ? Notifier.schedule(coach) : Notifier.cancel() }
            if !Notifier.available {
                Text("Available in the built app (scripts/build_app.sh), not with swift run.").font(.caption).foregroundStyle(.secondary)
            }
            SectionTitle("Backup and sync")
            Text("Export a backup on the phone (☰ → Export backup), then import it here. Importing merges: the newer entry wins.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Import Backup…") { store.importBackup() }
                Button("Export Backup…") { store.exportBackup() }
            }
        }
        .card()
    }
}

@MainActor
final class GoalDraft: ObservableObject {
    @Published var goal: Goal
    @Published var milestones: String

    init(_ goal: Goal) {
        self.goal = goal
        self.milestones = goal.milestones.map(\.text).joined(separator: "\n")
    }
}

struct GoalEditor: View {
    @EnvironmentObject var store: Store
    let coach: Coach
    let isNew: Bool
    let done: () -> Void
    @StateObject private var draft: GoalDraft

    init(coach: Coach, goal: Goal, isNew: Bool, done: @escaping () -> Void) {
        self.coach = coach
        self.isNew = isNew
        self.done = done
        self._draft = StateObject(wrappedValue: GoalDraft(goal))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New goal" : "Edit goal").font(.title2.bold())
            SectionTitle("Goal")
            TextField("What will be true at the end of the quarter?", text: $draft.goal.title).textFieldStyle(.roundedBorder)
            SectionTitle("Area")
            Picker("", selection: $draft.goal.area) {
                ForEach(coach.content.rhythm.areas.filter { $0.id != "rest" }) { Text("\($0.icon) \($0.title)").tag($0.id) }
            }
            .labelsHidden()
            SectionTitle("Milestones (one per line)")
            TextEditor(text: $draft.milestones)
                .frame(minHeight: 120)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
            HStack {
                Button("Save") {
                    var goal = draft.goal
                    let old = Dictionary(goal.milestones.map { ($0.text, $0.done) }, uniquingKeysWith: { a, _ in a })
                    goal.title = goal.title.trimmingCharacters(in: .whitespaces)
                    goal.milestones = draft.milestones.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }.map { Milestone(text: $0, done: old[$0] ?? false) }
                    store.saveGoal(goal)
                    done()
                }
                .buttonStyle(.borderedProminent).tint(.teal)
                .disabled(draft.goal.title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                if !isNew {
                    Button("Delete", role: .destructive) {
                        var goal = draft.goal
                        goal.deleted = true
                        store.saveGoal(goal)
                        done()
                    }
                }
                Spacer()
                Button("Cancel") { done() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
