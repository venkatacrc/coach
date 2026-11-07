import Foundation

/// Local calendar days as "YYYY-MM-DD" keys, the same keys the web app uses.
enum Day {
    static let cal = Calendar(identifier: .gregorian)
    static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func start(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static func add(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: start(d))! }
    static func weekday(_ d: Date) -> String { weekdays[cal.component(.weekday, from: d) - 1] }
    static func monday(_ d: Date) -> Date { add(d, -((cal.component(.weekday, from: d) + 5) % 7)) }

    static func isoWeek(_ d: Date) -> String {
        let iso = Calendar(identifier: .iso8601)
        return String(format: "%04d-W%02d", iso.component(.yearForWeekOfYear, from: d), iso.component(.weekOfYear, from: d))
    }

    static func quarter(_ d: Date) -> String {
        "\(cal.component(.year, from: d))-Q\((cal.component(.month, from: d) - 1) / 3 + 1)"
    }

    static func minutes(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        return p[0] * 60 + p[1]
    }

    static func nowMinutes(_ now: Date = Date()) -> Int {
        cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
    }

    static func clock(_ m: Int) -> String {
        let h = m / 60
        return String(format: "%d:%02d%@", (h + 11) % 12 + 1, m % 60, h < 12 ? "am" : "pm")
    }

    static func duration(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    static func format(_ d: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }
}

struct ResolvedStep: Identifiable {
    let key: String
    let sid: String
    let text: String
    let habit: String?
    let app: String?
    let track: String?
    let practice: String?
    let action: String?
    var hidden = false
    var custom = false
    var days: [String]?
    var id: String { key }
}

struct ResolvedBlock: Identifiable {
    let id: String
    let title: String
    let area: String
    let why: String?
    let start: Int
    let end: Int
    let steps: [ResolvedStep]
    var hidden = false
    var custom = false
    var days: [String]?
}

struct HabitCount {
    var planned = 0
    var done = 0
}

/// A step you keep skipping on days you otherwise used the plan.
struct SkippedStep {
    let key: String
    let text: String
    let block: String
    let day: Date
    var planned = 0
    var done = 0
}

struct HabitWindow {
    var stats: [String: HabitCount] = [:]
    var days = 0
    var moods: [Int] = []
    var energies: [Int] = []
}

struct CoachMessage: Identifiable {
    let icon: String
    let title: String
    let text: String
    /// A block to open in the editor ("Adjust").
    var adjust: BlockRef?
    var id: String { title }
}

struct BlockRef: Identifiable, Hashable {
    let day: Date
    /// nil adds a new block to that day.
    let block: String?
    var id: String { "\(Day.key(day))/\(block ?? "+")" }
}

/// The coaching rules, read-only over content and state. Mirrors web/app.js.
struct Coach {
    let content: CoachContent
    let state: CoachState

    var habitById: [String: Habit] { Dictionary(uniqueKeysWithValues: content.rhythm.habits.map { ($0.id, $0) }) }
    func area(_ id: String) -> Area? { content.rhythm.areas.first { $0.id == id } }
    func track(_ id: String) -> Track? { content.tracks.first { $0.id == id } }
    func app(_ id: String) -> CoachApp? { content.apps.first { $0.id == id } }

    func familyName(_ id: String) -> String? {
        if let custom = state.settings.family[id]?.trimmingCharacters(in: .whitespaces), !custom.isEmpty { return custom }
        return content.rhythm.family.first { $0.id == id }?.name
    }

    func fill(_ text: String, _ vars: [String: String] = [:]) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let name = String(rest[rest.index(after: open)..<close])
            out += vars[name] ?? familyName(name) ?? "{\(name)}"
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    func templateId(for d: Date) -> String { content.rhythm.days[Day.weekday(d)] ?? "weekday" }

    func template(for d: Date) -> DayTemplate {
        content.rhythm.templates[templateId(for: d)] ?? content.rhythm.templates.values.first!
    }

    /// The weekdays that share a template, in week order.
    func templateDays(_ tid: String) -> [String] {
        ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].filter { content.rhythm.days[$0] == tid }
    }

    var custom: Custom { state.custom }
    func habitOn(_ id: String) -> Bool { custom.habits[id]?.off != true }
    func habitTarget(_ id: String) -> Int? { custom.habits[id]?.target }

    /// Days you're expected to do a habit: every planned day, or its weekly target scaled to the window.
    func expected(_ habit: String, _ c: HabitCount, days: Int) -> Int {
        guard let t = habitTarget(habit) else { return c.planned }
        return min(c.planned, Int((Double(t * days) / 7).rounded(.up)))
    }

    func rate(_ habit: String, _ c: HabitCount, days: Int) -> Double {
        let e = expected(habit, c, days: days)
        return e == 0 ? 1 : Double(min(c.done, e)) / Double(e)
    }

    /// An override of "" means none; nil means not overridden.
    private func pick(_ override: String?, _ fallback: String?) -> String? {
        if let o = override { return o.isEmpty ? nil : o }
        return fallback
    }

    /// The day's plan: the template plus your changes. `all` keeps skipped blocks and steps (for the editor).
    func blocks(for d: Date, all: Bool = false) -> [ResolvedBlock] {
        let wd = Day.weekday(d), tid = templateId(for: d), c = custom
        let applies = { (days: [String]?) in (days ?? []).isEmpty || days!.contains(wd) }
        var out: [ResolvedBlock] = []

        func step(_ blockId: String, _ sid: String, text: String, app: String?, habit: String?, track: String? = nil,
                  practice: String? = nil, action: String? = nil, hidden: Bool, custom: Bool, days: [String]? = nil) -> ResolvedStep {
            ResolvedStep(
                key: "\(blockId).\(sid)", sid: sid, text: fill(text),
                habit: habit.flatMap { habitById[$0] != nil && habitOn($0) ? $0 : nil },
                app: app.flatMap { self.app($0) != nil ? $0 : nil },
                track: track, practice: practice, action: action, hidden: hidden, custom: custom, days: days)
        }
        func added(_ blockId: String) -> [ResolvedStep] {
            (c.addedSteps["\(tid)/\(blockId)"] ?? []).filter { applies($0.days) }.map {
                step(blockId, $0.id, text: $0.text, app: $0.app.isEmpty ? nil : $0.app, habit: $0.habit.isEmpty ? nil : $0.habit,
                     hidden: false, custom: true, days: $0.days)
            }
        }

        for b in template(for: d).blocks {
            let o = c.blocks["\(tid)/\(b.id)"]
            let hidden = o?.hidden?.on(wd) ?? false
            if hidden && !all { continue }
            var steps: [ResolvedStep] = []
            for s in b.steps {
                let so = c.steps["\(tid)/\(b.id)/\(s.id)"]
                let sHidden = so?.hidden?.on(wd) ?? false
                if sHidden && !all { continue }
                let over = so?.text?.on(wd).flatMap { $0.isEmpty ? nil : $0 }
                guard let text = over ?? s.text.resolve(wd) else { continue }
                steps.append(step(b.id, s.id, text: text, app: pick(so?.app?.on(wd), s.app?.resolve(wd)),
                                  habit: pick(so?.habit?.on(wd), s.habit), track: s.track?.resolve(wd),
                                  practice: s.practice, action: s.action, hidden: sHidden, custom: false))
            }
            steps += added(b.id)
            func field(_ m: DayMap<String>?, _ base: String) -> String { m?.on(wd).flatMap { $0.isEmpty ? nil : $0 } ?? base }
            out.append(ResolvedBlock(
                id: b.id, title: field(o?.title, b.title), area: field(o?.area, b.area), why: b.why,
                start: Day.minutes(field(o?.start, b.start)), end: Day.minutes(field(o?.end, b.end)),
                steps: steps, hidden: hidden))
        }
        for b in c.addedBlocks[tid] ?? [] where applies(b.days) {
            out.append(ResolvedBlock(
                id: b.id, title: b.title, area: b.area, why: nil, start: Day.minutes(b.start), end: Day.minutes(b.end),
                steps: added(b.id), custom: true, days: b.days))
        }
        return out.sorted { $0.start < $1.start }
    }

    func planned(_ d: Date) -> Set<String> {
        Set(blocks(for: d).flatMap { $0.steps.compactMap(\.habit) })
    }

    func done(_ d: Date) -> Set<String> {
        let ticked = Set(state.days[Day.key(d)]?.done ?? [])
        return Set(blocks(for: d).flatMap { $0.steps.filter { ticked.contains($0.key) }.compactMap(\.habit) })
    }

    /// Days before the first one you touched don't count against you.
    var firstDayKey: String? { state.days.keys.min() }

    /// Habit counts over the n days before `end` (end itself not included).
    func window(end: Date, days n: Int) -> HabitWindow {
        var w = HabitWindow()
        guard let first = firstDayKey else { return w }
        for i in stride(from: n, through: 1, by: -1) {
            let d = Day.add(end, -i)
            let k = Day.key(d)
            if k < first { continue }
            w.days += 1
            let p = planned(d), dn = done(d)
            for h in p {
                w.stats[h, default: HabitCount()].planned += 1
                if dn.contains(h) { w.stats[h, default: HabitCount()].done += 1 }
            }
            if let m = state.days[k]?.mood { w.moods.append(m) }
            if let e = state.days[k]?.energy { w.energies.append(e) }
        }
        return w
    }

    /// Consecutive planned days done, counting back from today (today only counts once it's done).
    func streak(_ habit: String, today: Date) -> Int {
        guard let first = firstDayKey else { return 0 }
        var count = 0
        for i in 0..<400 {
            let d = Day.add(today, -i)
            if Day.key(d) < first { break }
            if !planned(d).contains(habit) { continue }
            if done(d).contains(habit) { count += 1 } else if i > 0 { break }
        }
        return count
    }

    func weekHasReview(_ d: Date) -> Bool {
        guard let w = state.weeks[Day.isoWeek(d)] else { return false }
        return !w.isEmpty
    }

    func messages(today: Date) -> [CoachMessage] {
        let byRule = Dictionary(content.coach.messages.map { ($0.rule, $0) }, uniquingKeysWith: { a, _ in a })
        func msg(_ rule: String, _ vars: [String: String] = [:]) -> CoachMessage? {
            guard let m = byRule[rule] else { return nil }
            return CoachMessage(icon: m.icon, title: fill(m.title, vars), text: fill(m.text, vars))
        }
        var out: [CoachMessage] = []
        if Day.weekday(today) == "sun" && !weekHasReview(today), let m = msg("weekly") { out.append(m) }

        let w = window(end: today, days: 7)
        if w.days < 3 {
            if let m = msg("welcome") { out.append(m) }
            return out
        }
        func rate(_ ids: String...) -> Double {
            var e = 0, d = 0
            for id in ids {
                guard let s = w.stats[id] else { continue }
                let ex = expected(id, s, days: w.days)
                e += ex
                d += min(s.done, ex)
            }
            return e == 0 ? 1 : Double(d) / Double(e)
        }
        func avg(_ xs: [Int]) -> Double { Double(xs.reduce(0, +)) / Double(max(xs.count, 1)) }
        var problems: [String] = []
        if rate("sleep") < 0.6 { problems.append("sleep") }
        if w.moods.count >= 3 && avg(w.moods) < 3 { problems.append("mood") }
        if w.energies.count >= 3 && avg(w.energies) < 3 { problems.append("energy") }
        if rate("build") < 0.5 { problems.append("build") }
        if rate("family", "oneone") < 0.6 { problems.append("family") }
        if let g = w.stats["gig"], g.planned > 0, g.done == 0 { problems.append("gig") }
        if rate("lead") < 0.4 { problems.append("lead") }
        if rate("reflect") < 0.5 { problems.append("reflect") }
        if rate("sadhana") < 0.5 { problems.append("sadhana") }
        out += problems.prefix(2).compactMap { msg($0) }

        if let s = skippedSteps(today: today).first {
            let text = s.text.count > 60 ? String(s.text.prefix(57)) + "…" : s.text
            if var m = msg("adjust", ["step": text, "missed": "\(s.planned - s.done)", "planned": "\(s.planned)"]) {
                m.adjust = BlockRef(day: s.day, block: s.block)
                out.append(m)
            }
        }
        if problems.isEmpty, let up = levelUps(today: today).first,
           let m = msg("levelup", ["habit": habitById[up.id]?.title ?? up.id, "pct": "\(up.pct)"]) {
            out.append(m)
        }

        var best: (id: String, n: Int)?
        for h in content.rhythm.habits {
            let n = streak(h.id, today: today)
            if n >= 5 && n > (best?.n ?? 0) { best = (h.id, n) }
        }
        if let best, let m = msg("streak", ["days": "\(best.n)", "habit": habitById[best.id]?.title ?? best.id]) { out.append(m) }

        if problems.isEmpty {
            let total = w.stats.values.reduce(0) { $0 + $1.planned }
            let done = w.stats.values.reduce(0) { $0 + $1.done }
            if let m = msg("strong", ["done": "\(done)", "total": "\(total)"]) { out.append(m) }
        }
        return out
    }

    /// Habit steps and your own steps skipped on days you otherwise used the plan (3+ ticks), over two weeks. Worst first.
    func skippedSteps(today: Date, days n: Int = 14) -> [SkippedStep] {
        guard let first = firstDayKey else { return [] }
        var counts: [String: SkippedStep] = [:]
        var order: [String] = []
        for i in 1...n {
            let d = Day.add(today, -i), k = Day.key(d)
            if k < first { continue }
            let ticked = Set(state.days[k]?.done ?? [])
            if ticked.count < 3 { continue }
            for b in blocks(for: d) {
                for s in b.steps where s.habit != nil || s.custom {
                    if counts[s.key] == nil {
                        counts[s.key] = SkippedStep(key: s.key, text: s.text, block: b.id, day: d)
                        order.append(s.key)
                    }
                    counts[s.key]!.planned += 1
                    if ticked.contains(s.key) { counts[s.key]!.done += 1 }
                }
            }
        }
        return order.compactMap { counts[$0] }
            .filter { $0.planned >= 5 && Double($0.done) <= Double($0.planned) * 0.2 }
            .sorted { ($0.planned - $0.done) > ($1.planned - $1.done) }
    }

    /// Habits done on 90%+ of their expected days for three weeks.
    func levelUps(today: Date) -> [(id: String, pct: Int)] {
        let w = window(end: today, days: 21)
        return content.rhythm.habits.compactMap { h -> (id: String, pct: Int)? in
            guard let s = w.stats[h.id] else { return nil }
            let e = expected(h.id, s, days: w.days)
            let pct = e == 0 ? 0 : Int((Double(min(s.done, e)) / Double(e) * 100).rounded())
            return e >= 10 && pct >= 90 ? (h.id, pct) : nil
        }
        .sorted { $0.pct > $1.pct }
    }

    func greeting(_ minute: Int) -> String {
        let g = content.coach.greetings
        switch minute {
        case ..<(6 * 60): return g["early"] ?? ""
        case ..<(12 * 60): return g["morning"] ?? ""
        case ..<(17 * 60 + 30): return g["afternoon"] ?? ""
        case ..<(21 * 60): return g["evening"] ?? ""
        default: return g["night"] ?? ""
        }
    }

    func wisdom(for d: Date) -> Saying {
        let doy = Day.cal.ordinality(of: .day, in: .year, for: d) ?? 1
        return content.wisdom[doy % content.wisdom.count]
    }

    func lessonDone(_ id: String) -> Bool { state.lessons[id]?.done ?? false }

    func nextLesson(_ trackId: String) -> Lesson? {
        track(trackId)?.lessons.first { !lessonDone($0.id) }
    }

    /// A lesson finished in the last week is still the one you're practising; otherwise the next one.
    func practiceLesson(_ trackId: String) -> Lesson? {
        guard let t = track(trackId) else { return nil }
        let weekAgo = Day.key(Day.add(Date(), -7))
        let recent = t.lessons
            .filter { lessonDone($0.id) }
            .max { (state.lessons[$0.id]?.doneOn ?? "") < (state.lessons[$1.id]?.doneOn ?? "") }
        if let recent, (state.lessons[recent.id]?.doneOn ?? "") >= weekAgo { return recent }
        return nextLesson(trackId)
    }

    func lessonAndTrack(_ id: String) -> (Lesson, Track)? {
        for t in content.tracks { if let l = t.lessons.first(where: { $0.id == id }) { return (l, t) } }
        return nil
    }
}
