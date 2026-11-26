import SwiftUI
import UIKit

// MARK: - Controlador

/// Tutorial guiado por la luciérnaga: el punto de estado del panel «despega», oscurece la pantalla
/// y va iluminando cada parte de la app. Se muestra al llegar al panel por primera vez y otra vez
/// después de cada nuevo inicio de sesión o vinculación. También se puede repetir desde Ajustes.
@MainActor
@Observable
final class TutorialController {
    enum Target: Hashable {
        case statusDot, statusChip, hero, energyCards, gridToggle, tabBar, historyFilters, historyChart
    }

    struct Step {
        let targets: [Target]
        let title: String
        let body: String
        /// Pestaña que debe estar visible en este paso.
        let tab: AppTab
    }

    static let steps: [Step] = [
        Step(targets: [.statusChip], title: "Estado de la luz",
             body: "¡Hola! Soy FireFly, bienvenido. Demos un vistazo rápido por la app. Aquí ves si hay luz en casa. Si se va, me pongo naranja, tu router sigue con internet y te aviso.",
             tab: .home),
        Step(targets: [.hero], title: "Tu tiempo de internet",
             body: "Con luz te digo en cuánto se llena la batería. Durante un corte, cuánto internet te queda. El anillo muestra el porcentaje de carga.",
             tab: .home),
        Step(targets: [.energyCards], title: "Panel solar y router",
             body: "Cuántos vatios entrega ahora el panel solar y cuánto consume tu router.",
             tab: .home),
        Step(targets: [.gridToggle], title: "Cargar con la corriente",
             body: "Si lo activas, la batería también se carga con la luz de la casa, por si el sol no alcanza antes del próximo corte. Cuando se va la luz, el cambio a batería es siempre automático.",
             tab: .home),
        Step(targets: [.tabBar], title: "Muévete por la app",
             body: "Inicio es esta pantalla. En Estadísticas ves tus cortes y en Ajustes eliges qué avisos recibir. Vamos a Estadísticas.",
             tab: .home),
        Step(targets: [.historyFilters, .historyChart], title: "Tus cortes de luz",
             body: "Filtra por día, semana, mes o año para ver cuántos cortes hubo, cuánto duraron y cuánta energía usó el router.",
             tab: .stats),
    ]

    private static let doneKey = "tutorial.done"

    /// Marcos (en coordenadas de la ventana) de cada zona que explica el tutorial.
    var frames: [Target: CGRect] = [:]
    /// Lo asigna `AppModel` para poder cambiar de pestaña.
    var selectTab: ((AppTab) -> Void)?

    private(set) var isActive = false
    private(set) var index = 0
    /// La luciérnaga está posada en el punto de estado (al empezar y al terminar).
    private(set) var perched = true
    private(set) var dimVisible = false
    private(set) var cardVisible = false
    private var busy = false

    var done: Bool { UserDefaults.standard.bool(forKey: Self.doneKey) }

    /// Hace que el tutorial vuelva a mostrarse la próxima vez que se llegue al panel
    /// (después de cerrar sesión o de desvincular la batería).
    func reset() {
        UserDefaults.standard.set(false, forKey: Self.doneKey)
    }
    var step: Step { Self.steps[index] }
    var isLastStep: Bool { index == Self.steps.count - 1 }

    func start(after delay: Double = 0) {
        guard !isActive else { return }
        selectTab?(.home)
        index = 0
        perched = true
        dimVisible = false
        cardVisible = false
        isActive = true
        busy = true
        Task {
            try? await Task.sleep(for: .seconds(delay + 0.3))
            withAnimation(.easeOut(duration: 0.35)) { dimVisible = true }
            withAnimation(.spring(duration: 0.9, bounce: 0.3)) { perched = false }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeOut(duration: 0.25)) { cardVisible = true }
            busy = false
        }
    }

    func next() {
        guard isActive, !busy else { return }
        if isLastStep { finish(); return }
        busy = true
        let nextIndex = index + 1
        Task {
            withAnimation(.easeOut(duration: 0.15)) { cardVisible = false }
            if Self.steps[nextIndex].tab != step.tab {
                selectTab?(Self.steps[nextIndex].tab)
                // Esperar a que la nueva pestaña se dibuje y mida sus zonas.
                try? await Task.sleep(for: .milliseconds(450))
            } else {
                try? await Task.sleep(for: .milliseconds(150))
            }
            withAnimation(.spring(duration: 0.6, bounce: 0.25)) { index = nextIndex }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.25)) { cardVisible = true }
            busy = false
        }
    }

    /// «Saltar» y «Terminar»: la luciérnaga vuelve a su lugar y la pantalla se aclara.
    func finish() {
        guard isActive else { return }
        busy = true
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        Task {
            withAnimation(.easeOut(duration: 0.15)) { cardVisible = false }
            selectTab?(.home)
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(duration: 0.8, bounce: 0.2)) { perched = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { dimVisible = false }
            try? await Task.sleep(for: .milliseconds(850))
            isActive = false
            busy = false
        }
    }
}

// MARK: - Marcar zonas

extension View {
    /// Registra la posición de esta vista para que el tutorial pueda iluminarla.
    func tutorialTarget(_ target: TutorialController.Target, _ tutorial: TutorialController) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            tutorial.frames[target] = frame
        }
    }
}

// MARK: - Capa del tutorial

struct TutorialOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tutorial = model.tutorial
        GeometryReader { proxy in
            if tutorial.isActive {
                let origin = proxy.frame(in: .global).origin
                let size = proxy.size
                let hole = targetRect(tutorial, size: size, origin: origin)
                ZStack(alignment: .topLeading) {
                    // Oscurece todo menos la zona que se explica.
                    SpotlightShape(hole: hole ?? .zero)
                        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                        .opacity(tutorial.dimVisible ? 1 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityHidden(true)

                    if tutorial.cardVisible, let hole {
                        TutorialCard(step: tutorial.step, index: tutorial.index,
                                     total: TutorialController.steps.count, isLast: tutorial.isLastStep,
                                     hole: hole, screen: size,
                                     onNext: { tutorial.next() }, onSkip: { tutorial.finish() })
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    FireflyView(reduceMotion: reduceMotion)
                        .position(fireflyPoint(tutorial, hole: hole, size: size, origin: origin))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Zona iluminada del paso actual, en coordenadas de esta capa.
    private func targetRect(_ t: TutorialController, size: CGSize, origin: CGPoint) -> CGRect? {
        var rects: [CGRect] = []
        for target in t.step.targets {
            if target == .tabBar {
                rects.append(tabBarRect(size: size))
            } else if let r = t.frames[target] {
                rects.append(r.offsetBy(dx: -origin.x, dy: -origin.y))
            }
        }
        guard var union = rects.first else { return nil }
        for r in rects.dropFirst() { union = union.union(r) }
        return union.insetBy(dx: -8, dy: -8)
    }

    /// La barra de pestañas es de UIKit, así que se calcula desde el borde inferior de la pantalla.
    private func tabBarRect(size: CGSize) -> CGRect {
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let bottom = window?.safeAreaInsets.bottom ?? 34
        let height: CGFloat = 70
        return CGRect(x: 16, y: size.height - bottom - height + 8, width: size.width - 32, height: height)
    }

    private func fireflyPoint(_ t: TutorialController, hole: CGRect?, size: CGSize, origin: CGPoint) -> CGPoint {
        if t.perched || hole == nil {
            if let dot = t.frames[.statusDot] {
                return CGPoint(x: dot.midX - origin.x, y: dot.midY - origin.y)
            }
            return CGPoint(x: size.width - 60, y: 80)
        }
        let h = hole!
        // Se posa en la esquina superior izquierda de la zona iluminada.
        return CGPoint(x: max(18, h.minX + 6), y: max(60, h.minY + 2))
    }
}

/// Rectángulo completo con un hueco redondeado; el hueco se anima entre pasos.
struct SpotlightShape: Shape {
    var hole: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.size.width, hole.size.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if hole.width > 0, hole.height > 0 {
            p.addRoundedRect(in: hole, cornerSize: CGSize(width: 22, height: 22), style: .continuous)
        }
        return p
    }
}

/// La luciérnaga: un punto que brilla, titila y revolotea suavemente.
struct FireflyView: View {
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wanderX = reduceMotion ? 0 : 7 * sin(t * 1.7) + 3 * sin(t * 4.1)
            let wanderY = reduceMotion ? 0 : 6 * sin(t * 2.3 + 1) + 2 * cos(t * 5.3)
            let glow = reduceMotion ? 1 : 0.75 + 0.25 * sin(t * 3.2)
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.28 * glow))
                    .frame(width: 44, height: 44)
                    .blur(radius: 10)
                Circle()
                    .fill(Theme.accent.opacity(0.5 * glow))
                    .frame(width: 20, height: 20)
                    .blur(radius: 4)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 9, height: 9)
                    .shadow(color: Theme.accent, radius: 6 * glow)
            }
            .offset(x: wanderX, y: wanderY)
        }
        .frame(width: 60, height: 60)
    }
}

/// Tarjeta con el texto del paso, una flecha hacia la zona y los botones.
struct TutorialCard: View {
    let step: TutorialController.Step
    let index: Int
    let total: Int
    let isLast: Bool
    let hole: CGRect
    let screen: CGSize
    let onNext: () -> Void
    let onSkip: () -> Void

    private let margin: CGFloat = 20
    private var below: Bool { hole.midY < screen.height * 0.55 }

    var body: some View {
        let arrowX = min(max(hole.midX, margin + 28), screen.width - margin - 28)
        VStack(spacing: 0) {
            if below {
                Color.clear.frame(height: hole.maxY + 6)
                arrow(pointingUp: true, x: arrowX)
                card
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                card
                arrow(pointingUp: false, x: arrowX)
                Color.clear.frame(height: max(0, screen.height - hole.minY + 6))
            }
        }
        .frame(width: screen.width, height: screen.height)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paso \(index + 1) de \(total)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(step.title)
                .font(Theme.display(20))
                .foregroundStyle(Theme.text)
            Text(step.body)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if !isLast {
                    Button("Saltar", action: onSkip)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                Spacer()
                Button(action: onNext) {
                    Text(isLast ? "Terminar" : "Continuar")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 44)
                        .background(Theme.accent, in: .capsule)
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(Theme.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.border))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .padding(.horizontal, margin)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func arrow(pointingUp: Bool, x: CGFloat) -> some View {
        Triangle(pointingUp: pointingUp)
            .fill(Theme.surface)
            .frame(width: 22, height: 11)
            .offset(y: pointingUp ? 1 : -1)
            .frame(width: screen.width, alignment: .leading)
            .offset(x: x - 11)
            .accessibilityHidden(true)
    }
}

struct Triangle: Shape {
    var pointingUp: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if pointingUp {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        return p
    }
}
