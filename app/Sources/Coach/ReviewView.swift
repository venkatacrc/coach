import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let coach: Coach

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("", selection: $nav.reviewTab) {
                    ForEach(Nav.ReviewTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                switch nav.reviewTab {
                case .evening: evening
                case .week: week
                case .progress: progress
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Review")
    }

    // MARK: Evening

    private static let moods = ["😞", "😕", "😐", "🙂", "😄"]

    private var evening: some View {
        let key = Day.key(nav.date)
        let tomorrow = Day.add(nav.date, 1)
        let planned = coach.planned(nav.date), done = coach.done(nav.date)
        let missed = coach.content.rhythm.habits.filter { planned.contains($0.id) && !done.contains($0.id) }.map(\.title)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Evening review · \(Day.format(nav.date, "EEEEMMMMd"))").font(.headline)
                Text("\(done.count) of \(planned.count) habits done." + (missed.isEmpty ? " A full day. Well done." : " Not today: \(missed.joined(separator: ", ")). That's fine; tomorrow is a new day."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SectionTitle("Mood")
                scale(Self.moods, store.day(key, \.mood))
                SectionTitle("Energy")
                scale(["1", "2", "3", "4", "5"], store.day(key, \.energy))
                SectionTitle("Three wins (small ones count)")
                ForEach(0..<3, id: \.self) { i in
                    TextField("Win \(i + 1)", text: store.day(key, \.wins[i])).textFieldStyle(.roundedBorder)
                }
                SectionTitle("One gratitude")
                TextField("Today I'm grateful for…", text: store.day(key, \.gratitude)).textFieldStyle(.roundedBorder)
                SectionTitle("Notes")
                editor(store.day(key, \.note), minHeight: 90)
            }
            .card()
            VStack(alignment: .leading, spacing: 8) {
                Text("Top 3 for \(Day.format(tomorrow, "EEEE"))").font(.headline)
                Text("These appear at the top of tomorrow's plan.").foregroundStyle(.secondary)
                ForEach(0..<3, id: \.self) { i in
                    TextField(["The one thing that matters most", "Second", "Third"][i], text: store.day(Day.key(tomorrow), \.focus[i]))
                        .textFieldStyle(.roundedBorder)
                }
            }
            .card()
        }
    }

    private func scale(_ labels: [String], _ value: Binding<Int?>) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                let on = value.wrappedValue == i + 1
                Button { value.wrappedValue = on ? nil : i + 1 } label: {
                    Text(label).font(.title3).frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.teal.opacity(0.2) : Color.primary.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.teal : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 420)
    }

    private func editor(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body)
            .frame(minHeight: minHeight)
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
    }

    // MARK: Week

    private static let weekFields: [(WritableKeyPath<WeekLog, String>, String, String)] = [
        (\.wins, "Wins this week", "What went well, at work and at home?"),
        (\.learned, "What I learned", "From lessons, labs, mistakes and people"),
        (\.drained, "What drained my energy", "And what can I change about it?"),
        (\.family, "Family highlight", "A moment with the kids or with your wife"),
        (\.stop, "One thing to stop", "A commitment, a habit, or a meeting"),
    ]
    private static let big3 = [("craft", "🛠 Craft"), ("lead", "🧭 Leadership"), ("gig", "🚀 Gig"), ("family", "🏡 Family")]

    private var week: some View {
        let mon = Day.monday(nav.date)
        let end = Day.add(mon, 7)
        let wk = Day.isoWeek(nav.date)
        let w = coach.window(end: end, days: 7)
        var byArea: [String: HabitCount] = [:]
        for (id, s) in w.stats {
            guard let a = coach.habitById[id]?.area else { continue }
            byArea[a, default: HabitCount()].planned += s.planned
            byArea[a, default: HabitCount()].done += s.done
        }
        let lessons = store.state.lessons.values.filter { $0.done && ($0.doneOn ?? "") >= Day.key(mon) && ($0.doneOn ?? "") < Day.key(end) }.count
        func avg(_ xs: [Int]) -> String { xs.isEmpty ? "–" : String(format: "%.1f", Double(xs.reduce(0, +)) / Double(xs.count)) }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Week \(wk.components(separatedBy: "-W").last ?? "") · \(Day.format(mon, "MMMd")) – \(Day.format(Day.add(mon, 6), "MMMd"))").font(.headline)
                ForEach(coach.content.rhythm.areas.filter { byArea[$0.id] != nil }) { a in
                    let x = byArea[a.id]!
                    HStack {
                        Text("\(a.icon) \(a.title)").frame(width: 160, alignment: .leading)
                        Bar(value: x.planned == 0 ? 0 : Double(x.done) / Double(x.planned), color: Color(hex: a.color))
                        Text("\(x.done)/\(x.planned)").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
                Text("Mood \(avg(w.moods)) · Energy \(avg(w.energies)) · Lessons done \(lessons)").font(.caption).foregroundStyle(.secondary)
            }
            .card()
            VStack(alignment: .leading, spacing: 8) {
                Text("Look back").font(.headline)
                ForEach(Self.weekFields, id: \.1) { path, label, hint in
                    SectionTitle(label)
                    editor(store.week(wk, path), minHeight: 56)
                    Text(hint).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 8) {
                Text("Next week's Big 3").font(.headline)
                Text("One outcome per area. Small and specific beats ambitious and vague.").foregroundStyle(.secondary)
                ForEach(Self.big3, id: \.0) { key, label in
                    HStack {
                        Text(label).frame(width: 120, alignment: .leading)
                        TextField("", text: Binding(
                            get: { store.state.weeks[wk]?.big3[key] ?? "" },
                            set: { v in store.editWeek(wk) { $0.big3[key] = v } }))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .card()
        }
    }

    // MARK: Progress

    private var progress: some View {
        let today = Day.start(Date())
        let days = (0..<28).map { Day.add(today, $0 - 27) }
        let first = coach.firstDayKey
        let w = coach.window(end: Day.add(today, 1), days: 28)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 4 weeks").font(.headline)
                Text("Each dot is a day: filled = done, ring = planned but missed, faint = not planned that day. 🔥 is the current streak.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(coach.content.rhythm.habits.filter { coach.habitOn($0.id) }) { h in
                    let color = coach.color(h.area)
                    let s = w.stats[h.id] ?? HabitCount()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(h.icon) \(h.title)")
                            if let t = coach.habitTarget(h.id) { Text("\(t)× a week").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .frame(width: 170, alignment: .leading)
                        HStack(spacing: 3) {
                            ForEach(days, id: \.self) { d in
                                let k = Day.key(d)
                                Group {
                                    if let first, k >= first {
                                        if !coach.planned(d).contains(h.id) {
                                            Circle().fill(Color.primary.opacity(0.12)).padding(4)
                                        } else if coach.done(d).contains(h.id) {
                                            Circle().fill(color)
                                        } else {
                                            Circle().strokeBorder(color.opacity(0.45), lineWidth: 2)
                                        }
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 13, height: 13)
                                .help(Day.format(d, "EEEMMMd"))
                            }
                        }
                        Spacer()
                        Text("🔥 \(coach.streak(h.id, today: today)) · \(s.planned == 0 ? 0 : Int((coach.rate(h.id, s, days: w.days) * 100).rounded()))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text("Mood and energy").font(.headline)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(days, id: \.self) { d in
                        let log = store.state.days[Day.key(d)]
                        HStack(alignment: .bottom, spacing: 1) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#e64980")).frame(height: CGFloat(log?.mood ?? 0) * 16)
                            RoundedRectangle(cornerRadius: 2).fill(Color.teal).frame(height: CGFloat(log?.energy ?? 0) * 16)
                        }
                        .help(Day.format(d, "EEEMMMd"))
                    }
                }
                .frame(height: 82, alignment: .bottom)
                HStack(spacing: 12) {
                    Label("mood", systemImage: "square.fill").foregroundStyle(Color(hex: "#e64980"))
                    Label("energy", systemImage: "square.fill").foregroundStyle(.teal)
                    Spacer()
                    Text("\(store.state.lessons.values.filter(\.done).count) lessons done in total").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .card()
        }
    }
}
