import SwiftUI

struct RootView: View {
    @ObservedObject private var web = WebController.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            AlbakovWebView(controller: web)
                .ignoresSafeArea(edges: .bottom)   // сверху — под строкой состояния; снизу сайт сам учитывает полоску (viewport-fit=cover)
                .opacity(web.ready ? 1 : 0)
            if !web.ready && !web.failed {
                SplashView()
                    .transition(.opacity)
            }
            if web.failed {
                OfflineView { web.retry() }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: web.ready)
        .animation(.easeOut(duration: 0.2), value: web.failed)
        .onAppear { web.start(router.baseURL) }
        .onReceive(router.$pendingURL.compactMap { $0 }) { url in
            web.load(url)
            router.pendingURL = nil
        }
    }
}

// Знак AV и надпись ALBAKOV — как в шапке сайта, под ними тонкая линия загрузки.
// Своей заставки у сайта в приложении нет: эта держится, пока магазин не будет готов.
struct BrandMark: View {
    var body: some View {
        VStack(spacing: 22) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
            HStack(alignment: .top, spacing: 2) {
                Image("Wordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)
                Text("®")
                    .font(.system(size: 6, weight: .regular))
                    .foregroundStyle(Color("AccentColor").opacity(0.85))
                    .offset(y: -3)
            }
        }
    }
}

struct SplashView: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 28) {
            BrandMark()
            ZStack(alignment: .leading) {
                Rectangle().fill(Color("AccentColor").opacity(0.12))
                Rectangle().fill(Color("AccentColor")).frame(width: 150 * progress)
            }
            .frame(width: 150, height: 1)
        }
        .onAppear { withAnimation(.timingCurve(0.25, 0.7, 0.3, 1, duration: 2.6)) { progress = 0.82 } }
    }
}

// Нет связи: понятный экран и кнопка «Повторить». Связь вернулась — магазин откроется сам.
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
            Text("Проверьте интернет — магазин откроется сам, как только связь появится.")
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
