import SwiftUI

extension Day {
    static func parse(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}

struct PlacedStep: Identifiable {
    let step: RoadmapStep
    let doneOn: String?
    let skipped: Bool
    let typedHours: Double?
    let pomo: PomoTime?
    var id: String { step.id }
    var weeks: Int { step.weeks ?? 1 }
    /// What you typed wins over what Simple Pomo logged.
    var hours: Double? { typedHours ?? pomo?.hours }
}

/// Focus sessions Simple Pomo logged against one roadmap step (its task's `ref` is `coach:<step id>`).
struct PomoTime: Equatable {
    var count = 0
    var minutes = 0.0
    var hours: Double { (minutes / 30).rounded() / 2 }
    var line: String { "🍅 \(plural(count, "pomodoro")), \(hours.formatted()) h" }

    static let minutesEach = 25
    static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SimplePomo/store.json")
    }

    private struct Store: Decodable {
        struct Task: Decodable { let id: String; let ref: String? }
        struct Session: Decodable { let taskId: String?; let phase: String; let startedAt: Date; let endedAt: Date }
        let tasks: [Task]
        let sessions: [Session]
    }

    static func load() -> [String: PomoTime] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: storeURL), let store = try? dec.decode(Store.self, from: data) else { return [:] }
        var steps: [String: String] = [:]
        for t in store.tasks { if let r = t.ref, r.hasPrefix("coach:") { steps[t.id] = String(r.dropFirst(6)) } }
        var out: [String: PomoTime] = [:]
        for s in store.sessions where s.phase == "focus" {
            guard let id = s.taskId.flatMap({ steps[$0] }) else { continue }
            let m = s.endedAt.timeIntervalSince(s.startedAt) / 60
            guard m > 0 else { continue }
            out[id, default: PomoTime()].count += 1
            out[id, default: PomoTime()].minutes += m
        }
        return out
    }
}

struct RoadmapProgress {
    let active: [PlacedStep]
    let done: [PlacedStep]
    let thisWeek: [PlacedStep]
    let current: PlacedStep?
    let remaining: Int
    let finish: Date?
    let slip: Int
    let weeks: Int
    let hits: Int
    let pace: Double?
    let paceFinish: Date?
    let took: [String: Int]
    let elapsed: Int
    let plannedDays: Int
    let tookDays: Int
    let hoursPlanned: Int
    let hoursSpent: Double
}

extension Coach {
    var hoursPerWeek: Int { content.roadmap?.hoursPerWeek ?? 9 }

    func roadmapSteps() -> [PlacedStep] {
        guard let r = content.roadmap else { return [] }
        let s = state.roadmap
        return r.steps.map { base in
            var step = base
            if let e = s.edits[base.id] {
                if let t = e.title { step.title = t }
                if let d = e.doneWhen { step.doneWhen = d }
                if let w = e.weeks { step.weeks = w }
            }
            return PlacedStep(step: step, doneOn: s.done[base.id], skipped: s.skipped[base.id] ?? false,
                              typedHours: s.hours[base.id], pomo: pomo[base.id])
        }
    }

    func phase(_ id: String) -> RoadmapPhase? { content.roadmap?.phases.first { $0.id == id } }

    func apps(_ s: PlacedStep) -> [CoachApp] { (s.step.apps ?? []).compactMap(app) }

    /// Planned weeks per step against how long each took: from the previous finish (or the roadmap start) to its own finish.
    func roadmapProgress(today: Date = Date()) -> RoadmapProgress {
        func days(_ a: String, _ b: String) -> Int {
            guard let x = Day.parse(a), let y = Day.parse(b) else { return 0 }
            return Int((y.timeIntervalSince(x) / 86400).rounded())
        }
        func sumWeeks(_ xs: [PlacedStep]) -> Int { xs.reduce(0) { $0 + $1.weeks } }
        let mon = Day.monday(today), sun = Day.add(mon, 6)
        let start = Day.monday(Day.parse(state.roadmap.started) ?? mon)
        let startKey = Day.key(start), monKey = Day.key(mon)
        let active = roadmapSteps().filter { !$0.skipped }
        let done = active.filter { $0.doneOn != nil }
        let left = active.filter { $0.doneOn == nil }
        let current = left.first
        let thisWeek = done.filter { $0.doneOn! >= monKey }

        var took: [String: Int] = [:]
        var since = startKey
        for s in done.sorted(by: { $0.doneOn! < $1.doneOn! }) where s.doneOn! >= since {
            took[s.id] = max(1, days(since, s.doneOn!) + (since == startKey ? 1 : 0))
            since = s.doneOn!
        }
        let elapsed = days(since, Day.key(today)) + (since == startKey ? 1 : 0)

        var leftWeeks = sumWeeks(left)
        if let current {
            leftWeeks += max(1, current.weeks - max(0, Int(floor(Double(days(since, monKey)) / 7)))) - current.weeks
        }
        let finish = left.isEmpty ? nil : Day.add(sun, 7 * (leftWeeks - (thisWeek.isEmpty ? 1 : 0)))
        let planned = Day.add(start, 7 * sumWeeks(active) - 1)
        let weekSeconds = 7.0 * 86400
        let pastWeeks = Int((mon.timeIntervalSince(start) / weekSeconds).rounded())
        let inRun = done.filter { $0.doneOn! >= startKey }
        let pace = pastWeeks >= 4 ? Double(sumWeeks(inRun.filter { $0.doneOn! < monKey })) / Double(pastWeeks) : nil
        var paceFinish: Date?
        if let pace, pace > 0, pace < 0.95, !left.isEmpty {
            paceFinish = Day.add(sun, 7 * Int((Double(leftWeeks) / pace).rounded(.up)))
        }
        let timed = done.filter { took[$0.id] != nil }
        let logged = done.filter { $0.hours != nil }
        return RoadmapProgress(
            active: active, done: done, thisWeek: thisWeek, current: current,
            remaining: left.count, finish: finish,
            slip: finish.map { Int(($0.timeIntervalSince(planned) / weekSeconds).rounded()) } ?? 0,
            weeks: pastWeeks + 1,
            hits: Set(inRun.compactMap { Day.parse($0.doneOn!).map(Day.isoWeek) }).count,
            pace: pace, paceFinish: paceFinish,
            took: took, elapsed: elapsed,
            plannedDays: sumWeeks(timed) * 7,
            tookDays: timed.reduce(0) { $0 + (took[$1.id] ?? 0) },
            hoursPlanned: sumWeeks(logged) * hoursPerWeek,
            hoursSpent: logged.reduce(0) { $0 + ($1.hours ?? 0) })
    }

    /// What happened on the roadmap in the week starting `mon`, and the step that carried on after it.
    func roadmapWeek(_ mon: Date) -> (finished: [PlacedStep], next: PlacedStep?) {
        let start = Day.key(mon), end = Day.key(Day.add(mon, 7))
        let active = roadmapSteps().filter { !$0.skipped }
        return (active.filter { ($0.doneOn ?? "") >= start && ($0.doneOn ?? "") < end && $0.doneOn != nil },
                active.first { $0.doneOn == nil || $0.doneOn! >= end })
    }
}

extension Store {
    func startRoadmapIfNeeded() {
        if state.roadmap.started.isEmpty { editRoadmap { $0.started = Day.key(Day.monday(Date())) } }
    }

    func markStep(_ id: String, on day: String?) {
        editRoadmap { r in r.done[id] = day }
    }

    /// Hands the step to Simple Pomo as its active task and starts a focus session: the Mac app if it's installed, else the web app.
    func focusInPomo(_ s: PlacedStep, perWeek: Int) {
        var q = URLComponents()
        q.queryItems = [
            .init(name: "task", value: s.step.title), .init(name: "ref", value: "coach:\(s.id)"),
            .init(name: "category", value: "Roadmap"), .init(name: "area", value: "personal"),
            .init(name: "est", value: String(max(1, s.weeks * perWeek * 60 / PomoTime.minutesEach))),
            .init(name: "start", value: "1"),
        ]
        let query = q.percentEncodedQuery ?? ""
        if let mac = URL(string: "simplepomo://focus?\(query)"), NSWorkspace.shared.urlForApplication(toOpen: mac) != nil {
            NSWorkspace.shared.open(mac)
        } else if let web = coach?.app("simple_pomo")?.web, let url = URL(string: "\(web)?\(query)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The 🍅 button and the step's own apps.
struct StepTools: View {
    @EnvironmentObject var store: Store
    let coach: Coach
    let step: PlacedStep
    var pomo = true

    var body: some View {
        HStack(spacing: 8) {
            if pomo, coach.app("simple_pomo") != nil {
                Button("🍅 Focus in Simple Pomo") { store.focusInPomo(step, perWeek: coach.hoursPerWeek) }
                    .buttonStyle(.borderedProminent).tint(.red.opacity(0.8)).controlSize(.small)
            }
            ForEach(coach.apps(step)) { app in
                Button { store.open(app) } label: { Text("\(app.icon) \(app.name) ↗") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}

private func fullDate(_ d: Date) -> String { Day.format(d, "MMMdyyyy") }
func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

func fmtDays(_ d: Int) -> String {
    if d < 7 { return plural(d, "day") }
    var w = String(format: "%.1f", (Double(d) / 7 * 10).rounded() / 10)
    if w.hasSuffix(".0") { w.removeLast(2) }
    return "\(w) week\(w == "1" ? "" : "s")"
}

struct RoadmapStatus: View {
    let p: RoadmapProgress
    var full = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Bar(value: p.active.isEmpty ? 0 : Double(p.done.count) / Double(p.active.count), height: 8)
            (Text("\(p.done.count) of \(p.active.count) steps").bold() + Text(" · \(finishText)"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let pace = p.pace, let d = p.paceFinish {
                line("At your pace so far (\(Int((pace * 100).rounded()))% of the planned speed): \(fullDate(d))")
            }
            if full, p.plannedDays > 0 {
                let ratio = String(format: "%.1f", (Double(p.tookDays) / Double(p.plannedDays) * 10).rounded() / 10)
                (Text("Planned vs actual: ").bold()
                    + Text("finished steps were planned at \(fmtDays(p.plannedDays)) and took \(fmtDays(p.tookDays)) (\(ratio)× the plan)"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if full, p.hoursSpent > 0 {
                (Text("Hours: ").bold() + Text("\(p.hoursSpent.formatted()) h logged against about \(p.hoursPlanned) h planned"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if p.weeks > 1 { line("Hit \(p.hits) of \(p.weeks) weeks") }
        }
    }

    private func line(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var finishText: String {
        guard p.remaining > 0, let finish = p.finish else { return "🎉 Roadmap complete" }
        let vs = p.slip > 0 ? "\(plural(p.slip, "week")) later than first planned"
            : p.slip < 0 ? "\(plural(-p.slip, "week")) ahead of plan" : "on plan"
        return "Finish \(fullDate(finish)) at the planned pace · \(vs)"
    }
}

/// This week's goal on Today: the current roadmap step.
struct RoadmapCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let coach: Coach
    let date: Date

    var body: some View {
        let c = store.coach ?? coach
        let p = c.roadmapProgress()
        let day = min(Day.key(date), Day.key(Date()))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🎯 This week's goal").font(.headline)
                Spacer()
                Button("Roadmap ›") { nav.section = .plan }.buttonStyle(.link)
            }
            if !p.thisWeek.isEmpty {
                Text("✅ Done this week: \(p.thisWeek.map(\.step.title).joined(separator: "; "))")
                    .font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if let s = p.current {
                let ph = c.phase(s.step.phase)
                Text("\(ph?.icon ?? "") \(ph?.title ?? "") · step \(p.done.count + 1) of \(p.active.count)\(p.thisWeek.isEmpty ? "" : " · up next: start early, or rest")")
                    .font(.caption.bold()).foregroundStyle(.teal)
                Text(s.step.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                (Text("Done when: ").bold() + Text(s.step.doneWhen))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("⏱ \(p.elapsed > 0 ? "Day \(p.elapsed) on this step" : "Starts now") · planned \(plural(s.weeks, "week"))\(s.pomo.map { " · \($0.line)" } ?? "")")
                    .font(.caption).foregroundStyle(p.elapsed > s.weeks * 7 ? Color.orange : .secondary)
                StepTools(coach: c, step: s)
                HStack {
                    Button("✅ Done") { store.markStep(s.id, on: day) }
                        .buttonStyle(.borderedProminent).tint(.teal)
                    Button("Details and links") { nav.roadmapStepId = s.id }
                }
            } else if let r = c.content.roadmap {
                Text("🎉 \(r.goal): done.").font(.body.weight(.semibold))
            }
            RoadmapStatus(p: p, full: false)
        }
        .card(accent: .teal)
        .onAppear { store.startRoadmapIfNeeded() }
    }
}

/// The whole roadmap on Plan, one collapsible section per phase.
struct RoadmapList: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let coach: Coach

    var body: some View {
        let c = store.coach ?? coach
        if let r = c.content.roadmap {
            let p = c.roadmapProgress()
            let steps = c.roadmapSteps()
            let open = nav.openPhases ?? Set([p.current?.step.phase].compactMap { $0 })
            VStack(alignment: .leading, spacing: 10) {
                Text("🎯 Roadmap: \(r.title)").font(.headline)
                Text("\(r.goal). \(r.hours) One step at a time, planned at a week each unless you change it; a missed week carries the step over and the finish date moves with it.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                RoadmapStatus(p: p)
                ForEach(r.phases) { ph in
                    let list = steps.filter { $0.step.phase == ph.id }
                    let act = list.filter { !$0.skipped }
                    let n = act.filter { $0.doneOn != nil }.count
                    let isOpen = open.contains(ph.id)
                    Divider()
                    Button {
                        var o = open
                        if isOpen { o.remove(ph.id) } else { o.insert(ph.id) }
                        nav.openPhases = o
                    } label: {
                        HStack {
                            Text(ph.icon)
                            Text(ph.title).bold()
                            Spacer()
                            Text("\(n)/\(act.count)").font(.callout.weight(.semibold))
                                .foregroundStyle(!act.isEmpty && n == act.count ? .green : .secondary)
                            Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isOpen {
                        ForEach(list) { s in row(s, isCurrent: s.id == p.current?.id, took: s.doneOn == nil ? nil : p.took[s.id]) }
                    }
                }
            }
            .card(accent: .teal)
            .onAppear { store.startRoadmapIfNeeded() }
        }
    }

    private func row(_ s: PlacedStep, isCurrent: Bool, took: Int?) -> some View {
        Button { nav.roadmapStepId = s.id } label: {
            HStack(spacing: 10) {
                Image(systemName: s.doneOn != nil ? "checkmark.circle.fill" : isCurrent ? "play.circle" : "circle")
                    .foregroundStyle(.teal)
                Text(s.step.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .strikethrough(s.skipped)
                    .foregroundStyle(s.doneOn != nil || s.skipped ? .secondary : .primary)
                Spacer()
                if s.skipped { Text("skipped").font(.caption).foregroundStyle(.secondary) }
                if isCurrent { Text("this week").font(.caption.bold()).foregroundStyle(.teal) }
                if s.doneOn == nil, !s.skipped, s.weeks > 1 { Text("\(s.weeks) wk").font(.caption).foregroundStyle(.secondary) }
                if let took {
                    Text("took \(fmtDays(took))").font(.caption)
                        .foregroundStyle(Double(took) > Double(s.weeks * 7) * 1.25 ? Color.orange : .secondary)
                }
                if let d = s.doneOn.flatMap(Day.parse) { Text(Day.format(d, "MMMd")).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RoadmapStepSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let coach: Coach
    let stepId: String

    var body: some View {
        let c = store.coach ?? coach
        let steps = c.roadmapSteps()
        let active = steps.filter { !$0.skipped }
        if let s = steps.first(where: { $0.id == stepId }), let base = c.content.roadmap?.steps.first(where: { $0.id == stepId }) {
            let ph = c.phase(s.step.phase)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(ph?.icon ?? "") \(ph?.title ?? "") · \(s.skipped ? "skipped" : "step \((active.firstIndex { $0.id == stepId } ?? 0) + 1) of \(active.count)")")
                            .font(.callout.bold()).foregroundStyle(.teal)
                        Text(s.step.title).font(.title2.bold())
                        Text(s.step.why).lineSpacing(3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DONE WHEN").font(.caption.bold()).foregroundStyle(.teal)
                            Text(s.step.doneWhen).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        time(s, base: base, p: c.roadmapProgress(), perWeek: c.hoursPerWeek)
                        StepTools(coach: c, step: s, pomo: s.doneOn == nil && !s.skipped)
                        if let read = s.step.read, !read.isEmpty {
                            SectionTitle("Read (free)")
                            ForEach(read, id: \.self) { r in
                                if let u = r.url, let url = URL(string: u) { Link("\(r.title) ↗", destination: url).bold() }
                            }
                        }
                        DisclosureGroup("Reword this step") {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionTitle("Step")
                                TextField(base.title, text: edit(\.title, base: base.title, current: s.step.title)).textFieldStyle(.roundedBorder)
                                SectionTitle("Done when")
                                TextField(base.doneWhen, text: edit(\.doneWhen, base: base.doneWhen, current: s.step.doneWhen)).textFieldStyle(.roundedBorder)
                            }
                            .padding(.top, 6)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .textSelection(.enabled)
                }
                Divider()
                HStack {
                    Button(s.doneOn.flatMap(Day.parse).map { "✓ Done \(Day.format($0, "MMMd")) (undo)" } ?? "✅ Mark done") {
                        store.markStep(stepId, on: s.doneOn == nil ? Day.key(Date()) : nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(s.doneOn == nil ? .teal : .gray)
                    Button(s.skipped ? "Unskip" : "Skip") {
                        store.editRoadmap { r in r.skipped[stepId] = s.skipped ? nil : true }
                    }
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .padding(16)
            }
            .frame(width: 600, height: 640)
        }
    }

    private func edit(_ path: WritableKeyPath<StepEdit, String?>, base: String, current: String) -> Binding<String> {
        Binding(get: { current }, set: { v in
            store.editRoadmap { r in
                var e = r.edits[stepId] ?? StepEdit()
                let t = v.trimmingCharacters(in: .whitespaces)
                e[keyPath: path] = t.isEmpty || t == base ? nil : v
                r.edits[stepId] = e.title == nil && e.doneWhen == nil && e.weeks == nil ? nil : e
            }
        })
    }

    private func time(_ s: PlacedStep, base: RoadmapStep, p: RoadmapProgress, perWeek: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIME").font(.caption.bold()).foregroundStyle(.teal)
            HStack {
                Text("Planned").bold().frame(width: 96, alignment: .leading)
                Picker("", selection: Binding(get: { s.weeks }, set: { n in
                    store.editRoadmap { r in
                        var e = r.edits[stepId] ?? StepEdit()
                        e.weeks = n == (base.weeks ?? 1) ? nil : n
                        r.edits[stepId] = e.title == nil && e.doneWhen == nil && e.weeks == nil ? nil : e
                    }
                })) {
                    ForEach([1, 2, 3, 4, 6, 8], id: \.self) { n in Text(plural(n, "week")).tag(n) }
                }
                .labelsHidden().frame(width: 120)
                Text("about \(s.weeks * perWeek) h").font(.caption).foregroundStyle(.secondary)
            }
            if s.doneOn != nil, let took = p.took[stepId] {
                HStack {
                    Text("Took").bold().frame(width: 96, alignment: .leading)
                    Text(fmtDays(took)).bold()
                    Text(String(format: "%.1f× the plan", (Double(took) / Double(s.weeks * 7) * 10).rounded() / 10))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(Double(took) > Double(s.weeks * 7) * 1.25 ? Color.orange : .primary)
            } else if s.doneOn == nil, p.current?.id == stepId {
                HStack {
                    Text("So far").bold().frame(width: 96, alignment: .leading)
                    Text(p.elapsed > 0 ? fmtDays(p.elapsed) : "starts now").bold()
                }
                .foregroundStyle(p.elapsed > s.weeks * 7 ? Color.orange : .primary)
            }
            HStack {
                Text("Hours spent").bold().frame(width: 96, alignment: .leading)
                TextField(s.pomo.map { "\($0.hours.formatted()) (Pomo)" } ?? "optional", text: Binding(
                    get: { s.typedHours.map { $0.formatted() } ?? "" },
                    set: { v in
                        store.editRoadmap { r in
                            if let n = Double(v.trimmingCharacters(in: .whitespaces)), n >= 0 { r.hours[stepId] = n } else { r.hours[stepId] = nil }
                        }
                    }))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
            }
            if let pomo = s.pomo {
                Text("\(pomo.line) logged in Simple Pomo. \(s.typedHours != nil ? "The hours you typed win." : "Type hours to override.")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
