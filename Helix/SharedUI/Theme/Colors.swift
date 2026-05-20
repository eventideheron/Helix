// SharedUI/Theme/Colors.swift
// Single canonical source for all Helix UI palette tokens.
// Locked values per design handoff; no hardcoded domain colors elsewhere.
//
// HelixPresentation (posture, confidence, strand) references HelixTheme below.
// All views and widgets use this file only for background, surface, strand, posture, confidence.

import SwiftUI

// MARK: — Hex initializer

extension Color {
    /// Creates a Color from a hex string (e.g. "#0E1116" or "0E1116").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, int >> 24)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: — Locked palette (authoritative)

enum HelixColor {
    // ── Foundation (palette shifted one stop) ──────────────────────────────
    static let background        = Color(hex: "#161B22")  // was #0E1116
    static let surface           = Color(hex: "#1C2330")  // was #161B22
    static let surfaceSecondary  = Color(hex: "#222A38")  // was #1C2330, now slightly lighter
    static let neutral           = Color(hex: "#8B949E")
    static let textPrimary       = Color(hex: "#E6EDF3")

    // ── Strand accents — visual elements only (dots, bars, radar, borders) ─
    static let sleep             = Color(hex: "#4A55A2")  // unchanged — accent use only
    static let load              = Color(hex: "#00E3FF")  // unchanged — all uses
    static let recovery          = Color(hex: "#2E8F6E")  // unchanged — accent use only

    // ── Strand text tokens — rendered text only ─────────────────────────────
    // Use these wherever a strand color appears as a label, score, or number.
    // Never use `sleep` or `recovery` directly for text rendering.
    static let sleepText         = Color(hex: "#8B96E8")  // 6.3:1 on new bg ✅
    static let loadText          = Color(hex: "#00E3FF")  // same as load — 11.1:1 ✅
    static let recoveryText      = Color(hex: "#3DB880")  // 6.9:1 on new bg ✅

    // ── Posture ─────────────────────────────────────────────────────────────
    static let pursue            = Color(hex: "#22C55E")
    static let moderate          = Color(hex: "#F59E0B")
    static let restore           = Color(hex: "#8B5CF6")

    // ── Confidence ──────────────────────────────────────────────────────────
    static let confidenceHigh    = Color(hex: "#2E8F6E")
    static let confidenceMedium  = Color(hex: "#F59E0B")
    static let confidenceLow     = Color(hex: "#F43F5E")

    // ── Borders ─────────────────────────────────────────────────────────────
    static let borderSubtle      = Color(hex: "#8B949E").opacity(0.10)
    static let borderStronger    = Color(hex: "#8B949E").opacity(0.18)
}

// MARK: — Semantic API (views use this; delegates to HelixColor)

enum HelixTheme {
    // Strands — accent (visual elements)
    static let sleepColor:        Color = HelixColor.sleep
    static let loadColor:         Color = HelixColor.load
    static let recoveryColor:     Color = HelixColor.recovery

    // Strands — text rendering
    static let sleepTextColor:    Color = HelixColor.sleepText
    static let loadTextColor:     Color = HelixColor.loadText
    static let recoveryTextColor: Color = HelixColor.recoveryText

    // Structural
    static let backgroundPrimary:   Color = HelixColor.background
    static let backgroundSecondary: Color = HelixColor.surface
    static let surfaceSecondary:    Color = HelixColor.surfaceSecondary
    static let textPrimary:         Color = HelixColor.textPrimary
    static let textSecondary:       Color = HelixColor.neutral
    static let borderSubtle:        Color = HelixColor.borderSubtle
    static let borderStronger:      Color = HelixColor.borderStronger

    // Posture
    static let pursueColor:    Color = HelixColor.pursue
    static let moderateColor:  Color = HelixColor.moderate
    static let restoreColor:   Color = HelixColor.restore

    // Confidence — own color scheme, independent of strand
    static let confidenceHigh:   Color = HelixColor.confidenceHigh
    static let confidenceMedium: Color = HelixColor.confidenceMedium
    static let confidenceLow:    Color = HelixColor.confidenceLow

    // Posture color lookup
    static func color(for posture: HelixPosture) -> Color {
        switch posture {
        case .pursue: return pursueColor
        case .moderate: return moderateColor
        case .restore: return restoreColor
        }
    }

    // Strand color lookup — returns ACCENT color (visual use)
    static func color(for strand: HelixStrand) -> Color {
        switch strand {
        case .sleep:    return sleepColor
        case .load:     return loadColor
        case .recovery: return recoveryColor
        }
    }

    // Strand text color lookup — returns TEXT token (label/score use)
    static func textColor(for strand: HelixStrand) -> Color {
        switch strand {
        case .sleep:    return sleepTextColor
        case .load:     return loadTextColor
        case .recovery: return recoveryTextColor
        }
    }

    // Confidence color lookup
    static func color(for confidence: ConfidenceLevel) -> Color {
        switch confidence {
        case .high: return confidenceHigh
        case .medium: return confidenceMedium
        case .low: return confidenceLow
        }
    }
}
