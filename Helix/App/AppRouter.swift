// App/AppRouter.swift
// Owns navigation state independently of data state.
// HelixViewModel owns HelixAppState (data/confidence state).
// AppRouter owns depth and selected strand (UI navigation state).
// Keeping these separate means the ViewModel never needs to know which depth the user is on.

import SwiftUI

enum HelixDepth: Int, Equatable {
    case index   = 1
    case pillars = 2
    case signals = 3
}

@MainActor
class AppRouter: ObservableObject {
    @Published var depth: HelixDepth        = .index
    @Published var selectedStrand: HelixStrand? = nil

    func navigateDeeper(to strand: HelixStrand? = nil) {
        if let strand { selectedStrand = strand }
        if let next = HelixDepth(rawValue: depth.rawValue + 1) {
            depth = next
        }
    }

    func navigateBack() {
        selectedStrand = nil
        if let prev = HelixDepth(rawValue: depth.rawValue - 1) {
            depth = prev
        }
    }

    func resetToIndex() {
        depth          = .index
        selectedStrand = nil
    }
}
