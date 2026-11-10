import SwiftUI
import UserNotifications
import FirebaseCore
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// true cuando hay `GoogleService-Info.plist` en la app y Firebase quedó configurado.
    static var firebaseConfigured = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            AppDelegate.firebaseConfigured = true
        }
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Muestra los avisos también cuando la app está abierta.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct FireFlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView()
                        .environment(model)
                } else {
                    Theme.background.ignoresSafeArea()
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
            }
            .task {
                guard model == nil else { return }
                // Sin GoogleService-Info.plist la app arranca en modo demo.
                let backend: Backend = AppDelegate.firebaseConfigured ? FirebaseBackend() : DemoBackend()
                let m = AppModel(backend: backend)
                model = m
                await m.start()
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                ProgressView().tint(Theme.accent)
            case .signedOut:
                LoginView()
            case .needsPairing:
                PairingView()
            case .ready:
                MainTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fireflyScreen()
        .ignoresSafeArea(.keyboard)
        .animation(.easeOut(duration: 0.25), value: model.phase)
    }
}
