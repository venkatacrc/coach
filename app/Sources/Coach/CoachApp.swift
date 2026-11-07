import AppKit
import SwiftUI
@preconcurrency import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if Notifier.available { UNUserNotificationCenter.current().delegate = self }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
final class Nav: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case today = "Today", grow = "Grow", review = "Review", plan = "Plan"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .grow: return "books.vertical"
            case .review: return "book.closed"
            case .plan: return "target"
            }
        }
    }

    enum ReviewTab: String, CaseIterable { case evening = "Evening", week = "Week", progress = "Progress" }

    @Published var section: Section? = .today
    @Published var date = Day.start(Date())
    @Published var reviewTab = ReviewTab.evening
    @Published var lessonId: String?
    @Published var openTracks: Set<String> = []
    @Published var openBlocks: Set<String> = []
    var openBlocksFor = ""
    @Published var quarter = Day.quarter(Date())
    @Published var rhythmDay = Day.weekday(Date())
    @Published var editingGoal: Goal?
    @Published var editingGoalIsNew = false
    @Published var editingBlock: BlockRef?

    var isToday: Bool { Day.key(date) == Day.key(Date()) }

    /// Each new day opens with only the current (or next) block expanded.
    func resetOpenBlocks(_ dayKey: String, _ block: ResolvedBlock?) {
        guard openBlocksFor != dayKey else { return }
        openBlocksFor = dayKey
        openBlocks = block.map { [$0.id] } ?? []
    }
}

extension String: @retroactive Identifiable { public var id: String { self } }

@main
struct CoachMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()
    @StateObject private var nav = Nav()
    @AppStorage("notifyBlocks") private var notifyBlocks = false

    var body: some Scene {
        WindowGroup("Coach", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(nav)
                .frame(minWidth: 940, minHeight: 640)
                .task { if notifyBlocks, let coach = store.coach { Notifier.schedule(coach) } }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Backup…") { store.importBackup() }
                    .keyboardShortcut("o")
                Button("Export Backup…") { store.exportBackup() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Erase All Data…") { store.reset() }
            }
            CommandMenu("Go") {
                ForEach(Array(Nav.Section.allCases.enumerated()), id: \.offset) { i, s in
                    Button(s.rawValue) { nav.section = s }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
                Button("Previous Day") { nav.date = Day.add(nav.date, -1) }
                    .keyboardShortcut("[")
                Button("Next Day") { nav.date = Day.add(nav.date, 1) }
                    .keyboardShortcut("]")
                Button("Back to Today") { nav.date = Day.start(Date()) }
                    .keyboardShortcut("t")
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(nav)
        } label: {
            Image(systemName: "safari")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Reminders at the start of each block over the next two days. Needs the bundled .app;
/// `swift run` has no bundle identifier, and the notification center refuses to start without one.
enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    @MainActor
    static func schedule(_ coach: Coach) {
        guard available else { return }
        var requests: [UNNotificationRequest] = []
        let now = Date()
        for offset in 0...1 {
            let day = Day.add(now, offset)
            for b in coach.blocks(for: day) {
                guard let fire = Day.cal.date(byAdding: .minute, value: b.start, to: day), fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(Day.clock(b.start)) · \(b.title)"
                content.body = b.steps.first(where: { $0.habit != nil })?.text ?? b.why ?? ""
                content.sound = .default
                let parts = Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                requests.append(UNNotificationRequest(identifier: "coach-\(Day.key(day))-\(b.id)", content: content, trigger: trigger))
            }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            requests.forEach { center.add($0) }
        }
    }

    static func cancel() {
        guard available else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

/// The menu bar: what's happening now, its steps to tick, and the next block.
struct MenuBarView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let coach = store.coach {
                let today = Day.start(context.date)
                let key = Day.key(today)
                let now = Day.nowMinutes(context.date)
                let blocks = coach.blocks(for: today)
                let current = blocks.first { now >= $0.start && now < $0.end }
                let next = blocks.first { $0.start > now }
                let done = Set(store.state.days[key]?.done ?? [])
                VStack(alignment: .leading, spacing: 10) {
                    if let b = current {
                        let color = Color(hex: coach.area(b.area)?.color ?? "#0f766e")
                        HStack {
                            Text("NOW").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(color, in: Capsule()).foregroundStyle(.white)
                            Text(b.title).font(.headline)
                            Spacer()
                            Text("\(Day.duration(b.end - now)) left").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(now - b.start), total: Double(b.end - b.start)).tint(color)
                        ForEach(b.steps) { s in
                            Toggle(isOn: Binding(get: { done.contains(s.key) }, set: { _ in store.toggleStep(s.key, day: key) })) {
                                Text(s.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                            .toggleStyle(.checkbox)
                        }
                    } else {
                        Text(next == nil ? "Day complete. Sleep well." : "Free time").font(.headline)
                    }
                    if let n = next {
                        Divider()
                        Text("Next at \(Day.clock(n.start)): \(n.title)").font(.caption).foregroundStyle(.secondary)
                    }
                    let planned = coach.planned(today), habitsDone = coach.done(today)
                    Text("\(habitsDone.count) of \(planned.count) habits today").font(.caption).foregroundStyle(.secondary)
                    Button("Open Coach") {
                        nav.section = .today
                        nav.date = today
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .padding(14)
                .frame(width: 340)
            }
        }
    }
}
