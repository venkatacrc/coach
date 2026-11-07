import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav

    var body: some View {
        NavigationSplitView {
            List(Nav.Section.allCases, selection: $nav.section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .safeAreaInset(edge: .bottom) { SidebarSummary().padding(12) }
        } detail: {
            if let coach = store.coach {
                Group {
                    switch nav.section ?? .today {
                    case .today: TodayView(coach: coach)
                    case .grow: GrowView(coach: coach)
                    case .review: ReviewView(coach: coach)
                    case .plan: PlanView(coach: coach)
                    }
                }
                .toolbar { toolbar }
                .sheet(item: $nav.lessonId) { id in LessonView(coach: store.coach ?? coach, lessonId: id) }
                .sheet(item: $nav.editingBlock) { ref in
                    BlockEditor(coach: store.coach ?? coach, ref: ref) { nav.editingBlock = nil }
                }
            } else {
                ContentUnavailableView("No content", systemImage: "exclamationmark.triangle", description: Text(store.errorMessage ?? ""))
            }
        }
        .alert("Coach", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let section = nav.section ?? .today
        if section == .today || (section == .review && nav.reviewTab != .progress) {
            let step = section == .review && nav.reviewTab == .week ? 7 : 1
            ToolbarItemGroup(placement: .navigation) {
                Button { nav.date = Day.add(nav.date, -step) } label: { Image(systemName: "chevron.left") }
                Button(dateLabel(weekly: step == 7)) { nav.date = Day.start(Date()) }
                    .help("Back to today (⌘T)")
                Button { nav.date = Day.add(nav.date, step) } label: { Image(systemName: "chevron.right") }
            }
        }
    }

    private func dateLabel(weekly: Bool) -> String {
        if weekly {
            let mon = Day.monday(nav.date)
            return "\(Day.format(mon, "MMMd")) – \(Day.format(Day.add(mon, 6), "MMMd"))"
        }
        switch Day.key(nav.date) {
        case Day.key(Date()): return "Today"
        case Day.key(Day.add(Date(), -1)): return "Yesterday"
        case Day.key(Day.add(Date(), 1)): return "Tomorrow"
        default: return Day.format(nav.date, "EEEMMMd")
        }
    }
}

struct SidebarSummary: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let coach = store.coach {
            let today = Day.start(Date())
            let planned = coach.planned(today), done = coach.done(today)
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.caption.bold()).foregroundStyle(.secondary)
                ProgressView(value: Double(done.count), total: Double(max(planned.count, 1))).tint(.teal)
                Text("\(done.count) of \(planned.count) habits").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared pieces

struct CardStyle: ViewModifier {
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(alignment: .leading) {
                if let accent { UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14).fill(accent).frame(width: 5) }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}

extension View {
    func card(accent: Color? = nil) -> some View { modifier(CardStyle(accent: accent)) }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary).kerning(0.5)
    }
}

struct Bar: View {
    let value: Double
    var color: Color = .teal
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

extension Coach {
    func color(_ areaId: String) -> Color { Color(hex: area(areaId)?.color ?? "#868e96") }
}
