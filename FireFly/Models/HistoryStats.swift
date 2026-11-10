import Foundation

/// Una barra del gráfico de consumo.
struct ConsumptionBar: Identifiable, Equatable {
    var id: Int
    var label: String
    var energyWh: Double
}

/// Totales y barras del historial para un periodo.
struct HistorySummary: Equatable {
    var outageCount: Int
    var totalDuration: TimeInterval
    var totalEnergyWh: Double
    var caption: String
    var bars: [ConsumptionBar]
}

enum HistoryStats {
    static func summary(for period: HistoryPeriod, outages: [PowerOutage], now: Date = .now,
                        calendar: Calendar = .firefly) -> HistorySummary {
        let cal = calendar
        let interval: DateInterval
        var bars: [ConsumptionBar]
        let caption: String
        let es = Locale(identifier: "es_EC")

        switch period {
        case .day:
            interval = cal.dateInterval(of: .day, for: now)!
            // Barras cada 2 horas, de 0h a 22h.
            bars = stride(from: 0, to: 24, by: 2).map { ConsumptionBar(id: $0, label: "\($0)h", energyWh: 0) }
            caption = now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(es)).capitalizedFirst
        case .week:
            interval = cal.dateInterval(of: .weekOfYear, for: now)!
            let names = ["L", "M", "M", "J", "V", "S", "D"]
            bars = names.enumerated().map { ConsumptionBar(id: $0.offset, label: $0.element, energyWh: 0) }
            let last = interval.end.addingTimeInterval(-1)
            caption = "\(interval.start.formatted(.dateTime.day().locale(es))) al \(last.formatted(.dateTime.day().month(.wide).locale(es)))"
        case .month:
            interval = cal.dateInterval(of: .month, for: now)!
            let weeks = cal.range(of: .weekOfMonth, in: .month, for: now)?.count ?? 5
            bars = (0..<weeks).map { ConsumptionBar(id: $0, label: "S\($0 + 1)", energyWh: 0) }
            caption = now.formatted(.dateTime.month(.wide).year().locale(es)).capitalizedFirst
        case .year:
            interval = cal.dateInterval(of: .year, for: now)!
            let names = ["E", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
            bars = names.enumerated().map { ConsumptionBar(id: $0.offset, label: $0.element, energyWh: 0) }
            caption = now.formatted(.dateTime.year().locale(es))
        }

        let inPeriod = outages.filter { interval.contains($0.start) }
        for o in inPeriod {
            let index: Int
            switch period {
            case .day: index = cal.component(.hour, from: o.start) / 2
            case .week: index = (cal.component(.weekday, from: o.start) + 5) % 7  // lunes = 0
            case .month: index = cal.component(.weekOfMonth, from: o.start) - 1
            case .year: index = cal.component(.month, from: o.start) - 1
            }
            if bars.indices.contains(index) { bars[index].energyWh += o.energyWh }
        }
        return HistorySummary(
            outageCount: inPeriod.count,
            totalDuration: inPeriod.reduce(0) { $0 + $1.duration },
            totalEnergyWh: inPeriod.reduce(0) { $0 + $1.energyWh },
            caption: caption,
            bars: bars)
    }
}

extension Calendar {
    /// Semanas de lunes a domingo, como se usa en Ecuador.
    static var firefly: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_EC")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 1
        return c
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

enum Formatters {
    /// 135 min → «2 h 15 min»
    static func minutes(_ total: Int) -> String {
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) h" }
        return "\(h) h \(m) min"
    }

    static func duration(_ seconds: TimeInterval) -> String { minutes(Int((seconds / 60).rounded())) }

    static func energy(_ wh: Double) -> String {
        wh >= 1000 ? String(format: "%.1f kWh", wh / 1000).replacingOccurrences(of: ".", with: ",")
                   : "\(Int(wh.rounded())) Wh"
    }

    static func watts(_ w: Double) -> String {
        w.rounded() == w ? "\(Int(w)) W" : String(format: "%.1f W", w).replacingOccurrences(of: ".", with: ",")
    }

    static let es = Locale(identifier: "es_EC")

    /// «Mié 21 oct»
    static func shortDay(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(es))
            .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "").capitalizedFirst
    }

    private static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_EC")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Hora en formato de 24 horas: «16:40»
    static func time(_ d: Date) -> String { hourMinute.string(from: d) }

    /// «21/10/2026, 16:40»
    static func dateTime(_ d: Date) -> String {
        "\(d.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(es))), \(time(d))"
    }
}
