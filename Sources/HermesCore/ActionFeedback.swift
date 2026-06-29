import Foundation
import Observation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ActionFeedbackKind: Equatable {
    case information
    case success
    case warning
    case destructive
}

struct ActionFeedback: Identifiable, Equatable {
    let id: UUID
    let message: String
    let systemImage: String
    let kind: ActionFeedbackKind

    init(
        id: UUID = UUID(),
        message: String,
        systemImage: String,
        kind: ActionFeedbackKind
    ) {
        self.id = id
        self.message = message
        self.systemImage = systemImage
        self.kind = kind
    }
}

@MainActor
@Observable
final class ActionFeedbackCenter {
    static let shared = ActionFeedbackCenter()

    private(set) var current: ActionFeedback?
    private let automaticDismissal: Bool
    private var dismissalTask: Task<Void, Never>?

    init(automaticDismissal: Bool = true) {
        self.automaticDismissal = automaticDismissal
    }

    func show(_ message: String, systemImage: String, kind: ActionFeedbackKind) {
        dismissalTask?.cancel()
        let feedback = ActionFeedback(
            message: message,
            systemImage: systemImage,
            kind: kind
        )
        current = feedback
        performHaptic(for: kind)

        guard automaticDismissal else { return }
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled, self?.current?.id == feedback.id else { return }
            self?.current = nil
        }
    }

    func dismissCurrent() {
        dismissalTask?.cancel()
        dismissalTask = nil
        current = nil
    }

    private func performHaptic(for kind: ActionFeedbackKind) {
#if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        switch kind {
        case .information:
            return
        case .success:
            generator.notificationOccurred(.success)
        case .warning:
            generator.notificationOccurred(.warning)
        case .destructive:
            generator.notificationOccurred(.error)
        }
#elseif os(macOS)
        guard kind != .information else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = kind == .success ? .alignment : .levelChange
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
#endif
    }
}

struct ActionFeedbackBanner: View {
    let feedback: ActionFeedback

    var body: some View {
        Label(feedback.message, systemImage: feedback.systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
            .accessibilityAddTraits(.isStaticText)
    }

    private var tint: Color {
        switch feedback.kind {
        case .information: .blue
        case .success: .green
        case .warning: .orange
        case .destructive: .red
        }
    }
}

private struct ActionFeedbackOverlayModifier: ViewModifier {
    @Bindable var center: ActionFeedbackCenter
    let bottomInset: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let feedback = center.current {
                ActionFeedbackBanner(feedback: feedback)
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: center.current?.id)
    }
}

@MainActor
extension View {
    func actionFeedbackOverlay(
        _ center: ActionFeedbackCenter,
        bottomInset: CGFloat = 16
    ) -> some View {
        modifier(ActionFeedbackOverlayModifier(center: center, bottomInset: bottomInset))
    }
}
