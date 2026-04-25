// Views/HelixContentView.swift
// Root view. Driven entirely by HelixAppState — no optional-index pattern.
// Depth navigation: Index → Pillars → Signals (tap to go deeper, back button to return).

import SwiftUI
import SwiftData

enum HelixDepth: Int { case index = 1, pillars = 2, signals = 3 }

struct HelixContentView: View {

    @StateObject private var viewModel    = HelixViewModel()
    @State private var currentDepth: HelixDepth = .index
    @State private var selectedStrand: HelixStrand? = nil
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            HelixTheme.backgroundPrimary.ignoresSafeArea()

            switch viewModel.appState {

            case .idle, .requestingPermissions, .fetchingData:
                loadingView

            case .learningBaseline(let daysRemaining):
                statusView(
                    message: "Helix is learning your baseline.\n\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") until your first full score.",
                    icon: "clock"
                )

            case .developingBaseline(_, let index):
                indexNavigator(index: index)

            case .fullScore(let index):
                indexNavigator(index: index)

            case .partialScore(let index, _):
                indexNavigator(index: index)

            case .suppressedScore(let reason):
                statusView(
                    message: AppStatePresentation(state: viewModel.appState).statusMessage,
                    icon: suppressedIcon(reason)
                )

            case .healthKitUnavailable:
                statusView(message: "Apple Health is not available on this device.", icon: "heart.slash")

            case .permissionsDenied:
                statusView(message: "Enable Health access in Settings → Privacy → Health.", icon: "lock.shield")

            case .error(let msg):
                statusView(message: msg, icon: "exclamationmark.triangle")
            }
        }
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadToday()
        }
    }

    // MARK: — Index navigator (shared by fullScore, partialScore, developingBaseline)

    @ViewBuilder
    private func indexNavigator(index: HelixIndex) -> some View {
        VStack(spacing: 0) {
            depthIndicator
                .padding(.top, 20)

            switch currentDepth {
            case .index:
                DepthOneView(index: index) {
                    withAnimation(.easeInOut(duration: 0.3)) { currentDepth = .pillars }
                }
            case .pillars:
                DepthTwoView(index: index) { strand in
                    selectedStrand = strand
                    withAnimation(.easeInOut(duration: 0.3)) { currentDepth = .signals }
                }
            case .signals:
                DepthThreeView(index: index, selectedStrand: selectedStrand)
            }

            if currentDepth != .index {
                Button("← Back") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentDepth = HelixDepth(rawValue: currentDepth.rawValue - 1) ?? .index
                    }
                }
                .foregroundColor(HelixTheme.pursueColor)
                .padding(.bottom, 30)
            }

            // Partial score notice
            if case .partialScore(_, let missing) = viewModel.appState, !missing.isEmpty {
                partialScoreNotice(missingCount: missing.count)
            }
        }
    }

    // MARK: — Loading view

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("Reading your data…")
                .foregroundColor(HelixTheme.textSecondary)
                .font(.caption)
        }
    }

    // MARK: — Status / suppressed view

    private func statusView(message: String, icon: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(HelixTheme.textSecondary)
            Text(message)
                .foregroundColor(HelixTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .font(.body)
        }
    }

    // MARK: — Partial score notice

    private func partialScoreNotice(missingCount: Int) -> some View {
        Text("\(missingCount) signal\(missingCount == 1 ? "" : "s") unavailable — score is estimated")
            .font(.caption2)
            .foregroundColor(HelixTheme.confidenceMedium)
            .padding(.bottom, 12)
    }

    // MARK: — Depth indicator dots

    private var depthIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { depth in
                Circle()
                    .fill(currentDepth.rawValue >= depth
                          ? HelixTheme.pursueColor
                          : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.bottom, 16)
    }

    private func suppressedIcon(_ reason: ScoreSuppressedReason) -> String {
        switch reason {
        case .watchOfflineTooLong:    return "applewatch.slash"
        case .insufficientSignals:    return "waveform.path.ecg"
        case .baselineNotYetActivated: return "clock.badge.questionmark"
        }
    }
}
