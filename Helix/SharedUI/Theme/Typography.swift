// SharedUI/Theme/Typography.swift
// Semantic font definitions. Named by role, not by size, so usage stays consistent
// as the design system evolves.

import SwiftUI

enum HelixTypography {

    // MARK: — Score display
    static let scoreHero:   Font = .system(size: 96, weight: .thin,   design: .rounded)
    static let scoreLarge:  Font = .system(size: 56, weight: .thin,   design: .rounded)
    static let scoreMedium: Font = .system(size: 40, weight: .thin,   design: .rounded)
    static let scoreSmall:  Font = .system(size: 24, weight: .light,  design: .rounded)

    // MARK: — Labels
    static let postureLabel:    Font = .system(.caption, design: .default).weight(.semibold)
    static let strandLabel:     Font = .caption
    static let confidenceLabel: Font = .system(size: 9)
    static let signalLabel:     Font = .subheadline

    // MARK: — Body
    static let explanationBody: Font = .subheadline
    static let captionBody:     Font = .caption
    static let microLabel:      Font = .system(size: 10)

    // MARK: — Navigation
    static let backButton:  Font = .body
    static let sectionHeader: Font = .system(size: 10).weight(.semibold)
}

// MARK: — Letter spacing constants
enum HelixTracking {
    static let postureWord: CGFloat  = 3.0
    static let sectionHeader: CGFloat = 2.0
    static let strandName: CGFloat   = 1.0
}
