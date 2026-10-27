// Views,DeveloperDiagnosticsView.swift
import SwiftUI
import AppKit

struct DeveloperDiagnosticsView: View {
    @ObservedObject var service = DeveloperDiagnosticsService.shared
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject private var settings = SettingsManager.shared

    @State private var selectedCategory: DiagnosticCategory = .all
    @State private var searchText: String = ""
    @State private var expandedTestIds: Set<String> = []
    @State private var copiedReport: Bool = false

    var onClose: () -> Void

    private var filteredResults: [DiagnosticTestResult] {
        service.results.filter { test in
            let matchesCategory = selectedCategory == .all || test.category == selectedCategory
            let matchesSearch = searchText.isEmpty ||
                test.name.localizedCaseInsensitiveContains(searchText) ||
                test.summary.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    private var passedCount: Int {
        service.results.filter { $0.status == .passed }.count
    }

    private var failedCount: Int {
        service.results.filter { $0.status == .failed }.count
    }

    private var warningCount: Int {
        service.results.filter { $0.status == .warning }.count
    }

    private var totalDurationMs: Double {
        service.results.reduce(0.0) { $0 + $1.durationMs }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            Divider().background(Color.white.opacity(0.1))

            // Category Filter Bar & Stats
            subHeaderBar

            Divider().background(Color.white.opacity(0.1))

            // Test list
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundColor(.textMuted.opacity(0.4))
                            Text("No diagnostic tests matching the filter")
                                .font(.system(size: 13))
                                .foregroundColor(.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(filteredResults) { test in
                            testRow(test)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(settings.darkSurface)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Developer Diagnostics & Test Suite")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textMain)
                Text("Automated audio engine validation, metadata readers, parser benchmarks & storage checks")
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }

            Spacer()

            // Tone generator button
            Button {
                if service.toneIsPlaying {
                    service.stopTestTone()
                } else {
                    service.playTestTone(frequency: 440.0, duration: 1.5)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: service.toneIsPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .foregroundColor(service.toneIsPlaying ? .green : .accent)
                    Text(service.toneIsPlaying ? "Playing 440Hz…" : "Test Tone (440Hz)")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(service.toneIsPlaying ? Color.green.opacity(0.15) : Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Run All Tests button
            Button {
                Task { await service.runAll() }
            } label: {
                HStack(spacing: 6) {
                    if service.isRunningAll {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    Text(service.isRunningAll ? "Running Tests…" : "Run All Tests")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(service.isRunningAll)

            // Copy Report
            Button {
                let report = service.generateReport()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
                copiedReport = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedReport = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copiedReport ? "checkmark" : "doc.on.doc")
                    Text(copiedReport ? "Copied!" : "Copy Report")
                }
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Close
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textMuted)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - SubHeader Bar (Category tabs & stats)

    private var subHeaderBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                // Category Pills
                ForEach(DiagnosticCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: category.icon)
                                .font(.system(size: 10))
                            Text(category.title)
                                .font(.system(size: 11, weight: selectedCategory == category ? .semibold : .regular))
                        }
                        .foregroundColor(selectedCategory == category ? .textMain : .textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedCategory == category ? Color.accent.opacity(0.25) : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedCategory == category ? Color.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                    TextField("Filter tests…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 130)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
            }

            // Stats summary pills
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(passedCount) Passed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textMain)
                }

                if warningCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("\(warningCount) Warnings")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textMain)
                    }
                }

                if failedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("\(failedCount) Failed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textMain)
                    }
                }

                Spacer()

                if totalDurationMs > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 10))
                        Text(String(format: "Total time: %.1f ms", totalDurationMs))
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.textMuted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Test Row Card

    private func testRow(_ test: DiagnosticTestResult) -> some View {
        let isExpanded = expandedTestIds.contains(test.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Main card header
            HStack(spacing: 12) {
                // Status icon
                statusIcon(for: test.status)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(test.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textMain)

                        Text(test.category.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                    }

                    Text(test.summary)
                        .font(.system(size: 11))
                        .foregroundColor(test.status == .failed ? .red.opacity(0.9) : .textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if test.durationMs > 0 {
                    Text(String(format: "%.2f ms", test.durationMs))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(4)
                }

                // Run individual test button
                Button {
                    Task { await service.runTest(id: test.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.accent)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(service.runningTestId == test.id || service.isRunningAll)

                // Expand/collapse logs button
                if !test.logs.isEmpty {
                    Button {
                        if isExpanded {
                            expandedTestIds.remove(test.id)
                        } else {
                            expandedTestIds.insert(test.id)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.textMuted)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Expanded Logs Accordion
            if isExpanded && !test.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Color.white.opacity(0.05))

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(test.logs.enumerated()), id: \.offset) { _, log in
                            HStack(alignment: .top, spacing: 6) {
                                Text("›")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.accent.opacity(0.7))
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .background(Color.black.opacity(0.2))
            }
        }
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor(for: test.status), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(for status: DiagnosticTestStatus) -> some View {
        switch status {
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
        case .running:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .notRun:
            Image(systemName: "circle.dotted")
                .foregroundColor(.textMuted.opacity(0.5))
                .font(.system(size: 14))
        }
    }

    private func borderColor(for status: DiagnosticTestStatus) -> Color {
        switch status {
        case .failed:
            return Color.red.opacity(0.3)
        case .warning:
            return Color.orange.opacity(0.3)
        case .passed:
            return Color.green.opacity(0.15)
        case .running:
            return Color.accent.opacity(0.4)
        case .notRun:
            return Color.white.opacity(0.06)
        }
    }
}
