import AVFoundation
import Combine
import Speech
import SwiftUI
import UserNotifications

private let neonCyan = Color(red: 0.08, green: 0.95, blue: 1.00)
private let neonPurple = Color(red: 0.68, green: 0.18, blue: 1.00)
private let neonPink = Color(red: 1.00, green: 0.12, blue: 0.62)
private let amuletBackground = Color(red: 0.018, green: 0.025, blue: 0.065)

struct AmuletNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var reminderAt: Date?
    var isDone: Bool
}

struct WorkSession: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var startedAt: Date
    var duration: TimeInterval
}

private struct AmuletArchive: Codable {
    var notes: [AmuletNote]
    var sessions: [WorkSession]
}

final class AmuletStore: ObservableObject {
    static let shared = AmuletStore()
    @Published var notes: [AmuletNote] = [] { didSet { persist() } }
    @Published var sessions: [WorkSession] = [] { didSet { persist() } }
    private let storageKey = "neon.amulet.archive.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let archive = try? JSONDecoder().decode(AmuletArchive.self, from: data) {
            notes = archive.notes
            sessions = archive.sessions
        }
    }

    func saveNote(_ note: AmuletNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
        notes.sort { $0.updatedAt > $1.updatedAt }
        ReminderCenter.update(for: note)
    }

    func deleteNotes(at offsets: IndexSet, from visible: [AmuletNote]) {
        let ids = offsets.map { visible[$0].id }
        ids.forEach { ReminderCenter.cancel(id: $0) }
        notes.removeAll { ids.contains($0.id) }
    }

    func toggleDone(_ note: AmuletNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isDone.toggle()
        notes[index].updatedAt = Date()
        if notes[index].isDone { ReminderCenter.cancel(id: note.id) }
        else { ReminderCenter.update(for: notes[index]) }
    }

    func addSession(name: String, duration: TimeInterval) {
        sessions.insert(
            WorkSession(id: UUID(), name: name.isEmpty ? "Фокус-сессия" : name,
                        startedAt: Date(), duration: duration),
            at: 0
        )
    }

    private func persist() {
        let archive = AmuletArchive(notes: notes, sessions: sessions)
        if let data = try? JSONEncoder().encode(archive) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

enum ReminderCenter {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func update(for note: AmuletNote) {
        cancel(id: note.id)
        guard !note.isDone, let date = note.reminderAt, date > Date() else { return }
        requestPermission()
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.text.isEmpty ? "Пора выполнить запланированное дело" : note.text
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let request = UNNotificationRequest(identifier: note.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }
}

final class SpeechTranscriber: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var status = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() }
        else { authorizeAndStart() }
    }

    private func authorizeAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] result in
            DispatchQueue.main.async {
                guard result == .authorized else {
                    self?.status = "Разреши распознавание речи в настройках iPhone"
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        guard allowed else {
                            self?.status = "Нужен доступ к микрофону"
                            return
                        }
                        self?.start()
                    }
                }
            }
        }
    }

    private func start() {
        task?.cancel()
        task = nil
        transcript = ""
        status = "Говори — текст появится в заметке"

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = "Не удалось включить микрофон"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isRecording = true
        } catch {
            input.removeTap(onBus: 0)
            status = "Не удалось начать запись"
            return
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let text = result?.bestTranscription.formattedString {
                    self?.transcript = text
                }
                if result?.isFinal == true || error != nil { self?.stop() }
            }
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        if !transcript.isEmpty { status = "Диктовка добавлена" }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct NeonAmuletAppView: View {
    var body: some View {
        ZStack {
            AmuletBackground()
            TabView {
                NotesView()
                    .tabItem { Label("Заметки", systemImage: "note.text") }
                ReminderListView()
                    .tabItem { Label("Планы", systemImage: "bell.badge") }
                FocusTimerView()
                    .tabItem { Label("Таймер", systemImage: "timer") }
                ReportView()
                    .tabItem { Label("Отчёт", systemImage: "chart.bar.fill") }
            }
            .accentColor(neonCyan)
        }
        .preferredColorScheme(.dark)
    }
}

struct AmuletBackground: View {
    var body: some View {
        LinearGradient(
            colors: [amuletBackground, Color(red: 0.055, green: 0.015, blue: 0.12), amuletBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(colors: [neonPurple.opacity(0.22), .clear], center: .topTrailing,
                           startRadius: 10, endRadius: 340)
        )
        .ignoresSafeArea()
    }
}

struct AmuletLogo: View {
    @State private var pulse = false
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            Circle().stroke(neonPurple.opacity(0.45), lineWidth: 2)
                .frame(width: size * 1.25, height: size * 1.25)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .opacity(pulse ? 0.35 : 0.8)
            Circle().stroke(
                AngularGradient(colors: [neonCyan, neonPurple, neonPink, neonCyan], center: .center),
                lineWidth: 4
            )
            .frame(width: size, height: size)
            .shadow(color: neonCyan.opacity(0.8), radius: 12)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [neonCyan, neonPink], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: size * 1.35, height: size * 1.35)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct NeonHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            AmuletLogo(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold()).foregroundColor(.white)
                Text(subtitle).font(.caption).foregroundColor(neonCyan.opacity(0.82))
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

struct NeonCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .background(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(LinearGradient(colors: [neonCyan.opacity(0.6), neonPurple.opacity(0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: neonPurple.opacity(0.20), radius: 12, y: 5)
    }
}

struct NotesView: View {
    @EnvironmentObject private var store: AmuletStore
    @State private var search = ""
    @State private var editing: AmuletNote?
    @State private var creating = false

    private var visible: [AmuletNote] {
        guard !search.isEmpty else { return store.notes }
        return store.notes.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmuletBackground()
                VStack(spacing: 8) {
                    NeonHeader(title: "NEON AMULET", subtitle: "мысли, голос и планы")
                    SearchBar(text: $search)
                    if visible.isEmpty {
                        Spacer()
                        VStack(spacing: 18) {
                            AmuletLogo(size: 82)
                            Text(search.isEmpty ? "Создай первую заметку" : "Ничего не найдено")
                                .font(.headline).foregroundColor(.white.opacity(0.8))
                            if search.isEmpty {
                                Button("Новая заметка") { creating = true }
                                    .buttonStyle(NeonButtonStyle())
                            }
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(visible) { note in
                                Button { editing = note } label: { NoteRow(note: note) }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            .onDelete { store.deleteNotes(at: $0, from: visible) }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .bottomTrailing) {
                Button { creating = true } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundColor(.black)
                        .frame(width: 58, height: 58)
                        .background(neonCyan).clipShape(Circle())
                        .shadow(color: neonCyan.opacity(0.8), radius: 14)
                }
                .padding(22)
            }
            .sheet(isPresented: $creating) { NoteEditorView(note: nil) }
            .sheet(item: $editing) { NoteEditorView(note: $0) }
        }
        .navigationViewStyle(.stack)
    }
}

struct SearchBar: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(neonCyan)
            TextField("Поиск заметок", text: $text).foregroundColor(.white)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") } }
        }
        .padding(12)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal)
    }
}

struct NoteRow: View {
    let note: AmuletNote
    var body: some View {
        NeonCard {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(note.isDone ? Color.green : neonPurple)
                    .frame(width: 9, height: 9).shadow(color: note.isDone ? .green : neonPurple, radius: 7)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title).font(.headline).foregroundColor(note.isDone ? .gray : .white)
                        .strikethrough(note.isDone)
                    if !note.text.isEmpty {
                        Text(note.text).font(.subheadline).foregroundColor(.white.opacity(0.58)).lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Text(note.updatedAt, style: .date)
                        if let reminder = note.reminderAt {
                            Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: "bell.fill")
                                .foregroundColor(neonPink)
                        }
                    }
                    .font(.caption2).foregroundColor(.white.opacity(0.42))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(neonCyan.opacity(0.65))
            }
        }
        .padding(.vertical, 4)
    }
}

struct NoteEditorView: View {
    @EnvironmentObject private var store: AmuletStore
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var speech = SpeechTranscriber()
    private let original: AmuletNote?
    @State private var title: String
    @State private var text: String
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var speechBase = ""

    init(note: AmuletNote?) {
        original = note
        _title = State(initialValue: note?.title ?? "")
        _text = State(initialValue: note?.text ?? "")
        _hasReminder = State(initialValue: note?.reminderAt != nil)
        _reminderDate = State(initialValue: note?.reminderAt ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmuletBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        AmuletLogo(size: 58)
                        NeonCard {
                            TextField("Название", text: $title)
                                .font(.title3.bold()).foregroundColor(.white)
                            Divider().background(neonPurple.opacity(0.5))
                            TextEditor(text: $text)
                                .frame(minHeight: 210)
                                .foregroundColor(.white)
                                .background(Color.clear)
                        }
                        Button {
                            if !speech.isRecording {
                                speechBase = text + (text.isEmpty ? "" : " ")
                            }
                            speech.toggle()
                        } label: {
                            HStack {
                                Image(systemName: speech.isRecording ? "stop.circle.fill" : "waveform.circle.fill")
                                    .font(.title2)
                                Text(speech.isRecording ? "Остановить диктовку" : "Диктовать голосом").bold()
                            }
                            .frame(maxWidth: .infinity).padding(14)
                            .foregroundColor(speech.isRecording ? .white : .black)
                            .background(speech.isRecording ? neonPink : neonCyan)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: (speech.isRecording ? neonPink : neonCyan).opacity(0.65), radius: 12)
                        }
                        if !speech.status.isEmpty {
                            Text(speech.status).font(.caption).foregroundColor(.white.opacity(0.68))
                        }
                        NeonCard {
                            Toggle("Напомнить", isOn: $hasReminder).tint(neonPink)
                            if hasReminder {
                                DatePicker("Когда", selection: $reminderDate,
                                           in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(original == nil ? "Новая заметка" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { speech.stop(); presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.foregroundColor(neonCyan)
                }
            }
            .onChange(of: speech.transcript) { value in text = speechBase + value }
            .onDisappear { speech.stop() }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        speech.stop()
        let now = Date()
        let note = AmuletNote(
            id: original?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Без названия" : title,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: original?.createdAt ?? now,
            updatedAt: now,
            reminderAt: hasReminder ? reminderDate : nil,
            isDone: original?.isDone ?? false
        )
        store.saveNote(note)
        presentationMode.wrappedValue.dismiss()
    }
}

struct ReminderListView: View {
    @EnvironmentObject private var store: AmuletStore
    private var planned: [AmuletNote] {
        store.notes.filter { $0.reminderAt != nil }.sorted { ($0.reminderAt ?? .distantFuture) < ($1.reminderAt ?? .distantFuture) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmuletBackground()
                VStack {
                    NeonHeader(title: "ПЛАНЫ", subtitle: "что и когда нужно сделать")
                    if planned.isEmpty {
                        Spacer()
                        AmuletLogo(size: 80)
                        Text("Добавь дату напоминания в заметке")
                            .foregroundColor(.white.opacity(0.65)).padding()
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(planned) { note in
                                    NeonCard {
                                        HStack {
                                            Button { store.toggleDone(note) } label: {
                                                Image(systemName: note.isDone ? "checkmark.circle.fill" : "circle")
                                                    .font(.title2).foregroundColor(note.isDone ? .green : neonCyan)
                                            }
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(note.title).bold().strikethrough(note.isDone)
                                                if let date = note.reminderAt {
                                                    Text(date.formatted(date: .long, time: .shortened))
                                                        .font(.caption).foregroundColor(neonPink)
                                                }
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }.padding()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }.navigationViewStyle(.stack)
    }
}

struct FocusTimerView: View {
    @EnvironmentObject private var store: AmuletStore
    @State private var name = "Фокус-сессия"
    @State private var accumulated: TimeInterval = 0
    @State private var runningSince: Date?
    @State private var now = Date()
    @State private var savedMessage = ""
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var total: TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmuletBackground()
                VStack(spacing: 24) {
                    NeonHeader(title: "ТАЙМЕР", subtitle: "следи за временем и результатом")
                    Spacer()
                    AmuletLogo(size: 112)
                    Text(formatClock(total))
                        .font(.system(size: 54, weight: .thin, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: neonCyan, radius: 12)
                    TextField("Название задачи", text: $name)
                        .multilineTextAlignment(.center).padding(13)
                        .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 30)
                    HStack(spacing: 16) {
                        Button(runningSince == nil ? "Старт" : "Пауза") { toggleTimer() }
                            .buttonStyle(NeonButtonStyle(color: runningSince == nil ? neonCyan : neonPink))
                        Button("Сброс") { reset() }
                            .buttonStyle(NeonButtonStyle(color: neonPurple))
                    }
                    Button("Сохранить в отчёт") { saveSession() }
                        .disabled(total < 1)
                        .foregroundColor(total < 1 ? .gray : neonCyan)
                    if !savedMessage.isEmpty { Text(savedMessage).font(.caption).foregroundColor(.green) }
                    Text("Таймер учитывает время даже при временном сворачивании приложения.")
                        .font(.caption).foregroundColor(.white.opacity(0.42)).multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .onReceive(ticker) { now = $0 }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }.navigationViewStyle(.stack)
    }

    private func toggleTimer() {
        savedMessage = ""
        if let start = runningSince {
            accumulated += Date().timeIntervalSince(start)
            runningSince = nil
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            runningSince = Date()
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private func reset() {
        accumulated = 0
        runningSince = nil
        now = Date()
        savedMessage = ""
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func saveSession() {
        let value = total
        guard value >= 1 else { return }
        store.addSession(name: name, duration: value)
        savedMessage = "Сессия добавлена в отчёт"
        accumulated = 0
        runningSince = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

struct ReportView: View {
    @EnvironmentObject private var store: AmuletStore
    private var today: TimeInterval {
        store.sessions.filter { Calendar.current.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.duration }
    }
    private var week: TimeInterval {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return store.sessions.filter { interval.contains($0.startedAt) }.reduce(0) { $0 + $1.duration }
    }
    private var all: TimeInterval { store.sessions.reduce(0) { $0 + $1.duration } }

    var body: some View {
        NavigationView {
            ZStack {
                AmuletBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        NeonHeader(title: "ОТЧЁТ", subtitle: "твоё время и завершённые дела")
                        HStack(spacing: 10) {
                            MetricCard(title: "Сегодня", value: compactDuration(today), color: neonCyan)
                            MetricCard(title: "Неделя", value: compactDuration(week), color: neonPurple)
                            MetricCard(title: "Всего", value: compactDuration(all), color: neonPink)
                        }.padding(.horizontal)
                        NeonCard {
                            HStack {
                                Label("Выполнено заметок", systemImage: "checkmark.seal.fill").foregroundColor(.white)
                                Spacer()
                                Text("\(store.notes.filter { $0.isDone }.count)").font(.title2.bold()).foregroundColor(.green)
                            }
                        }.padding(.horizontal)
                        HStack { Text("Последние сессии").font(.headline); Spacer() }.padding(.horizontal)
                        if store.sessions.isEmpty {
                            Text("Сохрани первую сессию таймера")
                                .foregroundColor(.white.opacity(0.5)).padding(.top, 30)
                        } else {
                            ForEach(store.sessions.prefix(30)) { session in
                                NeonCard {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session.name).bold()
                                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption).foregroundColor(.white.opacity(0.48))
                                        }
                                        Spacer()
                                        Text(compactDuration(session.duration)).foregroundColor(neonCyan).bold()
                                    }
                                }.padding(.horizontal)
                            }
                        }
                    }.padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }.navigationViewStyle(.stack)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 7) {
            Text(value).font(.headline).foregroundColor(color).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption2).foregroundColor(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 15)
        .background(Color.white.opacity(0.055))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: color.opacity(0.25), radius: 8)
    }
}

struct NeonButtonStyle: ButtonStyle {
    var color: Color = neonCyan
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).foregroundColor(.black)
            .padding(.horizontal, 24).padding(.vertical, 13)
            .background(color.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .shadow(color: color.opacity(0.65), radius: configuration.isPressed ? 4 : 11)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private func formatClock(_ interval: TimeInterval) -> String {
    let value = max(0, Int(interval))
    return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
}

private func compactDuration(_ interval: TimeInterval) -> String {
    let minutes = max(0, Int(interval / 60))
    if minutes < 1 { return "< 1 мин" }
    if minutes < 60 { return "\(minutes) мин" }
    return String(format: "%d ч %02d м", minutes / 60, minutes % 60)
}
