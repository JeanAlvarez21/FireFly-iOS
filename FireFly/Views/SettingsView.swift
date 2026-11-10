import SwiftUI

/// Pantalla 5 · Ajustes
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var notifyOutage = Notifier.isEnabled(.outage)
    @State private var notifyLow = Notifier.isEnabled(.lowBattery)
    @State private var notifyRestored = Notifier.isEnabled(.restored)
    @State private var confirmUnpair = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ajustes").font(Theme.display(28))

                section("Dispositivo")
                group {
                    row("Batería", model.status?.name ?? model.deviceId ?? "—")
                    divider
                    row("Red Wi‑Fi", model.status?.wifiName ?? "—")
                    divider
                    row("Versión del equipo", model.status?.firmware ?? "—")
                }

                section("Avisos")
                group {
                    toggle("Se fue la luz", "Te avisamos que el router pasó a batería", $notifyOutage, .outage)
                    divider
                    toggle("Batería baja", "Cuando quede el 20 %", $notifyLow, .lowBattery)
                    divider
                    toggle("Volvió la luz", "Con la duración del corte", $notifyRestored, .restored)
                }

                if model.isDemo {
                    section("Modo demo")
                    group {
                        Button {
                            model.simulatePowerToggle()
                        } label: {
                            HStack {
                                Text(model.status?.state == .battery ? "Simular que volvió la luz" : "Simular un corte de luz")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Image(systemName: "bolt.fill")
                            }
                            .foregroundStyle(Theme.warning)
                            .frame(minHeight: 48)
                            .padding(.horizontal, 16)
                        }
                    }
                    Text("En modo demo los datos se generan en el teléfono. Con Firebase configurado, los envía la batería o el simulador.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }

                section("Cuenta")
                group {
                    row("Cuenta de Google", model.user?.firstName ?? "—")
                    divider
                    Button("Vincular otra batería") { confirmUnpair = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 16)
                    divider
                    Button("Cerrar sesión") { model.signOut() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .fireflyScreen()
        .confirmationDialog("¿Desvincular esta batería?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Desvincular y escanear otra", role: .destructive) { Task { await model.unpair() } }
        } message: {
            Text("Dejarás de ver su estado y su historial en esta cuenta.")
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 6)
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.surface, in: .rect(cornerRadius: 18))
    }

    private var divider: some View { Divider().overlay(Theme.divider) }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15))
            Spacer()
            Text(value).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    private func toggle(_ title: String, _ detail: String, _ value: Binding<Bool>, _ kind: Notifier.Kind) -> some View {
        Toggle(isOn: Binding(get: { value.wrappedValue }, set: { v in
            value.wrappedValue = v
            Notifier.setEnabled(kind, v)
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
