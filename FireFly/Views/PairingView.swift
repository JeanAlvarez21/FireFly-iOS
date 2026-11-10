import SwiftUI
import VisionKit

/// Pantallas 2 y 2b · Vincular batería con el código QR
struct PairingView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning = false
    @State private var paired = false
    @State private var showManual = false
    @State private var manualCode = ""

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button {
                    model.signOut()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Theme.surface, in: .circle)
                }
                .foregroundStyle(Theme.text)
                .accessibilityLabel("Volver")
                Spacer()
                if model.isDemo { DemoBadge() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Vincula tu batería").font(Theme.display(30))
                Text("Apunta la cámara al código QR que está en la batería FireFly.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textSecondary)
            }

            viewfinder
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            if paired, let id = model.deviceId {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batería vinculada").font(.system(size: 16, weight: .bold))
                        Text("FireFly \(id) · conectada a tu Wi‑Fi")
                            .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x3A4A1F)))

                Button("Ir al panel") { model.finishPairing() }
                    .buttonStyle(.primary)
            } else {
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.textSecondary)
                    Text("El código está en la etiqueta de la batería, junto a la entrada del panel solar.")
                        .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: .rect(cornerRadius: 16))

                Button {
                    if scannerAvailable { scanning = true } else { showManual = true }
                } label: {
                    if model.isBusy { ProgressView().tint(Theme.onAccent) } else { Text("Escanear código") }
                }
                .buttonStyle(.primary)
                .disabled(model.isBusy)

                Button("Escribir el código a mano") { showManual = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .alert("Código de la batería", isPresented: $showManual) {
            TextField("FF-0231 CLAVE", text: $manualCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Vincular") { Task { await submit(manualCode) } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Escribe el código que aparece debajo del QR (por ejemplo, FF-0231 y la clave).")
        }
    }

    @ViewBuilder private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(Theme.surface)
            if scanning {
                QRScannerView { text in
                    scanning = false
                    Task { await submit(text) }
                }
                .clipShape(.rect(cornerRadius: 28))
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 120, weight: .regular))
                    .foregroundStyle(Theme.text)
            }
            ViewfinderCorners().stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .padding(28)
        }
        .frame(width: 290, height: 290)
    }

    private func submit(_ text: String) async {
        if await model.pair(with: text) {
            paired = true
        }
    }
}

/// Las cuatro esquinas amarillas del visor.
struct ViewfinderCorners: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let len: CGFloat = 48, rad: CGFloat = 16
        // arriba izquierda
        p.move(to: CGPoint(x: r.minX, y: r.minY + len))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + len, y: r.minY))
        // arriba derecha
        p.move(to: CGPoint(x: r.maxX - len, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + rad), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + len))
        // abajo derecha
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - len))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - len, y: r.maxY))
        // abajo izquierda
        p.move(to: CGPoint(x: r.minX + len, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - rad), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - len))
        return p
    }
}

/// Cámara con lector de QR (VisionKit).
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        // Se arranca cuando la vista ya está en pantalla.
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}
