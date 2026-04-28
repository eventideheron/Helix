// Features/Onboarding/PermissionsView.swift
// Shown when appState == .permissionsDenied or first launch before permissions are requested.
// Explains clearly what health data is read and why. No dark patterns.

import SwiftUI

struct PermissionsView: View {

    let onRequestPermissions: () async -> Void

    private let signals: [(icon: String, label: String, reason: String)] = [
        ("heart.fill",         "Heart Rate",           "Used to calculate overnight HR dip and resting baseline"),
        ("waveform.path.ecg",  "Heart Rate Variability","Primary autonomic recovery marker — the most important signal"),
        ("lungs.fill",         "Respiratory Rate",     "Overnight breathing rate is an early illness and overtraining signal"),
        ("bed.double.fill",    "Sleep",                "Duration, staging, and consistency across all three strands"),
        ("thermometer",        "Wrist Temperature",    "Sensitive indicator of immune activation and recovery state"),
        ("flame.fill",         "Active Energy",        "Non-exercise movement contributes to daily training load"),
        ("figure.run",         "Workouts",             "Heart rate zones during exercise determine Training Stress Score"),
        ("drop.fill",          "Blood Oxygen",         "7-night rolling average modifies respiratory recovery score")
    ]

    var body: some View {
        ZStack {
            HelixTheme.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HELIX")
                            .font(HelixTypography.sectionHeader)
                            .tracking(HelixTracking.sectionHeader)
                            .foregroundColor(HelixTheme.textSecondary)
                            .padding(.top, 60)

                        Text("Your health data\nstays on your iPhone.")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(HelixTheme.textPrimary)
                            .lineSpacing(4)

                        Text("Helix reads Apple Health to compute your daily readiness score. No cloud. No account. All calculation happens on device.")
                            .font(HelixTypography.explanationBody)
                            .foregroundColor(HelixTheme.textSecondary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)

                    // Signal list
                    VStack(alignment: .leading, spacing: 0) {
                        Text("WHAT HELIX READS")
                            .font(HelixTypography.microLabel)
                            .tracking(HelixTracking.sectionHeader)
                            .foregroundColor(HelixTheme.textSecondary)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 12)

                        ForEach(signals, id: \.label) { signal in
                            SignalPermissionRow(
                                icon: signal.icon,
                                label: signal.label,
                                reason: signal.reason
                            )
                        }
                    }
                    .padding(.bottom, 36)

                    // Privacy statement
                    Text("Helix never writes to Apple Health, never transmits data externally, and requires no account. Denying individual permissions reduces score accuracy — it does not prevent the app from running.")
                        .font(HelixTypography.captionBody)
                        .foregroundColor(HelixTheme.textSecondary)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 36)

                    // CTA
                    Button {
                        Task { await onRequestPermissions() }
                    } label: {
                        Text("Connect Apple Health")
                            .font(.body.weight(.medium))
                            .foregroundColor(HelixTheme.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(HelixTheme.pursueColor)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 48)
                }
            }
        }
    }
}

struct SignalPermissionRow: View {
    let icon:   String
    let label:  String
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(HelixTheme.pursueColor)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(HelixTypography.signalLabel)
                    .foregroundColor(HelixTheme.textPrimary)
                Text(reason)
                    .font(HelixTypography.captionBody)
                    .foregroundColor(HelixTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }
}


// Features/Onboarding/BaselineLearningView.swift
// Shown when appState == .learningBaseline(daysRemaining:)
// Communicates the learning phase clearly without feeling like a broken state.

struct BaselineLearningView: View {

    let daysRemaining: Int
    let daysRecorded:  Int

    private var progress: Double {
        let total = Double(daysRemaining + daysRecorded)
        guard total > 0 else { return 0 }
        return Double(daysRecorded) / total
    }

    var body: some View {
        ZStack {
            HelixTheme.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(HelixTheme.borderSubtle, lineWidth: 3)
                        .frame(width: 120, height: 120)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(HelixTheme.pursueColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)
                    VStack(spacing: 4) {
                        Text("\(daysRecorded)")
                            .font(HelixTypography.scoreMedium)
                            .foregroundColor(HelixTheme.textPrimary)
                        Text("days")
                            .font(HelixTypography.captionBody)
                            .foregroundColor(HelixTheme.textSecondary)
                    }
                }

                VStack(spacing: 12) {
                    Text("Learning your baseline")
                        .font(.system(size: 22, weight: .thin))
                        .foregroundColor(HelixTheme.textPrimary)

                    Text("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") until your first full score")
                        .font(HelixTypography.captionBody)
                        .foregroundColor(HelixTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    learningPoint(
                        icon: "checkmark.circle",
                        text: "Helix is recording your sleep, heart rate, and activity each day"
                    )
                    learningPoint(
                        icon: "chart.line.uptrend.xyaxis",
                        text: "Your personal baselines are being established from your own data"
                    )
                    learningPoint(
                        icon: "lock.fill",
                        text: "Everything stays on your device — no cloud sync required"
                    )
                }
                .padding(.horizontal, 40)

                Spacer()
            }
        }
    }

    private func learningPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(HelixTheme.pursueColor)
                .frame(width: 22)
                .padding(.top, 1)
            Text(text)
                .font(HelixTypography.captionBody)
                .foregroundColor(HelixTheme.textSecondary)
            Spacer()
        }
    }
}
