import Foundation

/// Estado de la luz en la casa, tal como lo reporta la batería.
enum PowerState: String, Sendable {
    case grid      // hay luz: el router se alimenta de la red
    case battery   // corte de luz: el router se alimenta de la batería
}

/// Lo que la batería FireFly reporta en cada envío.
struct BatteryStatus: Equatable, Sendable {
    var deviceId: String
    var name: String
    var percent: Int
    var state: PowerState
    var charging: Bool
    var solarWatts: Double
    var routerWatts: Double
    /// Minutos que faltan para llegar al 100 % (solo cuando carga).
    var minutesToFull: Int?
    /// Minutos de internet que quedan con el consumo actual (durante un corte).
    var minutesRemaining: Int?
    var gridChargingEnabled: Bool
    var outageStart: Date?
    var lastBatteryUse: Date?
    var firmware: String
    var wifiName: String
    var updatedAt: Date

    /// Autonomía estimada si se fuera la luz ahora.
    var estimatedAutonomyMinutes: Int {
        let usableWh = BatteryStatus.capacityWh * BatteryStatus.usableFraction * Double(percent) / 100
        guard routerWatts > 0 else { return 0 }
        return Int(usableWh / routerWatts * 60)
    }

    /// Batería LiFePO4 12,8 V × 12 Ah.
    static let capacityWh = 153.6
    /// Se usa hasta el 80 % para cuidar la batería.
    static let usableFraction = 0.8
}

/// Un corte de luz registrado por la batería.
struct PowerOutage: Identifiable, Equatable, Sendable {
    var id: String
    var start: Date
    var end: Date
    var energyWh: Double

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Filtros del historial.
enum HistoryPeriod: String, CaseIterable, Identifiable, Sendable {
    case day = "Día"
    case week = "Semana"
    case month = "Mes"
    case year = "Año"
    var id: String { rawValue }
}

/// Usuario que inició sesión.
struct AppUser: Equatable, Sendable {
    var uid: String
    var displayName: String
    var email: String?

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}

/// Contenido del código QR pegado en la batería: `firefly://pair?id=FF-0231&k=CLAVE`.
struct PairingCode: Equatable, Sendable {
    var deviceId: String
    var key: String

    init?(scanned text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comps = URLComponents(string: trimmed), comps.scheme == "firefly" {
            let items = comps.queryItems ?? []
            guard let id = items.first(where: { $0.name == "id" })?.value,
                  let k = items.first(where: { $0.name == "k" })?.value,
                  !id.isEmpty, !k.isEmpty else { return nil }
            deviceId = id.uppercased()
            key = k
            return
        }
        // Ingreso manual: "FF-0231 CLAVE"
        let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == ":" })
        guard parts.count == 2, parts[0].uppercased().hasPrefix("FF-") else { return nil }
        deviceId = parts[0].uppercased()
        key = String(parts[1])
    }
}
