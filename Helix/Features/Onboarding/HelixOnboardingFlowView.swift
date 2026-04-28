// Features/Onboarding/HelixOnboardingFlowView.swift
// v1 onboarding: linear steps, HealthKit only on CTA, first score + explanation from live pipeline.

import SwiftUI
import UIKit

enum HelixOnboardingStep: Int, CaseIterable {
    case opening
    case problem
    case solution
    case model
    case baseline
    case privacy
    case permission
    case firstScore
    case firstExplanation
    case completion
}

struct HelixOnboardingFlowView: View {

    @ObservedObject var viewModel: HelixViewModel
    @Binding var onboardingCompleted: Bool

    @State private var step: HelixOnboardingStep = .opening

    var body: some View {
        ZStack {
            HelixTheme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        stepContent
                            .padding(.horizontal, 28)
                            .padding(.bottom, 28)
                    }
                }

                bottomBar
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
        }
        .onChange(of: viewModel.appState) { _, new in
            advanceFromPermissionStepWhenReady(new)
        }
    }

    // MARK: — Progress

    private var progressHeader: some View {
        HStack(spacing: 6) {
            ForEach(0..<HelixOnboardingStep.allCases.count, id: \.self) { i in
                Capsule()
                    .fill(i <= step.rawValue ? HelixTheme.pursueColor.opacity(0.85) : HelixTheme.borderSubtle)
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: — Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .opening:
            onboardingTextBlock(
                title: "Helix",
                body: "One answer to a simple question: What should you do today?"
            )
        case .problem:
            onboardingTextBlock(
                title: nil,
                body: "You already track your health. But your devices do not always agree."
            )
        case .solution:
            onboardingTextBlock(
                title: nil,
                body: "Helix combines everything into one system. One score. Three strands. Clear explanation."
            )
        case .model:
            modelScreen
        case .baseline:
            onboardingTextBlock(
                title: "Helix learns your physiology.",
                body: "First 14 days: Building your baseline. By 90 days: Highly personalized and more accurate."
            )
        case .privacy:
            onboardingTextBlock(
                title: nil,
                body: "Your data stays on your iPhone. No account. No cloud processing. No tracking."
            )
        case .permission:
            permissionScreen
        case .firstScore:
            OnboardingFirstScoreContent(appState: viewModel.appState)
        case .firstExplanation:
            OnboardingFirstExplanationContent(viewModel: viewModel)
        case .completion:
            onboardingTextBlock(
                title: "Helix improves over time.",
                body: "As your history grows, Helix becomes more personalized. Later, it can begin surfacing longer-term physiological patterns from your own history."
            )
        }
    }

    private func onboardingTextBlock(title: String?, body: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = title {
                Text(title)
                    .font(.system(size: 28, weight: .thin))
                    .foregroundColor(HelixTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(body)
                .font(HelixTypography.explanationBody)
                .foregroundColor(HelixTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private var modelScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your body runs on three systems:")
                .font(HelixTypography.explanationBody)
                .foregroundColor(HelixTheme.textSecondary)
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 14) {
                strandLine(color: HelixTheme.sleepColor, title: "Sleep", subtitle: "restores")
                strandLine(color: HelixTheme.loadColor, title: "Load", subtitle: "stresses")
                strandLine(color: HelixTheme.recoveryColor, title: "Recovery", subtitle: "rebuilds")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func strandLine(color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(color)
                Text(subtitle)
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
            }
            Spacer()
        }
    }

    private var permissionScreen: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Helix needs access to your health data.")
                .font(.system(size: 26, weight: .thin))
                .foregroundColor(HelixTheme.textPrimary)
                .padding(.top, 24)

            Text("Used only to calculate your Helix Index.")
                .font(HelixTypography.explanationBody)
                .foregroundColor(HelixTheme.textSecondary)
                .lineSpacing(4)

            if isLoadingHealth {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(HelixTheme.textSecondary)
                    Text("Reading your data…")
                        .font(HelixTypography.captionBody)
                        .foregroundColor(HelixTheme.textSecondary)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isLoadingHealth: Bool {
        switch viewModel.appState {
        case .requestingPermissions, .fetchingData:
            return true
        default:
            return false
        }
    }

    // MARK: — Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            switch step {
            case .permission:
                Button {
                    Task { await viewModel.loadToday() }
                } label: {
                    Text("Connect Health")
                        .font(.body.weight(.medium))
                        .foregroundColor(HelixTheme.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isLoadingHealth ? HelixTheme.pursueColor.opacity(0.45) : HelixTheme.pursueColor)
                        .cornerRadius(12)
                }
                .disabled(isLoadingHealth)
            case .completion:
                Button {
                    onboardingCompleted = true
                } label: {
                    Text("Go to Dashboard")
                        .font(.body.weight(.medium))
                        .foregroundColor(HelixTheme.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(HelixTheme.pursueColor)
                        .cornerRadius(12)
                }
            default:
                if step != .firstScore || canContinueFromFirstScore {
                    Button {
                        advance()
                    } label: {
                        Text(primaryButtonTitle)
                            .font(.body.weight(.medium))
                            .foregroundColor(HelixTheme.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(HelixTheme.pursueColor)
                            .cornerRadius(12)
                    }
                    .disabled(!canAdvance)
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .firstExplanation:
            return "Continue"
        default:
            return "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .firstScore:
            return canContinueFromFirstScore
        default:
            return true
        }
    }

    /// First score step: allow continue when load finished (any terminal state except pre-load).
    private var canContinueFromFirstScore: Bool {
        switch viewModel.appState {
        case .idle, .requestingPermissions, .fetchingData:
            return false
        default:
            return true
        }
    }

    private func advance() {
        guard let next = HelixOnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = next
        }
    }

    private func advanceFromPermissionStepWhenReady(_ state: HelixAppState) {
        guard step == .permission else { return }
        switch state {
        case .idle, .requestingPermissions, .fetchingData:
            return
        default:
            withAnimation(.easeInOut(duration: 0.25)) {
                step = .firstScore
            }
        }
    }
}

// MARK: — First score (live state)

private struct OnboardingFirstScoreContent: View {
    let appState: HelixAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your Helix today")
                .font(.system(size: 26, weight: .thin))
                .foregroundColor(HelixTheme.textPrimary)
                .padding(.top, 24)

            switch appState {
            case .idle, .requestingPermissions, .fetchingData:
                ProgressView()
                    .tint(HelixTheme.textSecondary)
                    .padding(.vertical, 24)
            case .learningBaseline(_):
                Text(AppStatePresentation(state: appState).statusMessage)
                    .font(HelixTypography.explanationBody)
                    .foregroundColor(HelixTheme.textSecondary)
                    .lineSpacing(4)
                Text("Helix is learning your baseline. Scores become more accurate as your history grows.")
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.confidenceMedium)
                    .padding(.top, 8)
            case .fullScore(let index):
                scoreBlocks(index: index, missingSignals: [])
            case .partialScore(let index, let missing):
                scoreBlocks(index: index, missingSignals: missing)
            case .developingBaseline(_, let index):
                scoreBlocks(index: index, missingSignals: [])
            case .suppressedScore:
                Text(AppStatePresentation(state: appState).statusMessage)
                    .font(HelixTypography.explanationBody)
                    .foregroundColor(HelixTheme.textSecondary)
            case .permissionsDenied:
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppStatePresentation(state: appState).statusMessage)
                        .font(HelixTypography.explanationBody)
                        .foregroundColor(HelixTheme.textSecondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.pursueColor)
                }
            case .healthKitUnavailable:
                Text(AppStatePresentation(state: appState).statusMessage)
                    .font(HelixTypography.explanationBody)
                    .foregroundColor(HelixTheme.textSecondary)
            case .error(let msg):
                Text("Could not load today: \(msg)")
                    .font(HelixTypography.explanationBody)
                    .foregroundColor(HelixTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scoreBlocks(index: HelixIndex, missingSignals: [SignalIdentifier]) -> some View {
        let posture = PosturePresentation(posture: index.posture)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(Int(index.score.rounded()))")
                    .font(.system(size: 56, weight: .thin, design: .rounded))
                    .foregroundColor(posture.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Helix Index")
                        .font(HelixTypography.microLabel)
                        .foregroundColor(HelixTheme.textSecondary)
                    Text(posture.headline)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(posture.color)
                }
            }

            VStack(spacing: 10) {
                strandRow(title: HelixStrand.sleep.displayLabel, score: index.sleepStrand.score, color: HelixTheme.sleepColor)
                strandRow(title: HelixStrand.load.displayLabel, score: index.loadStrand.score, color: HelixTheme.loadColor)
                strandRow(title: HelixStrand.recovery.displayLabel, score: index.recoveryStrand.score, color: HelixTheme.recoveryColor)
            }
            .padding(.top, 8)

            if !missingSignals.isEmpty {
                Text("\(missingSignals.count) signal\(missingSignals.count == 1 ? "" : "s") unavailable — score is estimated.")
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.confidenceMedium)
            }
        }
    }

    private func strandRow(title: String, score: Double, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(color)
            Spacer()
            Text("\(Int(score.rounded()))")
                .font(HelixTypography.scoreSmall)
                .foregroundColor(HelixTheme.textPrimary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(HelixTheme.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(HelixTheme.borderSubtle, lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

// MARK: — First explanation (engine + policy)

private struct OnboardingFirstExplanationContent: View {
    @ObservedObject var viewModel: HelixViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What Helix sees")
                .font(.system(size: 26, weight: .thin))
                .foregroundColor(HelixTheme.textPrimary)
                .padding(.top, 24)

            switch viewModel.appState {
            case .fullScore(let index), .partialScore(let index, _), .developingBaseline(_, let index):
                engineContributors(index: index)
            case .learningBaseline:
                Text(viewModel.getExplanationEngine().confidenceString(for: .low))
                    .font(HelixTypography.explanationBody)
                    .foregroundColor(HelixTheme.textSecondary)
                    .lineSpacing(4)
                Text(AppStatePresentation(state: viewModel.appState).statusMessage)
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
                    .padding(.top, 4)
            default:
                Text(viewModel.getExplanationEngine().confidenceString(for: .low))
                    .font(HelixTypography.explanationBody)
                    .foregroundColor(HelixTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func engineContributors(index: HelixIndex) -> some View {
        let engine = viewModel.getExplanationEngine()
        let strand = Self.bestStrand(for: index)
        let decomp = engine.buildDecomposition(from: strand, confidenceLevel: strand.confidence)
        let top = Array(decomp.topContributors.prefix(3))

        return VStack(alignment: .leading, spacing: 14) {
            Text(engine.resolveForDisplay(strand.primaryExplanation))
                .font(HelixTypography.explanationBody)
                .foregroundColor(HelixTheme.textPrimary)
                .lineSpacing(4)

            if !top.isEmpty {
                Text("Key signals")
                    .font(HelixTypography.microLabel)
                    .foregroundColor(HelixTheme.textSecondary)
                    .padding(.top, 4)

                ForEach(top, id: \.signal) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(c.signal.displayLabel)
                            .font(HelixTypography.signalLabel)
                            .foregroundColor(HelixTheme.textPrimary)
                        Text(engine.resolveForDisplay(c.explanation))
                            .font(HelixTypography.captionBody)
                            .foregroundColor(HelixTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HelixTheme.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(HelixTheme.borderSubtle, lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
            }

            if !decomp.missingSignals.isEmpty {
                Text("Missing: \(decomp.missingSignals.map(\.displayLabel).joined(separator: ", "))")
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.confidenceMedium)
            }
        }
    }

    private static func bestStrand(for index: HelixIndex) -> StrandScore {
        let candidates = [index.recoveryStrand, index.sleepStrand, index.loadStrand]
        if !index.recoveryStrand.contributionBreakdown.isEmpty {
            return index.recoveryStrand
        }
        return candidates.max(by: { $0.contributionBreakdown.count < $1.contributionBreakdown.count }) ?? index.recoveryStrand
    }
}
