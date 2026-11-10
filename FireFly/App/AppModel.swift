import Foundation
import Observation

/// Estado central de la app: sesión, batería vinculada y datos en vivo.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut
        case needsPairing
        case ready
    }

    let backend: Backend
    private let notifier = Notifier()

    var phase: Phase = .launching
    var user: AppUser?
    var deviceId: String?
    var status: BatteryStatus?
    var outages: [PowerOutage] = []
    var errorMessage: String?
    var isBusy = false

    private var statusSub: Subscription?
    private var outagesSub: Subscription?
    private var lowBatteryNotified = false

    var isDemo: Bool { backend.isDemo }

    init(backend: Backend) {
        self.backend = backend
    }

    func start() async {
        guard let user = backend.currentUser else { phase = .signedOut; return }
        self.user = user
        await loadDevice()
    }

    // MARK: Sesión

    func signIn() async {
        await run {
            let user = try await self.backend.signInWithGoogle()
            self.user = user
            await self.notifier.requestPermission()
            await self.loadDevice()
        }
    }

    func signOut() {
        stopObserving()
        try? backend.signOut()
        user = nil
        deviceId = nil
        status = nil
        outages = []
        phase = .signedOut
    }

    // MARK: Vinculación

    func pair(with scanned: String) async -> Bool {
        guard let code = PairingCode(scanned: scanned) else {
            errorMessage = BackendError.invalidCode.localizedDescription
            return false
        }
        guard let user else { return false }
        var ok = false
        await run {
            try await self.backend.pair(code, user: user)
            self.deviceId = code.deviceId
            ok = true
        }
        return ok
    }

    /// Después de ver la confirmación, entra al panel.
    func finishPairing() {
        guard let deviceId else { return }
        startObserving(deviceId)
        phase = .ready
    }

    func unpair() async {
        guard let user, let deviceId else { return }
        await run {
            try await self.backend.unpair(deviceId: deviceId, user: user)
            self.stopObserving()
            self.deviceId = nil
            self.status = nil
            self.outages = []
            self.phase = .needsPairing
        }
    }

    // MARK: Acciones del panel

    func setGridCharging(_ enabled: Bool) async {
        guard let deviceId else { return }
        status?.gridChargingEnabled = enabled
        await run { try await self.backend.setGridCharging(deviceId: deviceId, enabled: enabled) }
    }

    func simulatePowerToggle() {
        guard let deviceId else { return }
        backend.simulatePowerToggle(deviceId: deviceId)
    }

    // MARK: Interno

    private func loadDevice() async {
        guard let user else { return }
        do {
            if let id = try await backend.pairedDeviceId(for: user) {
                deviceId = id
                startObserving(id)
                phase = .ready
            } else {
                phase = .needsPairing
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .needsPairing
        }
    }

    private func startObserving(_ id: String) {
        stopObserving()
        statusSub = backend.observeStatus(deviceId: id) { [weak self] new in
            self?.handle(new)
        }
        outagesSub = backend.observeOutages(deviceId: id) { [weak self] list in
            self?.outages = list
        }
    }

    private func stopObserving() {
        statusSub?.cancel(); statusSub = nil
        outagesSub?.cancel(); outagesSub = nil
    }

    private func handle(_ new: BatteryStatus) {
        let old = status
        status = new
        guard let old else { return }
        if old.state == .grid, new.state == .battery {
            let time = Formatters.time(new.outageStart ?? .now)
            notifier.send(.outage, title: "Se fue la luz",
                          body: "Desde las \(time). Tu router sigue con internet gracias a la batería.")
            lowBatteryNotified = false
        }
        if old.state == .battery, new.state == .grid {
            let duration = old.outageStart.map { Formatters.duration(Date.now.timeIntervalSince($0)) } ?? ""
            notifier.send(.restored, title: "Volvió la luz",
                          body: duration.isEmpty ? "La batería vuelve a cargarse." : "El corte duró \(duration).")
        }
        if new.state == .battery, new.percent <= 20, !lowBatteryNotified {
            lowBatteryNotified = true
            let left = Formatters.minutes(new.minutesRemaining ?? 0)
            notifier.send(.lowBattery, title: "Batería baja", body: "Queda el \(new.percent) %, unos \(left) de internet.")
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await work() } catch { errorMessage = error.localizedDescription }
    }
}
