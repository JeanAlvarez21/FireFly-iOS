import SwiftUI

/// Colores y tipografía del Figma «FireFly – Prototipo app» (variables «FireFly · Colores»).
enum Theme {
    static let background = Color(hex: 0x0E1621)
    static let surface = Color(hex: 0x172231)
    static let border = Color(hex: 0x2A3A50)
    static let divider = Color(hex: 0x22324A)
    static let text = Color(hex: 0xF3F5F7)
    static let textSecondary = Color(hex: 0xA9B4C2)
    static let accent = Color(hex: 0xE8F86B)
    static let warning = Color(hex: 0xFFB454)
    static let onAccent = Color(hex: 0x0E1621)
    static let danger = Color(hex: 0xFF9B8A)

    /// Títulos: Space Grotesk si está incluida en la app; si no, la tipografía del sistema redondeada.
    static func display(_ size: CGFloat) -> Font {
        if UIFont(name: "SpaceGrotesk-Bold", size: size) != nil {
            return .custom("SpaceGrotesk-Bold", size: size, relativeTo: .title)
        }
        return .system(size: size, weight: .bold, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Tarjeta con el fondo «superficie».
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: radius))
    }
}

/// Botón principal amarillo del Figma.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 16))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Pantalla con el fondo oscuro de la app.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.text)
            .background(Theme.background.ignoresSafeArea())
    }
}

extension View {
    func fireflyScreen() -> some View { modifier(ScreenBackground()) }
}

/// Aviso de que la app está mostrando datos simulados.
struct DemoBadge: View {
    var body: some View {
        Label("Modo demo · datos simulados", systemImage: "testtube.2")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.warning, in: .capsule)
    }
}
