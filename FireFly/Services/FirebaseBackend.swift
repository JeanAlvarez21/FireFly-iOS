import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

/// Datos reales: inicio de sesión con Google (Firebase Auth) y estado de la batería en Firestore.
///
/// Estructura en Firestore:
///   devices/{deviceId}             estado en vivo que escribe la batería (o el simulador)
///   devices/{deviceId}/outages/{id} un documento por cada corte terminado
@MainActor
final class FirebaseBackend: Backend {
    let isDemo = false
    private var db: Firestore { Firestore.firestore() }

    var currentUser: AppUser? {
        guard let u = Auth.auth().currentUser else { return nil }
        return AppUser(uid: u.uid, displayName: u.displayName ?? "Usuario", email: u.email)
    }

    // MARK: Inicio de sesión

    func signInWithGoogle() async throws -> AppUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw BackendError.signInFailed("Falta el CLIENT_ID en GoogleService-Info.plist")
        }
        // Si falta el esquema de URL de Google, GoogleSignIn cerraría la app: mejor avisar.
        let reversed = clientID.split(separator: ".").reversed().joined(separator: ".")
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard schemes.contains(reversed) else {
            throw BackendError.signInFailed("falta REVERSED_CLIENT_ID en project.yml (ver README, paso 3.6)")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = Self.topViewController() else { throw BackendError.missingPresenter }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw BackendError.signInFailed("Google no devolvió el token")
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                       accessToken: result.user.accessToken.tokenString)
        let auth = try await Auth.auth().signIn(with: credential)
        return AppUser(uid: auth.user.uid, displayName: auth.user.displayName ?? "Usuario", email: auth.user.email)
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    // MARK: Vinculación

    func pairedDeviceId(for user: AppUser) async throws -> String? {
        let snap = try await db.collection("devices")
            .whereField("ownerUid", isEqualTo: user.uid)
            .limit(to: 1)
            .getDocuments()
        return snap.documents.first?.documentID
    }

    func pair(_ code: PairingCode, user: AppUser) async throws {
        // Las reglas de Firestore solo aceptan este cambio si la batería no tiene dueño
        // y la clave coincide con la que está guardada en el equipo.
        do {
            try await db.collection("devices").document(code.deviceId).updateData([
                "ownerUid": user.uid,
                "claimKey": code.key,
            ])
        } catch let error as NSError {
            // Códigos de Firestore: 5 = no existe, 7 = permiso denegado (ya tiene dueño o la clave no coincide).
            if error.domain == FirestoreErrorDomain, error.code == 5 { throw BackendError.notFound }
            if error.domain == FirestoreErrorDomain, error.code == 7 { throw BackendError.alreadyPaired }
            throw error
        }
    }

    func unpair(deviceId: String, user: AppUser) async throws {
        try await db.collection("devices").document(deviceId).updateData([
            "ownerUid": NSNull(),
            "claimKey": NSNull(),
        ])
    }

    // MARK: Datos en vivo

    func observeStatus(deviceId: String, onChange: @escaping (BatteryStatus) -> Void) -> Subscription {
        let reg = db.collection("devices").document(deviceId).addSnapshotListener { snap, _ in
            guard let snap, let data = snap.data() else { return }
            onChange(Self.parseStatus(id: snap.documentID, data))
        }
        return FirestoreSubscription(reg)
    }

    func observeOutages(deviceId: String, onChange: @escaping ([PowerOutage]) -> Void) -> Subscription {
        let since = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        let reg = db.collection("devices").document(deviceId).collection("outages")
            .whereField("start", isGreaterThan: Timestamp(date: since))
            .order(by: "start", descending: true)
            .limit(to: 1000)
            .addSnapshotListener { snap, _ in
                guard let snap else { return }
                let list = snap.documents.compactMap { doc -> PowerOutage? in
                    let d = doc.data()
                    guard let s = (d["start"] as? Timestamp)?.dateValue(),
                          let e = (d["end"] as? Timestamp)?.dateValue() else { return nil }
                    return PowerOutage(id: doc.documentID, start: s, end: e, energyWh: Self.double(d["energyWh"]))
                }
                onChange(list)
            }
        return FirestoreSubscription(reg)
    }

    func setGridCharging(deviceId: String, enabled: Bool) async throws {
        try await db.collection("devices").document(deviceId).updateData(["gridChargingEnabled": enabled])
    }

    // MARK: Ayudas

    nonisolated private static func parseStatus(id: String, _ d: [String: Any]) -> BatteryStatus {
        BatteryStatus(
            deviceId: id,
            name: d["name"] as? String ?? "FireFly \(id)",
            percent: Int(double(d["batteryPercent"]).rounded()),
            state: PowerState(rawValue: d["state"] as? String ?? "grid") ?? .grid,
            charging: d["charging"] as? Bool ?? false,
            solarWatts: double(d["solarWatts"]),
            routerWatts: double(d["routerWatts"]),
            minutesToFull: (d["minutesToFull"] as? NSNumber)?.intValue,
            minutesRemaining: (d["minutesRemaining"] as? NSNumber)?.intValue,
            gridChargingEnabled: d["gridChargingEnabled"] as? Bool ?? true,
            outageStart: (d["outageStart"] as? Timestamp)?.dateValue(),
            lastBatteryUse: (d["lastBatteryUse"] as? Timestamp)?.dateValue(),
            firmware: d["firmware"] as? String ?? "—",
            wifiName: d["wifi"] as? String ?? "—",
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
        )
    }

    nonisolated private static func double(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class FirestoreSubscription: Subscription {
    private let registration: ListenerRegistration
    init(_ r: ListenerRegistration) { registration = r }
    func cancel() { registration.remove() }
}
