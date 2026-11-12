import SwiftUI

struct RootView: View {
    @ObservedObject private var web = WebController.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            AlbakovWebView(controller: web)
                .ignoresSafeArea(edges: .bottom)   // сверху — под строкой состояния, как у значка на экране «Домой»; снизу сайт сам учитывает полоску (viewport-fit=cover)
                .opacity(web.firstLoadDone ? 1 : 0)
            if !web.firstLoadDone && !web.failed {
                SplashView()
                    .transition(.opacity)
            }
            if web.failed {
                OfflineView { web.retry() }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: web.firstLoadDone)
        .animation(.easeOut(duration: 0.2), value: web.failed)
        .onAppear { web.start(router.baseURL) }
        .onReceive(router.$pendingURL.compactMap { $0 }) { url in
            web.load(url)
            router.pendingURL = nil
        }
    }
}

// Пока магазин открывается: знак AV на белом и тонкий индикатор.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            ProgressView()
                .tint(Color("AccentColor"))
        }
    }
}

// Нет связи: понятный экран и кнопка «Повторить» вместо белой страницы.
struct OfflineView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 84, height: 84)
                .background(Circle().fill(Color("AccentColor").opacity(0.06)))
            Text("Нет соединения")
                .font(.system(size: 22, weight: .regular))
            Text("Проверьте интернет и попробуйте ещё раз.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Повторить")
                    .font(.system(size: 15, weight: .medium))
                    .kerning(0.6)
                    .frame(maxWidth: 260)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color("AccentColor")))
            }
            .padding(.top, 10)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground").ignoresSafeArea())
    }
}
