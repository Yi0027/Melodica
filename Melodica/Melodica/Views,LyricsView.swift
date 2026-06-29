// Views,LyricsView.swift
import SwiftUI

struct LyricsView: View {
    let lyrics: [LyricsLine]
    let currentTime: TimeInterval
    @Binding var userScrolled: Bool
    let trackId: UUID?
    let onTapLine: ((TimeInterval) -> Void)?
    
    @State private var currentIndex: Int = -1
    @State private var ignoreScrollUntil: Date = Date.distantPast
    @State private var canShowButton: Bool = false
    @State private var isProgrammaticScroll = false
    @State private var hasInitialized: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                lyricList(proxy: proxy)
            }
            
            if userScrolled && canShowButton {
                syncButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: userScrolled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ForceResetLyricsView"))) { _ in
            currentIndex = -1
            userScrolled = false
            hasInitialized = false
            canShowButton = false
            updateCurrentIndex(time: currentTime)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasInitialized = true
                canShowButton = true
            }
        }
    }
    
    private func lyricList(proxy: ScrollViewProxy) -> some View {
        List {
            ForEach(Array(lyrics.enumerated()), id: \.element.id) { idx, line in
                lyricRow(idx: idx, line: line)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 24)
        .coordinateSpace(name: "scrollSpace")
        .onPreferenceChange(ViewOffsetKey.self) { _ in
            guard hasInitialized else { return }
            guard !isProgrammaticScroll else { return }
            guard Date() > ignoreScrollUntil else { return }
            if !userScrolled {
                userScrolled = true
            }
        }
        .onChange(of: trackId) { _ in
            hasInitialized = false
            currentIndex = -1
            userScrolled = false
            canShowButton = false
            isProgrammaticScroll = false
            ignoreScrollUntil = Date().addingTimeInterval(1.0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                hasInitialized = true
                canShowButton = true
            }
        }
        .onChange(of: currentIndex) { newIdx in
            if !userScrolled && newIdx >= 0 && hasInitialized {
                performProgrammaticScroll(to: newIdx, proxy: proxy)
            } else if newIdx == -1 {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(0, anchor: .top)
                }
            }
        }
        .onChange(of: currentTime) { time in
            updateCurrentIndex(time: time)
        }
        .onChange(of: userScrolled) { scrolled in
            if !scrolled && currentIndex >= 0 && hasInitialized {
                performProgrammaticScroll(to: currentIndex, proxy: proxy)
            }
        }
    }
    
    private func lyricRow(idx: Int, line: LyricsLine) -> some View {
        Text(line.text)
            .font(.system(size: 15))
            .foregroundColor(idx == currentIndex ? .lyricActive : .textMuted)
            .scaleEffect(idx == currentIndex ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: currentIndex)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .id(idx)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                userScrolled = true
                onTapLine?(line.time)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ViewOffsetKey.self,
                        value: [geo.frame(in: .named("scrollSpace")).midY]
                    )
                }
            )
    }
    
    private var syncButton: some View {
        Button(action: {
            userScrolled = false
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                Text(LocalizedStringKey("synch"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 16)
    }
    
    private func performProgrammaticScroll(to index: Int, proxy: ScrollViewProxy) {
        isProgrammaticScroll = true
        ignoreScrollUntil = Date().addingTimeInterval(0.5)
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(index, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isProgrammaticScroll = false
        }
    }
    
    private func updateCurrentIndex(time: TimeInterval) {
        var idx = -1
        for (i, line) in lyrics.enumerated() {
            if time >= line.time { idx = i } else { break }
        }
        
        // Если трек закончился — сбрасываем в начало
        if time >= (lyrics.last?.time ?? 0) + 1.0 && idx == lyrics.count - 1 {
            idx = -1
        }
        
        if idx != currentIndex {
            currentIndex = idx
        }
    }
}

struct ViewOffsetKey: PreferenceKey {
    typealias Value = [CGFloat]
    static var defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}
