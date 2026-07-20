import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Сохранение") {
                    Picker("Формат", selection: $settings.outputFormat) {
                        ForEach(PhotoOutputFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    Toggle("Сохранять оригинал", isOn: $settings.saveOriginal)
                    if settings.saveOriginal {
                        Text("Каждый спуск сохранит два файла: исходный и обработанный.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Качество одного кадра") {
                    Picker("Приоритет", selection: $settings.captureQuality) {
                        ForEach(CaptureQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    Text("Thermal Safe автоматически ограничивает Maximum при серьёзном нагреве.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Интерфейс") {
                    Toggle("Сетка 3 × 3", isOn: $settings.gridEnabled)
                    Toggle("Тактильный отклик", isOn: $settings.hapticsEnabled)
                    Toggle("Зеркальное селфи", isOn: $settings.mirrorSelfie)
                }

                Section("Конфиденциальность") {
                    Label("Обработка выполняется на устройстве", systemImage: "lock.shield")
                    Text("Приложение не содержит аналитики, серверной отправки фотографий или сторонних SDK.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("О версии") {
                    LabeledContent("Приложение", value: "LUMORA X")
                    LabeledContent("Версия", value: "1.0.0 (1)")
                    LabeledContent("Этап", value: "Base Camera")
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
