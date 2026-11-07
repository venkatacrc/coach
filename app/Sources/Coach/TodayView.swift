import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let coach: Coach

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let date = nav.date
            let key = Day.key(date)
            let isToday = key == Day.key(context.date)
            let now = Day.nowMinutes(context.date)
            let blocks = coach.blocks(for: date)
            let current = isToday ? blocks.first { now >= $0.start && now < $0.end } : nil
            let next = isToday ? blocks.first { $0.start > now } : nil
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 14) {
                        hero(date: date, isToday: isToday, now: now, current: current, next: next)
                        focus(key: key)
                        coachCard(date: date)
                    }
                    .frame(width: 340)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Your day · \(coach.template(for: date).title)")
                        ForEach(blocks) { b in
                            BlockCard(coach: coach, block: b, dayKey: key, day: date,
                                      phase: current?.id == b.id ? .now : (isToday && b.end <= now ? .past : .later),
                                      isOpen: nav.openBlocks.contains(b.id)) {
                                if nav.openBlocks.contains(b.id) { nav.openBlocks.remove(b.id) } else { nav.openBlocks.insert(b.id) }
                            }
                        }
                        Button("+ Add a block to this day") { nav.editingBlock = BlockRef(day: date, block: nil) }
                            .buttonStyle(.link)
                    }
                }
                .padding(20)
            }
            .onAppear { nav.resetOpenBlocks(key, current ?? next) }
            .onChange(of: key) { _, k in nav.resetOpenBlocks(k, current ?? next) }
        }
        .navigationTitle(Day.format(nav.date, "EEEEMMMMd"))
    }

    private func hero(date: Date, isToday: Bool, now: Int, current: ResolvedBlock?, next: ResolvedBlock?) -> some View {
        let planned = coach.planned(date), done = coach.done(date)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? coach.greeting(now) : coach.template(for: date).title).font(.title3.bold())
                    Text("\(Day.format(date, "EEEEMMMMd")) · \(coach.template(for: date).title) plan")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 7)
                    Circle().trim(from: 0, to: planned.isEmpty ? 0 : Double(done.count) / Double(planned.count))
                        .stroke(Color.teal, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(done.count)/\(planned.count)").font(.callout.bold())
                }
                .frame(width: 56, height: 56)
            }
            if let b = current {
                let color = coach.color(b.area)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Now").font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(color, in: Capsule()).foregroundStyle(.white)
                        Text(b.title).bold()
                        Spacer()
                        Text("\(Day.duration(b.end - now)) left").font(.callout).foregroundStyle(.secondary)
                    }
                    Bar(value: Double(now - b.start) / Double(b.end - b.start), color: color)
                    if let n = next {
                        Text("Next at \(Day.clock(n.start)): \(n.title)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            } else if isToday {
                Text(next.map { "Next at \(Day.clock($0.start)): \($0.title)" } ?? "Day complete. Sleep well.")
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 6) {
                ForEach(coach.content.rhythm.habits.filter { planned.contains($0.id) }) { h in
                    Text(h.icon)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(done.contains(h.id) ? coach.color(h.area).opacity(0.2) : .clear))
                        .overlay(Circle().stroke(coach.color(h.area).opacity(done.contains(h.id) ? 1 : 0.35), lineWidth: 2))
                        .grayscale(done.contains(h.id) ? 0 : 1)
                        .opacity(done.contains(h.id) ? 1 : 0.5)
                        .help(h.title)
                }
            }
        }
        .card(accent: .teal)
    }

    private func focus(key: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 3 today").font(.headline)
            ForEach(0..<3, id: \.self) { i in
                HStack {
                    Toggle("", isOn: store.day(key, \.focusDone[i])).toggleStyle(.checkbox).labelsHidden()
                    TextField(["The one thing that matters most", "Second", "Third"][i], text: store.day(key, \.focus[i]))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .card()
    }

    private func coachCard(date: Date) -> some View {
        let w = coach.wisdom(for: date)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Coach").font(.headline)
            ForEach(coach.messages(today: date)) { m in
                HStack(alignment: .top, spacing: 10) {
                    Text(m.icon).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).bold()
                        Text(m.text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let ref = m.adjust {
                            Button("🔧 Adjust") { nav.editingBlock = ref }.controlSize(.small).padding(.top, 4)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(w.text).italic(w.meaning != nil)
                    .foregroundStyle(w.meaning != nil ? Color(hex: "#b6501a") : .primary)
                if let meaning = w.meaning { Text(meaning) }
                Text(w.source).font(.caption.bold()).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .card(accent: .teal)
    }
}

struct BlockCard: View {
    enum Phase { case past, now, later }

    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let coach: Coach
    let block: ResolvedBlock
    let dayKey: String
    let day: Date
    let phase: Phase
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        let color = coach.color(block.area)
        let done = Set(store.state.days[dayKey]?.done ?? [])
        let n = block.steps.filter { done.contains($0.key) }.count
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Day.clock(block.start)).font(.callout.bold()).foregroundStyle(color)
                        Text(Day.clock(block.end)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 64, alignment: .leading)
                    Text(block.title).font(.body.weight(.semibold))
                    if phase == .now {
                        Text("Now").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color, in: Capsule()).foregroundStyle(.white)
                    }
                    Spacer()
                    Text("\(n)/\(block.steps.count)").font(.callout.weight(.semibold))
                        .foregroundStyle(n == block.steps.count ? .green : .secondary)
                    Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen ? 90 : 0)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    if let why = block.why {
                        Text(why).italic().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(block.steps) { s in step(s, done: done.contains(s.key)) }
                    HStack {
                        Spacer()
                        Button("✎ Adjust this block") { nav.editingBlock = BlockRef(day: day, block: block.id) }
                            .buttonStyle(.link).font(.callout)
                    }
                }
                .padding(.top, 12)
            }
        }
        .card(accent: color)
        .opacity(phase == .past ? 0.75 : 1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(phase == .now ? 0.6 : 0), lineWidth: 2))
    }

    private func step(_ s: ResolvedStep, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Toggle(isOn: Binding(get: { done }, set: { _ in store.toggleStep(s.key, day: dayKey) })) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(s.text).strikethrough(done, color: .secondary).foregroundStyle(done ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let h = s.habit.flatMap({ coach.habitById[$0] }) { Text(h.icon).font(.caption).help("Counts toward \(h.title)") }
                }
            }
            .toggleStyle(.checkbox)
            HStack(spacing: 8) {
                if let app = s.app.flatMap({ coach.app($0) }) {
                    Button { store.open(app) } label: { Text("\(app.icon) \(app.name) ↗") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                if let tid = s.track, let t = coach.track(tid) {
                    if let l = coach.nextLesson(tid) {
                        Button { nav.lessonId = l.id } label: { Text("\(t.icon) \(l.title)") }
                            .buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Text("\(t.icon) \(t.title): all lessons done 🎉").font(.caption)
                    }
                }
                if let action = s.action {
                    Button(action == "week" ? "🗓 Weekly review" : "📓 Evening review") {
                        nav.reviewTab = action == "week" ? .week : .evening
                        nav.section = .review
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(.leading, 22)
            if let tid = s.practice, let l = coach.practiceLesson(tid) {
                Button { nav.lessonId = l.id } label: {
                    (Text("This week: ").bold() + Text(coach.fill(l.practice)))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary.opacity(0.5)))
                .padding(.leading, 22)
            }
        }
    }
}
