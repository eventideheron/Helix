import WidgetKit
import SwiftUI

// MARK: — Hex color (canonical palette values; see SharedUI/Theme/Colors.swift)
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

let helixAppGroupID = "group.com.joshlang.helix"

@main
struct HelixWidgetBundle: WidgetBundle {
    var body: some Widget {
        HelixWidget()
    }
}

struct HelixWidget: Widget {
    let kind = "HelixWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HelixWidgetProvider()) { entry in
            HelixWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Helix")
        .description("Your daily Helix Index.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

// Posture colors match canonical palette (HelixColor in SharedUI/Theme/Colors.swift).
// This target may not include Theme; use same hex so widget matches app.
struct PosturePresentation {
    let posture: HelixPosture
    var color: Color {
        switch posture {
        case .pursue:   return Color(hex: "#22C55E")
        case .moderate: return Color(hex: "#F59E0B")
        case .restore:  return Color(hex: "#8B5CF6")
        }
    }
}
