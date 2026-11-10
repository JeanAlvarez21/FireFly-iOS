import SwiftUI
import Charts

/// Pantalla 4 · Historial y estadísticas, con filtros Día / Semana / Mes / Año
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var period: HistoryPeriod = .week

    var body: some View {
        let summary = HistoryStats.summary(for: period, outages: model.outages)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Historial de cortes").font(Theme.display(28))
                    Text(lastOutageText).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }

                // Filtros tipo píldora (cambio pedido en la prueba del hackathon)
                HStack(spacing: 8) {
                    ForEach(HistoryPeriod.allCases) { p in
                        Button(p.rawValue) { withAnimation(.easeOut(duration: 0.2)) { period = p } }
                            .font(.system(size: 14, weight: p == period ? .bold : .medium))
                            .foregroundStyle(p == period ? Theme.onAccent : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(p == period ? Theme.accent : Theme.surface, in: .capsule)
                            .overlay(Capsule().stroke(p == period ? .clear : Theme.border))
                            .accessibilityAddTraits(p == period ? .isSelected : [])
                    }
                }

                HStack(spacing: 10) {
                    StatTile(title: "Cortes", value: "\(summary.outageCount)")
                    StatTile(title: "Sin luz", value: Formatters.duration(summary.totalDuration))
                    StatTile(title: "Energía usada", value: Formatters.energy(summary.totalEnergyWh))
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Consumo de energía").font(.system(size: 16, weight: .bold))
                        Spacer()
                        Text(summary.caption).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    Chart(summary.bars) { bar in
                        BarMark(x: .value("Periodo", "\(bar.id)"), y: .value("Wh", bar.energyWh), width: .ratio(0.55))
                            .foregroundStyle(bar.energyWh > 0 ? Theme.accent : Theme.border)
                            .cornerRadius(6)
                            .accessibilityLabel(bar.label)
                            .accessibilityValue(Formatters.energy(bar.energyWh))
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let s = value.as(String.self), let i = Int(s),
                                   let bar = summary.bars.first(where: { $0.id == i }) {
                                    Text(bar.label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 150)
                    Text("Vatios-hora (Wh) que usó el router con la batería.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
                .background(Theme.surface, in: .rect(cornerRadius: 20))

                Text("Últimos cortes").font(.system(size: 16, weight: .bold)).padding(.top, 4)
                if model.outages.isEmpty {
                    Card { Text("Todavía no hay cortes registrados.").foregroundStyle(Theme.textSecondary) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.outages.prefix(5).enumerated()), id: \.element.id) { index, o in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Formatters.shortDay(o.start)).font(.system(size: 14, weight: .semibold))
                                    Text("\(Formatters.time(o.start)) – \(Formatters.time(o.end))")
                                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Text("\(Formatters.duration(o.duration)) · \(Formatters.energy(o.energyWh))")
                                    .font(.system(size: 13))
                            }
                            .padding(.vertical, 12).padding(.horizontal, 16)
                            if index < min(5, model.outages.count) - 1 { Divider().overlay(Theme.divider) }
                        }
                    }
                    .background(Theme.surface, in: .rect(cornerRadius: 18))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .fireflyScreen()
    }

    private var lastOutageText: String {
        guard let o = model.outages.first else { return "Sin cortes registrados" }
        return "Último corte: \(o.start.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(Formatters.es))) · \(Formatters.time(o.start)) – \(Formatters.time(o.end))"
    }
}

struct StatTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 18, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}
