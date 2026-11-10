import SwiftUI

/// Pantalla 1 · Inicio de sesión
struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                FireflyLogo()
                Text("FireFly").font(Theme.display(20))
                Spacer()
                if model.isDemo { DemoBadge() }
            }

            Spacer()

            VStack(spacing: 28) {
                RouterIllustration()
                VStack(spacing: 10) {
                    Text("¡Bienvenido de vuelta!")
                        .font(Theme.display(32))
                        .multilineTextAlignment(.center)
                    Text("Revisa tu batería y tus cortes de luz desde el celular.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                }
                Button {
                    Task { await model.signIn() }
                } label: {
                    HStack(spacing: 12) {
                        Text("G")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1F2937))
                            .frame(width: 28, height: 28)
                            .background(.white, in: .circle)
                        if model.isBusy {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text("Acceder con Google")
                        }
                    }
                }
                .buttonStyle(.primary)
                .disabled(model.isBusy)

                Button("Cambiar usuario") {
                    model.signOut()
                    Task { await model.signIn() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)

                Text("Solo usamos tu cuenta para guardar tu batería y tu historial.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
}

struct FireflyLogo: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.16)).frame(width: 26, height: 26)
            Circle().fill(Theme.accent).frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}

struct RouterIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: 196, height: 196)
                .shadow(color: Theme.accent.opacity(0.22), radius: 30)
            VStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Image(systemName: "wifi.router")
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(Theme.text)
            }
        }
        .accessibilityLabel("Router con batería de respaldo")
    }
}
