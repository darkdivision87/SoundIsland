#if canImport(AppKit)
import XCTest
import SwiftUI
import AppKit
import MusicTheory
@testable import DesignSystem

/// Snapshot tests for DesignSystem components, with no third-party library: SwiftUI's ImageRenderer draws
/// each component, and the pixels are compared with a reference PNG in __Snapshots__.
/// Record new references with: RECORD_SNAPSHOTS=1 swift test --filter DesignSystemSnapshotTests
@MainActor
final class DesignSystemSnapshotTests: XCTestCase {
    private static let snapshotsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
    private var recording: Bool { ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" }

    private func assertSnapshot<V: View>(_ view: V, named name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "could not render \(name)", file: file, line: line)
        let png = try XCTUnwrap(Self.pngData(image), file: file, line: line)
        let url = Self.snapshotsDir.appendingPathComponent("\(name).png")
        if recording || !FileManager.default.fileExists(atPath: url.path) {
            try png.write(to: url)
            if !recording { XCTFail("Recorded missing reference \(name).png; run again to compare.", file: file, line: line) }
            return
        }
        let reference = try XCTUnwrap(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil), file: file, line: line)
        let diff = Self.difference(image, reference)
        XCTAssertLessThan(diff, 0.01, "\(name) differs from its snapshot in \(Int(diff * 100))% of pixels", file: file, line: line)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Share of pixels whose RGBA differs by more than a small tolerance (font antialiasing varies a little).
    private static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        func rgba(_ img: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: img.width * img.height * 4)
            let ctx = CGContext(data: &data, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            return data
        }
        let pa = rgba(a), pb = rgba(b)
        var differing = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let d = (0..<4).map { abs(Int(pa[i + $0]) - Int(pb[i + $0])) }.max()!
            if d > 24 { differing += 1 }
        }
        return Double(differing) / Double(pa.count / 4)
    }

    func testNotePadsKeepColorShapeAndSharpStripes() throws {
        let row = HStack(spacing: 10) {
            ForEach(PitchClass.allCases, id: \.self) { NotePad($0, size: 80) }
        }
        .padding(20).background(Color.white)
        try assertSnapshot(row, named: "NotePad-all")
    }

    func testNoteBadges() throws {
        let row = HStack(spacing: 8) {
            ForEach(PitchClass.allCases, id: \.self) { NoteBadge($0, size: 36) }
        }
        .padding(12).background(Color.white)
        try assertSnapshot(row, named: "NoteBadge-all")
    }

    func testButtonsBubbleChipsAndStars() throws {
        let view = VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Button("Play") {}.buttonStyle(BigButtonStyle.primary)
                Button("Back") {}.buttonStyle(BigButtonStyle.secondary)
                Button("Go") {}.buttonStyle(BigButtonStyle.go)
            }
            SpeechBubble("Tap on every beat!")
            HStack(spacing: 16) { FeedbackChip(correct: true); FeedbackChip(correct: false) }
            HStack(spacing: 16) { StarRow(earned: 0); StarRow(earned: 2); StarRow(earned: 3) }
        }
        .padding(24).background(SI.Palette.sky)
        try assertSnapshot(view, named: "Components")
    }

    func testBopMoods() throws {
        let view = HStack(spacing: 16) {
            ForEach([BopMood.idle, .listen, .sing, .cheer, .wobble, .sleep], id: \.self) { BopView(mood: $0, size: 90) }
        }
        .padding(16).background(SI.Palette.sky)
        try assertSnapshot(view, named: "Bop-moods")
    }
}

/// Spec rule: text contrast >= 4.5:1 (white on brand purple only at 22 pt+ bold, i.e. >= 3:1).
final class DesignSystemContrastTests: XCTestCase {
    private func luminance(_ color: Color) -> Double {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        func lin(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    private func ratio(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testBodyTextPairs() {
        let backgrounds: [(String, Color)] = [("white", .white), ("sky", SI.Palette.sky), ("sand", SI.Palette.sand),
                                              ("ocean", SI.Palette.ocean), ("star", SI.Palette.star), ("tryAgain", SI.Palette.tryAgain),
                                              ("success", SI.Palette.success), ("bopTint", SI.Palette.bopTint)]
        for (name, bg) in backgrounds {
            XCTAssertGreaterThanOrEqual(ratio(SI.Palette.ink900, bg), 4.5, "ink on \(name)")
        }
        XCTAssertGreaterThanOrEqual(ratio(SI.Palette.ink500, .white), 4.5, "secondary ink on white")
    }

    func testWhiteOnBrandIsLargeTextOnly() {
        XCTAssertGreaterThanOrEqual(ratio(.white, SI.Palette.bop), 3.0, "white on bop at 22 pt+ bold")
        XCTAssertGreaterThanOrEqual(ratio(.white, SI.Palette.ink900), 4.5)
    }

    func testNoteColorsCarryInkLabels() {
        // Ink on A (blue) and B (purple) is just under 4.5:1, so text drawn straight on a note color must be
        // large (19 pt+ heavy, 3:1 rule); smaller labels go on a NoteColorChip (ink on white).
        for pc in PitchClass.allCases where pc.isNatural {
            XCTAssertGreaterThanOrEqual(ratio(SI.Palette.ink900, NoteStyle.of(pc).color), 3.0, "large ink text on \(pc.name) color")
        }
        XCTAssertGreaterThanOrEqual(ratio(SI.Palette.ink900, Color.white.opacity(0.92)), 4.5, "chip text")
    }
}
#endif
