import SwiftUI

struct GrowView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let coach: Coach

    var body: some View {
        let all = coach.content.tracks.flatMap(\.lessons)
        let doneAll = all.filter { coach.lessonDone($0.id) }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Five tracks, \(all.count) lessons. Each lesson has one idea, one practice for the week, and one question. \(doneAll) done so far.")
                        .foregroundStyle(.secondary)
                    Bar(value: Double(doneAll) / Double(max(all.count, 1)), height: 10)
                }
                .card()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(coach.content.tracks) { t in trackCard(t) }
                }
            }
            .padding(20)
        }
        .navigationTitle("Grow")
    }

    private func trackCard(_ t: Track) -> some View {
        let color = coach.color(t.area)
        let n = t.lessons.filter { coach.lessonDone($0.id) }.count
        let open = nav.openTracks.contains(t.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if open { nav.openTracks.remove(t.id) } else { nav.openTracks.insert(t.id) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(t.icon).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.headline)
                        Text(t.subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("\(n)/\(t.lessons.count)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Bar(value: Double(n) / Double(t.lessons.count), color: color)
            if !open, let next = coach.nextLesson(t.id) {
                Button { nav.lessonId = next.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT").font(.caption2.bold()).foregroundStyle(color)
                        Text(next.title).bold()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            if open {
                VStack(spacing: 0) {
                    ForEach(t.lessons) { l in
                        let done = coach.lessonDone(l.id)
                        Button { nav.lessonId = l.id } label: {
                            HStack(spacing: 10) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(color)
                                Text(l.title).foregroundStyle(done ? .secondary : .primary)
                                if !(store.state.lessons[l.id]?.note ?? "").isEmpty { Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .card(accent: color)
    }
}

struct LessonView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) private var dismiss
    let coach: Coach
    let lessonId: String

    var body: some View {
        if let (lesson, track) = coach.lessonAndTrack(lessonId) {
            let color = coach.color(track.area)
            let idx = track.lessons.firstIndex { $0.id == lesson.id } ?? 0
            let done = store.state.lessons[lesson.id]?.done ?? false
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(track.icon) \(track.title) · \(idx + 1) of \(track.lessons.count)").font(.callout.bold()).foregroundStyle(color)
                        Text(lesson.title).font(.title2.bold())
                        Text(coach.fill(lesson.idea)).font(.body).lineSpacing(3)
                        callout("Practice this week", coach.fill(lesson.practice), color, italic: false)
                        callout("Ask yourself", coach.fill(lesson.ask), color.opacity(0.6), italic: true)
                        let free = (lesson.read ?? []).filter { $0.url != nil }
                        let books = (lesson.read ?? []).filter { $0.url == nil }
                        if !free.isEmpty {
                            SectionTitle("Read (free)")
                            ForEach(free, id: \.self) { r in
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    if let s = r.url, let url = URL(string: s) { Link("\(r.title) ↗", destination: url).bold() }
                                    if let by = r.by { Text("· \(by)").foregroundStyle(.secondary) }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !books.isEmpty {
                            SectionTitle("Go deeper")
                            ForEach(books, id: \.self) { r in
                                HStack(spacing: 4) {
                                    Text(r.title).italic()
                                    if let by = r.by { Text("· \(by)").foregroundStyle(.secondary) }
                                }
                            }
                        }
                        SectionTitle("My notes")
                        TextEditor(text: store.lessonNote(lesson.id))
                            .font(.body)
                            .frame(minHeight: 110)
                            .padding(6)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                    }
                    .padding(24)
                    .textSelection(.enabled)
                }
                Divider()
                HStack {
                    Button(done ? "✓ Done (undo)" : "Mark done") {
                        store.editLesson(lesson.id) { l in
                            l.done.toggle()
                            l.doneOn = l.done ? Day.key(Date()) : nil
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(done ? .gray : .teal)
                    if idx + 1 < track.lessons.count {
                        Button("Next ›") { nav.lessonId = track.lessons[idx + 1].id }
                    }
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .padding(16)
            }
            .frame(width: 620, height: 680)
        }
    }

    private func callout(_ title: String, _ text: String, _ color: Color, italic: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(color)
            Text(text).italic(italic).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}
