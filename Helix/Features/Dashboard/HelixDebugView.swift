// HelixDebugView.swift
// Temporary debug panel to inspect ViewModel state. Excluded from Release builds.

#if DEBUG
import SwiftUI
import UIKit

struct HelixDebugView: View {

    @ObservedObject var viewModel: HelixViewModel

    private static let captureDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = .autoupdatingCurrent
        return f
    }()

    private var debugString: String {
        var lines: [String] = []
        lines.append("=== HELIX STATE CAPTURE ===")
        lines.append("Captured: \(Self.captureDateFormatter.string(from: Date()))")
        lines.append("App State: \(viewModel.appState)")

        guard let index = viewModel.indexFromState else {
            lines.append("")
            lines.append("No score available — app state: \(viewModel.appState)")
            lines.append("")
            lines.append("=== END CAPTURE ===")
            return lines.joined(separator: "\n")
        }

        let gateLevelStr = viewModel.recoveryGateLevel.map { "\($0.rawValue)" } ?? "nil"
        let interaction = viewModel.interactionTerms

        lines.append("")
        lines.append("--- INDEX ---")
        lines.append("Helix Score: \(index.score)")
        lines.append("Posture: \(index.posture.rawValue)")
        lines.append("Confidence: \(index.overallConfidence.rawValue)")
        lines.append("Balance Penalty: \(viewModel.balancePenalty.map { "\($0)" } ?? "nil")")
        lines.append("Recovery Gate: \(viewModel.recoveryGateApplied) / \(gateLevelStr)")
        if let it = interaction {
            lines.append("Interaction: sleepBoost=\(it.sleepBoostApplied) loadCost=\(it.loadCostApplied) net=\(it.netInteractionEffect)")
        } else {
            lines.append("Interaction: sleepBoost=— loadCost=— net=—")
        }

        if let sleep = viewModel.sleepStrand {
            lines.append("")
            lines.append(Self.strandBlock(title: "SLEEP STRAND", strand: sleep))
        }
        if let load = viewModel.loadStrand {
            lines.append("")
            lines.append(Self.strandBlock(title: "LOAD STRAND", strand: load))
        }
        if let recovery = viewModel.recoveryStrand {
            lines.append("")
            lines.append(Self.strandBlock(title: "RECOVERY STRAND", strand: recovery))
        }

        let insight = viewModel.crossStrandInsight
        lines.append("")
        lines.append("--- CROSS-STRAND INSIGHT ---")
        lines.append("Pattern: \(insight?.patternID ?? "nil")")
        lines.append("Headline: \(insight?.depth2Headline ?? "—")")

        lines.append("")
        lines.append("=== END CAPTURE ===")
        return lines.joined(separator: "\n")
    }

    private static func strandBlock(title: String, strand: StrandScore) -> String {
        var lines: [String] = []
        lines.append("--- \(title) ---")
        lines.append("Score: \(strand.score)")
        lines.append("Confidence: \(strand.confidence.rawValue)")
        let primary = strand.primaryExplanation.replacingOccurrences(of: "\n", with: " ")
        lines.append("Primary Explanation: \(primary)")
        let missingLabels = strand.missingSignals.map(\.displayLabel)
        lines.append("Missing: \(missingLabels.isEmpty ? "—" : missingLabels.joined(separator: ", "))")
        lines.append("Contributions:")
        let sorted = strand.contributionBreakdown.sorted {
            abs($0.pointContribution) > abs($1.pointContribution)
        }
        if sorted.isEmpty {
            lines.append("  —")
        } else {
            for c in sorted {
                let pts = String(format: "%+.2f", c.pointContribution)
                let expl = c.explanation.replacingOccurrences(of: "\n", with: " ")
                let delta = c.deltaDescription.replacingOccurrences(of: "\n", with: " ")
                lines.append("  \(c.signal.displayLabel): \(pts) | \(expl) | \(delta)")
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            Text(debugString)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("Helix Debug")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Share") {
                    Self.presentShareSheet(text: debugString)
                }
                Button("Copy") {
                    UIPasteboard.general.string = debugString
                }
            }
        }
    }

    private static func presentShareSheet(text: String) {
        let controller = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
            let root = window.rootViewController
        else { return }

        if let popover = controller.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        root.present(controller, animated: true)
    }
}
#endif
