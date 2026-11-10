import Foundation

/// Algo que se puede cancelar (un listener de Firestore o un temporizador del modo demo).
protocol Subscription: AnyObject {
    func cancel()
}

enum BackendError: LocalizedError {
    case invalidCode
    case alreadyPaired
    case notFound
    case missingPresenter
    case signInFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "El código no es de una batería FireFly."
        case .alreadyPaired: return "Esta batería ya está vinculada a otra cuenta."
        case .notFound: return "No encontramos esa batería. Revisa el código."
        case .missingPresenter: return "No se pudo abrir el inicio de sesión."
        case .signInFailed(let msg): return "No se pudo iniciar sesión: \(msg)"
        }
    }
}

/// Todo lo que la app necesita de la nube. Hay dos versiones:
/// `FirebaseBackend` (datos reales en Firestore) y `DemoBackend` (simulación dentro del teléfono).
@MainActor
protocol Backend: AnyObject {
    var isDemo: Bool { get }
    var currentUser: AppUser? { get }

    func signInWithGoogle() async throws -> AppUser
    func signOut() throws

    /// Busca la batería que ya tiene vinculada el usuario.
    func pairedDeviceId(for user: AppUser) async throws -> String?
    func pair(_ code: PairingCode, user: AppUser) async throws
    func unpair(deviceId: String, user: AppUser) async throws

    func observeStatus(deviceId: String, onChange: @escaping (BatteryStatus) -> Void) -> Subscription
    func observeOutages(deviceId: String, onChange: @escaping ([PowerOutage]) -> Void) -> Subscription
    func setGridCharging(deviceId: String, enabled: Bool) async throws

    /// Solo en modo demo: simula que se va o vuelve la luz.
    func simulatePowerToggle(deviceId: String)
}

extension Backend {
    func simulatePowerToggle(deviceId: String) {}
}
