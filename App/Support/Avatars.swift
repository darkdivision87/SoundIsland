import SwiftUI
import DesignSystem

/// Placeholder avatars until illustrated ones land. Kids pick by picture, never by typing.
struct Avatar: Identifiable, Hashable {
    let id: String
    let symbol: String
    let color: Color
    let name: String

    static let all: [Avatar] = [
        Avatar(id: "fox", symbol: "pawprint.fill", color: Color(hex: 0xFF9A3C), name: "fox"),
        Avatar(id: "owl", symbol: "bird.fill", color: Color(hex: 0x7B5CFF), name: "owl"),
        Avatar(id: "turtle", symbol: "tortoise.fill", color: Color(hex: 0x3DD68C), name: "turtle"),
        Avatar(id: "fish", symbol: "fish.fill", color: Color(hex: 0x4D8DFF), name: "fish"),
        Avatar(id: "bunny", symbol: "hare.fill", color: Color(hex: 0xFF6FA8), name: "bunny"),
        Avatar(id: "bug", symbol: "ladybug.fill", color: Color(hex: 0xFFB000), name: "ladybug"),
    ]

    static func named(_ id: String) -> Avatar { all.first { $0.id == id } ?? all[0] }
}
