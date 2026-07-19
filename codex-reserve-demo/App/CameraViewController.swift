import SwiftUI

private let paper = Color(red: 0.90, green: 0.89, blue: 0.80)
private let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
private let accent = Color(red: 1.00, green: 0.53, blue: 0.18)
private let warning = Color(red: 0.78, green: 0.08, blue: 0.07)

private enum DemoStage { case splash, login, app }

struct ReserveDemoRootView: View {
    @State private var stage: DemoStage = .splash
    var body: some View {
        Group {
            switch stage {
            case .splash: DemoSplashView()
            case .login: DemoLoginView { stage = .app }
            case .app: DemoMainView { stage = .login }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            guard stage == .splash else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { stage = .login }
        }
    }
}

struct DemoShield: View {
    var size: CGFloat = 58
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(ink).frame(width: size, height: size)
            Text("D").font(.system(size: size * 0.52, weight: .black, design: .rounded))
                .foregroundColor(paper)
            Circle().fill(accent).frame(width: size * 0.20, height: size * 0.20)
                .overlay(Image(systemName: "checkmark").font(.system(size: size * 0.10, weight: .black)))
                .offset(x: size * 0.36, y: -size * 0.36)
        }
        .accessibilityLabel("Демонстраційний знак")
    }
}

struct DemoSplashView: View {
    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            VStack(spacing: 24) {
                DemoShield(size: 78)
                Text("Резерв Демо")
                    .font(.system(size: 38, weight: .bold, design: .rounded)).foregroundColor(paper)
                Text("НАВЧАЛЬНИЙ МАКЕТ\nНЕ Є ДОКУМЕНТОМ")
                    .font(.headline).multilineTextAlignment(.center).foregroundColor(accent)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent, lineWidth: 2))
            }
        }
    }
}

struct DemoLoginView: View {
    let enter: () -> Void
    @State private var accepted = false

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 25) {
                    Spacer(minLength: 45)
                    DemoShield(size: 74)
                    Text("Резерв Демо").font(.largeTitle.bold()).foregroundColor(ink)
                    Text("Безпечний навчальний макет інтерфейсу")
                        .font(.subheadline).foregroundColor(ink.opacity(0.58))
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Не підключено до державних реєстрів", systemImage: "wifi.slash")
                        Label("Не створює електронні документи", systemImage: "doc.badge.ellipsis")
                        Label("Усі дані на екрані вигадані", systemImage: "person.crop.circle.badge.questionmark")
                    }
                    .font(.subheadline.weight(.medium)).foregroundColor(ink)
                    .padding(20).background(Color.white.opacity(0.62)).clipShape(RoundedRectangle(cornerRadius: 22))
                    Toggle(isOn: $accepted) {
                        Text("Я розумію, що це лише демонстрація").font(.subheadline.bold())
                    }
                    .tint(accent).padding(.horizontal)
                    Button(action: enter) {
                        Text("Увійти в демо").font(.headline).frame(maxWidth: .infinity).padding(17)
                            .background(accepted ? ink : ink.opacity(0.25)).foregroundColor(paper)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(!accepted).padding(.horizontal)
                    Text("ДЕМО — НЕ Є ДОКУМЕНТОМ")
                        .font(.caption.bold()).foregroundColor(warning)
                    Spacer()
                }.padding()
            }
        }
    }
}

struct DemoMainView: View {
    let logout: () -> Void
    var body: some View {
        TabView {
            DemoProfileView().tabItem { Label("Демо ID", systemImage: "rectangle.portrait") }
            DemoServicesView().tabItem { Label("Сервіси", systemImage: "square.grid.2x2") }
            DemoVacanciesView().tabItem { Label("Можливості", systemImage: "briefcase") }
            DemoMenuView(logout: logout).tabItem { Label("Меню", systemImage: "line.3.horizontal") }
        }
        .tint(ink)
        .safeAreaInset(edge: .top, spacing: 0) { DemoWarningBar() }
    }
}

struct DemoWarningBar: View {
    var body: some View {
        Text("ДЕМО • НЕ Є ДОКУМЕНТОМ")
            .font(.caption2.bold()).tracking(1.2).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 7).background(warning)
    }
}

struct DemoProfileView: View {
    @State private var showingActions = false
    var body: some View {
        NavigationView {
            ZStack {
                paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        HStack {
                            Spacer()
                            Label("Сповіщення", systemImage: "bell.fill")
                                .font(.subheadline.bold()).padding(.horizontal, 15).padding(.vertical, 10)
                                .background(.white).clipShape(Capsule())
                        }
                        DemoIDCard { showingActions = true }
                        Text("Цей екран містить лише тестові дані й не підтверджує особу або статус.")
                            .font(.caption).foregroundColor(ink.opacity(0.58)).multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }.padding()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingActions) { DemoActionsSheet() }
        }.navigationViewStyle(.stack)
    }
}

struct DemoIDCard: View {
    let actions: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Демо ID").font(.title.bold())
                        Text("НАВЧАЛЬНИЙ МАКЕТ").font(.caption.bold()).foregroundColor(warning)
                    }
                    Spacer(); DemoShield(size: 48)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Дата народження:").foregroundColor(ink.opacity(0.55))
                    Text("01.01.2000").font(.title3.bold())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Статус:").foregroundColor(ink.opacity(0.55))
                    Text("ТЕСТОВІ ДАНІ").font(.title3.bold()).foregroundColor(warning)
                }
            }.padding(22)
            Text("ДЕМО • НЕ Є ДОКУМЕНТОМ • ДАНІ ВИГАДАНІ")
                .font(.caption2.bold()).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity).padding(.vertical, 8).background(warning)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Користувач демо").foregroundColor(ink.opacity(0.55))
                    Text("ПРИКЛАД\nТЕСТОВИЙ").font(.title2.bold())
                }
                Spacer()
                Button(action: actions) {
                    Image(systemName: "ellipsis").font(.title2.bold()).foregroundColor(ink)
                        .frame(width: 52, height: 52).background(accent).clipShape(Circle())
                }
            }.padding(22)
        }
        .background(Color(red: 0.85, green: 0.84, blue: 0.74))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct DemoActionsSheet: View {
    @Environment(\.presentationMode) private var presentationMode
    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.gray.opacity(0.5)).frame(width: 58, height: 5).padding(.top, 12)
            DemoShield(size: 52)
            Text("Дії з документом недоступні").font(.title3.bold())
            Text("Демо-версія не завантажує PDF, не оновлює реєстри та не формує документи.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button("Зрозуміло") { presentationMode.wrappedValue.dismiss() }
                .font(.headline).frame(maxWidth: .infinity).padding(15).background(ink).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 15)).padding()
            Spacer()
        }
    }
}

struct DemoServicesView: View {
    private let services = [
        ("Навчальний профіль", "person.text.rectangle"),
        ("Демо-сповіщення", "bell.badge"),
        ("Довідка", "questionmark.circle"),
        ("Безпека даних", "lock.shield")
    ]
    var body: some View {
        NavigationView {
            ZStack {
                paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Демо-сервіси").font(.largeTitle.bold())
                        Text("Приклади розділів без підключення до зовнішніх систем.").foregroundColor(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(services, id: \.0) { service in
                                VStack(alignment: .leading, spacing: 18) {
                                    Image(systemName: service.1).font(.largeTitle).foregroundColor(accent)
                                    Text(service.0).font(.headline).foregroundColor(ink)
                                }
                                .frame(maxWidth: .infinity, minHeight: 125, alignment: .leading)
                                .padding().background(.white.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    }.padding()
                }
            }.navigationBarHidden(true)
        }.navigationViewStyle(.stack)
    }
}

struct DemoVacanciesView: View {
    var body: some View {
        NavigationView {
            ZStack {
                paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Можливості").font(.largeTitle.bold())
                    Text("Вигадані приклади для демонстрації макета.").foregroundColor(.secondary)
                    DemoListCard(title: "Навчальний курс", subtitle: "Онлайн • тестовий запис", icon: "graduationcap.fill")
                    DemoListCard(title: "Волонтерський проєкт", subtitle: "Демо-картка • без реєстрації", icon: "heart.fill")
                    DemoListCard(title: "Практика дизайну", subtitle: "Приклад вакансії", icon: "paintbrush.fill")
                    Spacer()
                }.padding()
            }.navigationBarHidden(true)
        }.navigationViewStyle(.stack)
    }
}

struct DemoListCard: View {
    let title: String; let subtitle: String; let icon: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundColor(accent).frame(width: 44, height: 44)
                .background(ink).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundColor(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundColor(.secondary)
        }.padding().background(.white.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct DemoMenuView: View {
    let logout: () -> Void
    var body: some View {
        NavigationView {
            ZStack {
                paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Меню").font(.largeTitle.bold())
                    DemoListCard(title: "Про демо", subtitle: "Версія 1.0", icon: "info.circle.fill")
                    DemoListCard(title: "Конфіденційність", subtitle: "Дані не надсилаються", icon: "hand.raised.fill")
                    Spacer()
                    Button(action: logout) {
                        Label("Вийти з демо", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline).frame(maxWidth: .infinity).padding(16)
                            .background(ink).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text("ДЕМО — НЕ Є ДОКУМЕНТОМ").font(.caption.bold()).foregroundColor(warning).frame(maxWidth: .infinity)
                }.padding()
            }.navigationBarHidden(true)
        }.navigationViewStyle(.stack)
    }
}
