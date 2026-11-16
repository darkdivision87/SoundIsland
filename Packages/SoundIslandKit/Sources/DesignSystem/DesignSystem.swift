// DesignSystem: "toy-box tactile" tokens and components from spec section 6
// and the hi-fi canvas (design/screens/DesignSystem.dc.html).

import SwiftUI
import MusicTheory

// MARK: - Color tokens

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

public enum SI {
    public enum Palette {
        public static let sky = Color(hex: 0xFFF6E9)
        public static let card = Color.white
        public static let ink900 = Color(hex: 0x2A2550)
        public static let ink500 = Color(hex: 0x6E6A93)
        public static let bop = Color(hex: 0x7B5CFF)
        public static let bopDeep = Color(hex: 0x5A3FD9)
        public static let bopTint = Color(hex: 0xEDE7FF)
        public static let success = Color(hex: 0x2ECC8F)
        public static let successDeep = Color(hex: 0x1E9A6A)
        public static let tryAgain = Color(hex: 0xFFB23F)
        public static let star = Color(hex: 0xFFD447)
        public static let ocean = Color(hex: 0x8EDBE8)
        public static let sand = Color(hex: 0xF4D7A1)
        public static let locked = Color(hex: 0xC7CFDD)
        public static let cheek = Color(hex: 0xFF8FB1)
    }

    public enum Metrics {
        public static let grid: CGFloat = 8
        public static let margin: CGFloat = 32
        public static let outline: CGFloat = 4
        public static let lip: CGFloat = 6
        public static let bigButtonHeight: CGFloat = 88
        public static let iconButton: CGFloat = 76
        public static let stepCell: CGFloat = 52          // Makers 16-step grid; Explorers use 64 pt tall 8-step cells
    }

    /// SF Pro Rounded at the spec's sizes. Nothing below 16 pt.
    public enum Font {
        public static let display = SwiftUI.Font.system(size: 48, weight: .heavy, design: .rounded)
        public static let title = SwiftUI.Font.system(size: 34, weight: .bold, design: .rounded)
        public static let headline = SwiftUI.Font.system(size: 26, weight: .bold, design: .rounded)
        public static let body = SwiftUI.Font.system(size: 22, weight: .semibold, design: .rounded)
        public static let label = SwiftUI.Font.system(size: 18, weight: .bold, design: .rounded)
        public static let caption = SwiftUI.Font.system(size: 16, weight: .semibold, design: .rounded)
    }

    /// Spring used everywhere (spec: response 0.35, damping 0.6).
    public static let spring = Animation.spring(response: 0.35, dampingFraction: 0.6)
}

// MARK: - Note color + shape (fixed app-wide)

public enum NoteGlyph: String, CaseIterable, Sendable {
    case circle, triangle, square, diamond, hexagon, star, heart
}

public struct NoteStyle: Sendable {
    public let color: Color
    public let lip: Color
    public let glyph: NoteGlyph
    public let colorName: String
    /// Sharps and flats get diagonal stripes over the lower natural's color.
    public let striped: Bool

    public static func of(_ pc: PitchClass) -> NoteStyle {
        let base = pc.colorParent
        let s: (UInt32, UInt32, NoteGlyph, String) = {
            switch base {
            case .c: return (0xFF5A5F, 0xC9363B, .circle, "Red")
            case .d: return (0xFF9A3C, 0xD06F17, .triangle, "Orange")
            case .e: return (0xFFD23F, 0xD2A515, .square, "Yellow")
            case .f: return (0x3DD68C, 0x21A867, .diamond, "Green")
            case .g: return (0x22C3C9, 0x13979C, .hexagon, "Teal")
            case .a: return (0x4D8DFF, 0x2F68D1, .star, "Blue")
            default: return (0xA66BFF, 0x7E45D6, .heart, "Purple")
            }
        }()
        return NoteStyle(color: Color(hex: s.0), lip: Color(hex: s.1), glyph: s.2, colorName: s.3, striped: !pc.isNatural)
    }
}

/// The seven note glyphs, drawn in a unit square (matches the SVG paths on the canvas).
public struct NoteShape: Shape {
    public let glyph: NoteGlyph
    public init(_ glyph: NoteGlyph) { self.glyph = glyph }

    public func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x / 40 * r.width, y: r.minY + y / 40 * r.height) }
        var path = Path()
        switch glyph {
        case .circle:
            path.addEllipse(in: CGRect(origin: p(6, 6), size: CGSize(width: r.width * 28 / 40, height: r.height * 28 / 40)))
        case .triangle:
            path.addLines([p(20, 5), p(35, 32), p(5, 32)]); path.closeSubpath()
        case .square:
            path.addRoundedRect(in: CGRect(origin: p(7, 7), size: CGSize(width: r.width * 26 / 40, height: r.height * 26 / 40)), cornerSize: CGSize(width: 3, height: 3))
        case .diamond:
            path.addLines([p(20, 3), p(37, 20), p(20, 37), p(3, 20)]); path.closeSubpath()
        case .hexagon:
            path.addLines([p(20, 3), p(35, 11.5), p(35, 28.5), p(20, 37), p(5, 28.5), p(5, 11.5)]); path.closeSubpath()
        case .star:
            path.addLines([p(20, 3), p(25, 14), p(37, 15.5), p(28, 23.5), p(30.5, 35.5), p(20, 29.5), p(9.5, 35.5), p(12, 23.5), p(3, 15.5), p(15, 14)])
            path.closeSubpath()
        case .heart:
            path.move(to: p(20, 35))
            path.addCurve(to: p(3, 13.5), control1: p(8, 27), control2: p(3, 20))
            path.addCurve(to: p(11.5, 5), control1: p(3, 8.5), control2: p(7, 5))
            path.addCurve(to: p(20, 10), control1: p(15, 5), control2: p(18, 7))
            path.addCurve(to: p(28.5, 5), control1: p(22, 7), control2: p(25, 5))
            path.addCurve(to: p(37, 13.5), control1: p(33, 5), control2: p(37, 8.5))
            path.addCurve(to: p(20, 35), control1: p(37, 20), control2: p(32, 27))
        }
        return path
    }
}

// MARK: - Components

/// Chunky pressable button with a colored lip. Press = lip compresses, 0.94 scale.
public struct BigButtonStyle: ButtonStyle, Sendable {
    public var fill: Color
    public var lip: Color
    public var foreground: Color
    public var height: CGFloat
    public var cornerRadius: CGFloat
    public var horizontalPadding: CGFloat

    public init(fill: Color = SI.Palette.bop, lip: Color = SI.Palette.bopDeep, foreground: Color = .white,
                height: CGFloat = SI.Metrics.bigButtonHeight, cornerRadius: CGFloat = 32, horizontalPadding: CGFloat = 28) {
        self.horizontalPadding = horizontalPadding
        self.fill = fill
        self.lip = lip
        self.foreground = foreground
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public static let primary = BigButtonStyle()
    public static let secondary = BigButtonStyle(fill: .white, lip: SI.Palette.ink900, foreground: SI.Palette.ink900)
    public static let go = BigButtonStyle(fill: SI.Palette.success, lip: SI.Palette.successDeep, foreground: SI.Palette.ink900)

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(SI.Font.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(SI.Palette.ink900, lineWidth: SI.Metrics.outline))
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(lip)
                    .offset(y: pressed ? 1 : SI.Metrics.lip)
            )
            .offset(y: pressed ? SI.Metrics.lip - 1 : 0)
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(SI.spring, value: pressed)
            .contentShape(Rectangle())
    }
}

/// Round 76 pt icon button (Back, Pause, Hear it again).
public struct RoundIconButton: View {
    let systemName: String
    let label: String
    let fill: Color
    let tint: Color
    let action: () -> Void

    public init(systemName: String, label: String, fill: Color = .white, tint: Color = SI.Palette.ink900, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.fill = fill
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: SI.Metrics.iconButton, height: SI.Metrics.iconButton)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(SI.Palette.ink900, lineWidth: SI.Metrics.outline))
                .background(Circle().fill(SI.Palette.ink900).offset(y: SI.Metrics.lip))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Note pad: rounded square in the note's color with its shape glyph and (optionally) its letter.
public struct NotePad: View {
    let pitchClass: PitchClass
    let showName: Bool
    let size: CGFloat
    let highlighted: Bool

    public init(_ pitchClass: PitchClass, showName: Bool = true, size: CGFloat = 120, highlighted: Bool = false) {
        self.pitchClass = pitchClass
        self.showName = showName
        self.size = size
        self.highlighted = highlighted
    }

    public var body: some View {
        let style = NoteStyle.of(pitchClass)
        VStack(spacing: 6) {
            NoteShape(style.glyph)
                .fill(.white)
                .overlay(NoteShape(style.glyph).stroke(SI.Palette.ink900, lineWidth: 2.5))
                .frame(width: size * 0.46, height: size * 0.46)
            if showName {
                Text(pitchClass.name)
                    .font(.system(size: size * 0.22, weight: .heavy, design: .rounded))
                    .foregroundStyle(SI.Palette.ink900)
            }
        }
        .frame(width: size, height: size * 1.1)
        .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(style.color))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(SI.Palette.ink900, lineWidth: SI.Metrics.outline))
        .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(style.lip).offset(y: 7))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.25 + 10, style: .continuous)
                .strokeBorder(SI.Palette.star, lineWidth: highlighted ? 6 : 0)
                .padding(-12)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note \(pitchClass.name), \(style.colorName) \(style.glyph.rawValue)")
    }
}

public struct StarRow: View {
    let earned: Int
    let size: CGFloat
    public init(earned: Int, size: CGFloat = 28) { self.earned = earned; self.size = size }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                NoteShape(.star)
                    .fill(i < earned ? SI.Palette.star : .white)
                    .overlay(NoteShape(.star).stroke(SI.Palette.ink900, lineWidth: 2.5))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned) of 3 stars")
    }
}

/// White speech bubble with a lip, used for Bop's lines.
public struct SpeechBubble: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(SI.Font.body)
            .foregroundStyle(SI.Palette.ink900)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(SI.Palette.ink900, lineWidth: 3))
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SI.Palette.ink900).offset(y: 5))
    }
}

/// Feedback chip: "Great!" (success) or "Try again!" (gentle orange, never red).
public struct FeedbackChip: View {
    let correct: Bool
    public init(correct: Bool) { self.correct = correct }
    public var body: some View {
        Text(correct ? "Great!" : "Try again!")
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(SI.Palette.ink900)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(Capsule().fill(correct ? SI.Palette.success : SI.Palette.tryAgain))
            .overlay(Capsule().strokeBorder(SI.Palette.ink900, lineWidth: SI.Metrics.outline))
            .background(Capsule().fill(SI.Palette.ink900).offset(y: 5))
            .rotationEffect(.degrees(-6))
    }
}

// MARK: - Bop

public enum BopMood: Sendable { case idle, listen, sing, cheer, wobble, sleep }

/// Placeholder vector Bop matching the canvas. Replace with the Rive state machine (spec section 6).
public struct BopView: View {
    let mood: BopMood
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    public init(mood: BopMood = .idle, size: CGFloat = 120) {
        self.mood = mood
        self.size = size
    }

    public var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 120
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }
            let ink = SI.Palette.ink900
            // antenna
            var antenna = Path(); antenna.move(to: CGPoint(x: 60 * s, y: 22 * s)); antenna.addLine(to: CGPoint(x: 60 * s, y: 8 * s))
            ctx.stroke(antenna, with: .color(ink), style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
            ctx.fill(Path(ellipseIn: rect(54, 1, 12, 12)), with: .color(SI.Palette.star))
            ctx.stroke(Path(ellipseIn: rect(54, 1, 12, 12)), with: .color(ink), lineWidth: 3 * s)
            // body + lip
            let lip = Path(roundedRect: rect(12, 24, 96, 86), cornerRadius: 40 * s)
            ctx.fill(lip, with: .color(SI.Palette.bopDeep)); ctx.stroke(lip, with: .color(ink), lineWidth: 4 * s)
            let body = Path(roundedRect: rect(12, 18, 96, 84), cornerRadius: 40 * s)
            ctx.fill(body, with: .color(mood == .cheer ? Color(hex: 0x9D85FF) : SI.Palette.bop)); ctx.stroke(body, with: .color(ink), lineWidth: 4 * s)
            // eyes
            if mood == .cheer || mood == .sleep {
                for x in [32.0, 68.0] {
                    var arc = Path(); arc.move(to: CGPoint(x: x * s, y: 50 * s))
                    arc.addQuadCurve(to: CGPoint(x: (x + 20) * s, y: 50 * s), control: CGPoint(x: (x + 10) * s, y: (mood == .sleep ? 58 : 38) * s))
                    ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 4.5 * s, lineCap: .round))
                }
            } else {
                for x in [32.0, 68.0] {
                    ctx.fill(Path(ellipseIn: rect(x, 38, 20, 20)), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: rect(x, 38, 20, 20)), with: .color(ink), lineWidth: 3 * s)
                    ctx.fill(Path(ellipseIn: rect(x + 7.5, 45.5, 9, 9)), with: .color(ink))
                }
            }
            // cheeks
            ctx.fill(Path(ellipseIn: rect(21, 60, 12, 12)), with: .color(SI.Palette.cheek.opacity(0.85)))
            ctx.fill(Path(ellipseIn: rect(87, 60, 12, 12)), with: .color(SI.Palette.cheek.opacity(0.85)))
            // woofer mouth
            let r: CGFloat = mood == .sing ? 19 : 16
            ctx.fill(Path(ellipseIn: rect(60 - r, 78 - r, r * 2, r * 2)), with: .color(ink))
            ctx.fill(Path(ellipseIn: rect(50, 68, 20, 20)), with: .color(Color(hex: 0x4B3FA0)))
            ctx.fill(Path(ellipseIn: rect(56, 74, 8, 8)), with: .color(Color(hex: 0xA99BFF)))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(mood == .wobble && bounce && !reduceMotion ? 8 : 0))
        .scaleEffect(y: mood == .cheer && bounce && !reduceMotion ? 1.06 : 1, anchor: .bottom)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) { bounce = true }
        }
        .accessibilityLabel("Bop the speaker buddy")
    }
}
