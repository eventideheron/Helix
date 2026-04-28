// Views/HelixContentView.swift
// Root view. Driven entirely by HelixAppState — no optional-index pattern.
// Depth navigation: Index → Pillars → Signals (tap to go deeper, back button to return).

import SwiftUI
import SwiftData

/// Canonical anchor chart frame — matches Depth 3 radar (`DepthThreeView`) per spec v3.
enum HelixDashboardAnchorMetrics {
    static let chartHeight: CGFloat = 300
    static let chartHorizontalPadding: CGFloat = 8

    /// Same geometric center as `DepthThreeRadar` canvas (`DepthThreeView` — `CGPoint(x: size.width/2, y: size.height/2)`).
    static func helixCenterPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Outer ring radius in chart coordinates — matches `DepthThreeRadar` / `DepthOneGhostRadarView` (`min * 0.34`).
    static func radarOuterRadius(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.34
    }
}

struct HelixContentView: View {

    @StateObject private var viewModel    = HelixViewModel()
    /// Depth 3 only: links polygon vertex taps and signal row expansion (`DepthThreeView.swift`).
    @State private var depthThreeExpansionCoordinator = DepthThreeExpansionCoordinator()
    @State private var currentDepth: HelixDepth = .index
    @State private var selectedStrand: HelixStrand? = nil
    @State private var showingHistory     = false
    @Namespace private var depthTransitionNamespace
    @Environment(\.modelContext) private var modelContext

    /// v1 onboarding: first launch shows linear flow; HealthKit is requested only from onboarding (or `loadToday` after completion).
    @AppStorage("helix.onboarding.v1.completed") private var onboardingCompleted = false

    var body: some View {
        NavigationStack {
            ZStack {
                HelixTheme.backgroundPrimary.ignoresSafeArea()

                if !onboardingCompleted {
                    HelixOnboardingFlowView(
                        viewModel: viewModel,
                        onboardingCompleted: $onboardingCompleted
                    )
                } else {

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
                }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if onboardingCompleted, viewModel.historyResult != nil {
                    Button("History") { showingHistory = true }
                        .font(.caption)
                        .foregroundColor(HelixTheme.textSecondary)
                }
            }
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Debug") {
                    HelixDebugView(viewModel: viewModel)
                }
            }
            #endif
        }
        .sheet(isPresented: $showingHistory) {
            if let hr = viewModel.historyResult {
                NavigationStack {
                    HistoryView(
                        historyResult: hr,
                        allRecords: viewModel.allDailyRecords,
                        trendArrow: hr.trendArrow ?? .flat
                    )
                    .navigationTitle("History")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingHistory = false }
                        }
                    }
                }
            }
        }
        }
        .task(id: onboardingCompleted) {
            viewModel.setModelContext(modelContext)
            if onboardingCompleted {
                await viewModel.loadToday(skipIfAlreadyLoaded: true)
            }
        }
    }

    // MARK: — Index navigator (shared by fullScore, partialScore, developingBaseline)

    @ViewBuilder
    private func indexNavigator(index: HelixIndex) -> some View {
        VStack(spacing: 0) {
            depthIndicator
                .padding(.top, 20)

            // RADAR + TOP CLUSTER — radar is always at the same vertical position; top cluster
            // is overlaid within the same ZStack so the radar frame never shifts between depths.
            ZStack(alignment: .topLeading) {
                SharedRadarView(
                    index: index,
                    currentDepth: currentDepth,
                    selectedStrand: selectedStrand,
                    depthThreeExpansion: currentDepth == .signals ? depthThreeExpansionCoordinator : nil,
                    namespace: depthTransitionNamespace
                )
                .animation(.easeInOut(duration: 0.25), value: currentDepth)

                // Depth-specific top-left (and top-right) overlay — depth 1 score lives inside
                // the radar itself via DepthOneRadarCenterOverlay, so no overlay needed there.
                Group {
                    switch currentDepth {
                    case .index:
                        EmptyView()
                    case .pillars:
                        DepthTwoTopContent(index: index, namespace: depthTransitionNamespace)
                    case .signals:
                        DepthThreeTopContent(
                            index: index,
                            selectedStrand: selectedStrand,
                            explanationEngine: viewModel.getExplanationEngine(),
                            namespace: depthTransitionNamespace
                        )
                    }
                }
                .padding(.top, 2)
                .padding(.horizontal, 24)
            }

            // BOTTOM ZONE — depth-specific content below the radar; animates on depth change
            Group {
                switch currentDepth {
                case .index:
                    DepthOneBottomContent(index: index) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                            currentDepth = .pillars
                        }
                    }
                    .transition(.opacity)

                case .pillars:
                    DepthTwoBottomContent(
                        index: index,
                        crossStrandInsight: viewModel.crossStrandInsight
                    ) { strand in
                        selectedStrand = strand
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                            currentDepth = .signals
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .signals:
                    DepthThreeBottomContent(
                        index: index,
                        selectedStrand: selectedStrand,
                        explanationEngine: viewModel.getExplanationEngine(),
                        expansion: depthThreeExpansionCoordinator
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.84), value: currentDepth)

            Spacer()

            if currentDepth != .index {
                Button("← Back") {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                        currentDepth = HelixDepth(rawValue: currentDepth.rawValue - 1) ?? .index
                    }
                }
                .foregroundColor(HelixTheme.pursueColor)
                .padding(.bottom, 30)
            }

            // Depth 1 / Depth 2 no longer show the bottom partial-score footer.
            // Confidence remains in the top chrome. Depth 3 keeps the detailed
            // missing-signal card inside DepthThreeBottomContent.
        }
        .onChange(of: currentDepth) { _, depth in
            if depth != .signals {
                depthThreeExpansionCoordinator.expandedSignal = nil
            }
        }
        .onChange(of: depthThreeExpansionCoordinator.strandChangeRequest) { _, newStrand in
            guard let strand = newStrand else { return }
            selectedStrand = strand
            depthThreeExpansionCoordinator.strandChangeRequest = nil
        }
    }

    // MARK: — Loading view

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(HelixTheme.textPrimary)
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

// MARK: — Shared radar — fixed spatial anchor across all depths

private struct SharedRadarView: View {
    let index: HelixIndex
    let currentDepth: HelixDepth
    let selectedStrand: HelixStrand?
    let depthThreeExpansion: DepthThreeExpansionCoordinator?
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            radarBranch
                .frame(maxWidth: .infinity)
                .frame(height: HelixDashboardAnchorMetrics.chartHeight)
                .padding(.horizontal, HelixDashboardAnchorMetrics.chartHorizontalPadding)
                .matchedGeometryEffect(id: "helixRadar", in: namespace)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var radarBranch: some View {
        switch currentDepth {
        case .index:
            ZStack {
                DepthOneGhostRadarView(
                    index: index,
                    tint: PosturePresentation(posture: index.posture).color
                )
                DepthOneRadarCenterOverlay(
                    index: index,
                    namespace: namespace,
                    style: .hero
                )
            }
        case .pillars:
            DepthTwoTriangleRadar(index: index)
        case .signals:
            DepthThreeRadar(
                index: index,
                selectedStrand: selectedStrand ?? .recovery,
                expansion: depthThreeExpansion
            )
        }
    }
}
