// Views,EnrichmentBannerView.swift
import SwiftUI

struct EnrichmentBannerView: View {
    @State private var isVisible = false
    @State private var dismissWorkItem: DispatchWorkItem?
    
    var body: some View {
        VStack {
            if isVisible {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("scanning_complete", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textMain)
                        Text(NSLocalizedString("scanning_complete_hint", comment: ""))
                            .font(.system(size: 11))
                            .foregroundColor(.textMuted)
                    }
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Text(NSLocalizedString("ok", comment: ""))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textMain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
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
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.darkSurface)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
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
        withAnimation { isVisible = true }
        
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
