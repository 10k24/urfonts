import SwiftUI

enum HostControlPhase: Equatable {
    case download
    case downloading(progress: Double?)
    case family(FamilyActivation)
    case file(FaceActivationState)
    case unavailable
}

struct HostActivationControl: View {
    let phase: HostControlPhase
    let action: () -> Void

    var body: some View {
        switch phase {
        case .download:
            Button(action: action) {
                Image(systemName: "square")
                    .font(.system(size: PreviewMetrics.activationIconSize))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: PreviewMetrics.activationHitSize,
                        height: PreviewMetrics.activationHitSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Messages.Activation.downloadAndActivate)
            .accessibilityLabel(Messages.Activation.downloadAndActivate)
        case .downloading(let progress):
            HostDownloadProgress(progress: progress)
        case .family(let state):
            ActivationDot(state: state, action: action)
        case .file(let state):
            FaceActivationControl(state: state, action: action)
        case .unavailable:
            Image(systemName: "questionmark.square")
                .font(.system(size: PreviewMetrics.activationIconSize))
                .foregroundStyle(.tertiary)
                .frame(
                    width: PreviewMetrics.activationHitSize,
                    height: PreviewMetrics.activationHitSize
                )
                .help(Messages.Activation.noDownloadableFiles)
                .accessibilityLabel(Messages.Activation.noDownloadableFiles)
        }
    }
}

/// Circular progress with a down arrow: the host download is running.
struct HostDownloadProgress: View {
    let progress: Double?
    @State private var sweep = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 2)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.15), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(sweep ? 360 : 0))
                    .animation(
                        .linear(duration: 0.9).repeatForever(autoreverses: false),
                        value: sweep
                    )
            }
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(
            width: PreviewMetrics.activationHitSize,
            height: PreviewMetrics.activationHitSize
        )
        .onAppear { sweep = true }
        .accessibilityLabel(Messages.Activation.downloading)
    }
}
