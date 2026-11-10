import Foundation

/// Modo demo: la batería se simula dentro del teléfono. Se usa cuando la app no tiene
/// `GoogleService-Info.plist` (Firebase sin configurar) o para mostrar la app sin hardware.
/// Los datos que genera son de ejemplo y la app lo indica en pantalla.
@MainActor
final class DemoBackend: Backend {
    let isDemo = true
    private let defaults = UserDefaults.standard
    private var status: BatteryStatus
    private var outages: [PowerOutage]
    private var statusObservers: [UUID: (BatteryStatus) -> Void] = [:]
    private var outageObservers: [UUID: ([PowerOutage]) -> Void] = [:]
    private var timer: Timer?

    /// Cada tic del temporizador (3 s) avanza 5 minutos simulados.
    private let simulatedMinutesPerTick = 5.0

    init() {
        status = BatteryStatus(
            deviceId: "FF-0231", name: "FireFly FF-0231", percent: 75, state: .grid, charging: true,
            solarWatts: 18, routerWatts: 9.8, minutesToFull: 120, minutesRemaining: nil,
            gridChargingEnabled: true, outageStart: nil,
            lastBatteryUse: Calendar.current.date(byAdding: .day, value: -1, to: .now),
            firmware: "1.0.3", wifiName: "Casa", updatedAt: .now)
        outages = DemoBackend.sampleHistory()
        status.lastBatteryUse = outages.first?.end
    }

    var currentUser: AppUser? {
        guard defaults.bool(forKey: "demo.signedIn") else { return nil }
        return AppUser(uid: "demo", displayName: "Juan (demo)", email: nil)
    }

    func signInWithGoogle() async throws -> AppUser {
        try? await Task.sleep(for: .milliseconds(400))
        defaults.set(true, forKey: "demo.signedIn")
        return currentUser!
    }

    func signOut() throws {
        defaults.set(false, forKey: "demo.signedIn")
        defaults.removeObject(forKey: "demo.device")
    }

    func pairedDeviceId(for user: AppUser) async throws -> String? {
        defaults.string(forKey: "demo.device")
    }

    func pair(_ code: PairingCode, user: AppUser) async throws {
        try? await Task.sleep(for: .milliseconds(600))
        status.deviceId = code.deviceId
        status.name = "FireFly \(code.deviceId)"
        defaults.set(code.deviceId, forKey: "demo.device")
    }

    func unpair(deviceId: String, user: AppUser) async throws {
        defaults.removeObject(forKey: "demo.device")
    }

    func observeStatus(deviceId: String, onChange: @escaping (BatteryStatus) -> Void) -> Subscription {
        let id = UUID()
        statusObservers[id] = onChange
        onChange(status)
        startTimerIfNeeded()
        return DemoSubscription { [weak self] in self?.statusObservers[id] = nil }
    }

    func observeOutages(deviceId: String, onChange: @escaping ([PowerOutage]) -> Void) -> Subscription {
        let id = UUID()
        outageObservers[id] = onChange
        onChange(outages)
        return DemoSubscription { [weak self] in self?.outageObservers[id] = nil }
    }

    func setGridCharging(deviceId: String, enabled: Bool) async throws {
        status.gridChargingEnabled = enabled
        recompute()
        publish()
    }

    func simulatePowerToggle(deviceId: String) {
        if status.state == .grid {
            status.state = .battery
            status.outageStart = .now
        } else {
            if let start = status.outageStart {
                let minutes = max(1, Date.now.timeIntervalSince(start) / 60 * (simulatedMinutesPerTick / 0.05))
                let end = start.addingTimeInterval(minutes * 60)
                let wh = status.routerWatts * minutes / 60
                outages.insert(PowerOutage(id: UUID().uuidString, start: start, end: end, energyWh: wh), at: 0)
                status.lastBatteryUse = end
                outageObservers.values.forEach { $0(outages) }
            }
            status.state = .grid
            status.outageStart = nil
        }
        recompute()
        publish()
    }

    // MARK: Simulación

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let hour = Double(Calendar.current.component(.hour, from: .now))
        // Curva solar simple: 0 W de noche, hasta ~22 W al mediodía.
        let sun = max(0, sin((hour - 6) / 12 * .pi))
        status.solarWatts = (sun * 22).rounded()
        let usableWh = BatteryStatus.capacityWh * BatteryStatus.usableFraction
        var pct = Double(status.percent)
        if status.state == .battery {
            let netW = status.routerWatts - status.solarWatts
            pct -= max(0, netW) * simulatedMinutesPerTick / 60 / usableWh * 100
        } else {
            let chargeW = status.solarWatts + (status.gridChargingEnabled ? 30 : 0)
            pct += chargeW * simulatedMinutesPerTick / 60 / usableWh * 100
        }
        status.percent = Int(min(100, max(0, pct)).rounded())
        recompute()
        publish()
    }

    private func recompute() {
        let usableWh = BatteryStatus.capacityWh * BatteryStatus.usableFraction
        let pct = Double(status.percent)
        if status.state == .battery {
            status.charging = false
            status.minutesToFull = nil
            // Estimación conservadora: solo el consumo del router (el sol, si hay, la alarga).
            status.minutesRemaining = Int(usableWh * pct / 100 / max(0.5, status.routerWatts) * 60)
        } else {
            let chargeW = status.solarWatts + (status.gridChargingEnabled ? 30 : 0)
            status.charging = chargeW > 0 && status.percent < 100
            status.minutesRemaining = nil
            status.minutesToFull = status.charging ? Int(usableWh * (100 - pct) / 100 / chargeW * 60) : nil
        }
        status.updatedAt = .now
    }

    private func publish() {
        statusObservers.values.forEach { $0(status) }
    }

    /// Historial de ejemplo de los últimos 70 días para que las gráficas tengan datos.
    private static func sampleHistory() -> [PowerOutage] {
        var rng = SeededGenerator(seed: 231)
        var list: [PowerOutage] = []
        let cal = Calendar.current
        for daysAgo in 1...70 {
            guard Double.random(in: 0...1, using: &rng) < 0.35,
                  let day = cal.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }
            let startHour = Int.random(in: 7...20, using: &rng)
            let minutes = Double(Int.random(in: 40...240, using: &rng))
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = startHour
            comps.minute = Int.random(in: 0...59, using: &rng)
            guard let start = cal.date(from: comps) else { continue }
            let end = start.addingTimeInterval(minutes * 60)
            list.append(PowerOutage(id: "demo-\(daysAgo)", start: start, end: end, energyWh: (9.8 * minutes / 60).rounded()))
        }
        return list.sorted { $0.start > $1.start }
    }
}

private final class DemoSubscription: Subscription {
    private var onCancel: (() -> Void)?
    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() { onCancel?(); onCancel = nil }
}

/// Generador pseudoaleatorio con semilla para que el historial de ejemplo sea siempre el mismo.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
