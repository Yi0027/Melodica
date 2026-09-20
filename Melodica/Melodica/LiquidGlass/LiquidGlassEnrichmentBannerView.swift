// Views,LiquidGlass,LiquidGlassEnrichmentBannerView.swift
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassEnrichmentBannerView: View {
    @State private var isVisible = false
    @State private var dismissWorkItem: DispatchWorkItem?

    var body: some View {
        VStack {
            if isVisible {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("scanning_complete", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(NSLocalizedString("scanning_complete_hint", comment: ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("ok", comment: ""))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        dismiss()
                        NotificationCenter.default.post(name: .saveStateOnExit, object: nil)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            restartApp()
                        }
                    }) {
                        Text(NSLocalizedString("restart", comment: ""))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            show()
        }
    }

    private func show() {
        dismissWorkItem?.cancel()

        withAnimation {
            isVisible = true
        }

        let workItem = DispatchWorkItem { dismiss() }
        dismissWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: workItem)
    }

    private func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        withAnimation(.easeInOut(duration: 0.3)) {
            isVisible = false
        }
    }

    private func restartApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
