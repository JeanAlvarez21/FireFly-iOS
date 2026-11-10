import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Inicio", systemImage: "house") { PanelView() }
            Tab("Estadísticas", systemImage: "chart.bar") { HistoryView() }
            Tab("Ajustes", systemImage: "gearshape") { SettingsView() }
        }
        .tint(Theme.accent)
    }
}

/// Pantallas 3 y 3b · Panel principal (con luz y durante un corte)
struct PanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let s = model.status {
                content(s)
            } else {
                ProgressView("Conectando con tu batería…")
                    .tint(Theme.accent)
                    .padding(.top, 120)
            }
        }
        .scrollIndicators(.hidden)
        .fireflyScreen()
    }

    @ViewBuilder private func content(_ s: BatteryStatus) -> some View {
        let outage = s.state == .battery
        VStack(alignment: .leading, spacing: 16) {
            // Encabezado
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hola, \(model.user?.firstName ?? "")").font(Theme.display(28))
                    Text("Batería del dispositivo · \(s.deviceId)")
                        .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(outage ? Theme.warning : Theme.accent).frame(width: 8, height: 8)
                    Text(outage ? "Con batería" : "Con luz").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.surface, in: .capsule)
                .accessibilityElement(children: .combine)
            }

            if model.isDemo { DemoBadge() }

            if outage {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.slash").foregroundStyle(Theme.warning)
                    Text("Se fue la luz a las \(Formatters.time(s.outageStart ?? .now)). Tu router sigue con internet.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0xFFE2B8))
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x2B2212), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x5C4418)))
            }

            // Lo más importante: el tiempo (aprendido en la prueba del hackathon)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(heroLabel(s)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                    Text(heroValue(s))
                        .font(Theme.display(38))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(heroDetail(s)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BatteryRing(percent: s.percent,
                            label: outage ? "En uso" : (s.charging ? "Cargando" : "Llena"),
                            color: outage ? Theme.warning : Theme.accent)
            }
            .padding(.vertical, 22).padding(.horizontal, 20)
            .background(Theme.surface, in: .rect(cornerRadius: 24))

            HStack(spacing: 12) {
                MiniCard(title: "Panel solar", value: Formatters.watts(s.solarWatts), icon: "sun.max", iconColor: Theme.accent)
                MiniCard(title: "Router", value: Formatters.watts(s.routerWatts), icon: "wifi.router", iconColor: Theme.textSecondary)
            }

            Card {
                Toggle(isOn: Binding(get: { s.gridChargingEnabled },
                                     set: { v in Task { await model.setGridCharging(v) } })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cargar también con la corriente").font(.system(size: 15, weight: .semibold))
                        Text("Durante un corte, el cambio a batería es automático. Esto solo decide si se carga con la red cuando hay luz.")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .tint(Theme.accent)
            }

            Text(outage ? "Corte actual desde las \(Formatters.time(s.outageStart ?? .now))."
                        : "Último uso de la batería: \(s.lastBatteryUse.map(Formatters.dateTime) ?? "todavía no").")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func heroLabel(_ s: BatteryStatus) -> String {
        if s.state == .battery { return "Internet restante" }
        return s.charging ? "Carga completa en" : "Batería"
    }

    private func heroValue(_ s: BatteryStatus) -> String {
        if s.state == .battery { return Formatters.minutes(s.minutesRemaining ?? s.estimatedAutonomyMinutes) }
        if s.charging, let m = s.minutesToFull { return Formatters.minutes(m) }
        return "Lista"
    }

    private func heroDetail(_ s: BatteryStatus) -> String {
        if s.state == .battery { return "Calculado con el consumo actual del router." }
        return "Si se va la luz, tu internet dura unas \(Formatters.minutes(roundedHours(s.estimatedAutonomyMinutes)))."
    }

    /// Redondea a la media hora para que la estimación no parezca más exacta de lo que es.
    private func roundedHours(_ minutes: Int) -> Int { (minutes + 15) / 30 * 30 }
}

/// Anillo sólido con el porcentaje centrado.
struct BatteryRing: View {
    var percent: Int
    var label: String
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.border, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: percent)
            VStack(spacing: 2) {
                Text("\(percent)%").font(.system(size: 20, weight: .bold)).contentTransition(.numericText())
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 88, height: 88)
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Batería al \(percent) por ciento, \(label)")
    }
}

struct MiniCard: View {
    var title: String
    var value: String
    var icon: String
    var iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .labelStyle(TintedIconLabelStyle(color: iconColor))
            Text(value).font(.system(size: 22, weight: .bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
    }
}

struct TintedIconLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}
