// Views,ScrollingText.swift
import SwiftUI

// MARK: - Synchronized Track Info (Title + Artist)
struct SynchronizedScrollingTrackInfo: View {
    let title: String
    let artist: String
    var titleFont: Font = .system(size: 12, weight: .medium)
    var titleColor: Color = .primary
    var artistFont: Font = .system(size: 10.5)
    var artistColor: Color = .secondary
    var spacing: CGFloat = 2
    var speed: Double = 25
    var pauseDelay: Double = 2.0
    var gap: CGFloat = 36
    
    @State private var containerWidth: CGFloat = 0
    @State private var titleWidth: CGFloat = 0
    @State private var artistWidth: CGFloat = 0
    @State private var titleOffset: CGFloat = 0
    @State private var artistOffset: CGFloat = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            titleRow
            artistRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SynchronizedWidthKey.self,
                    value: geo.size.width
                )
            }
        )
        .background(
            VStack {
                Text(title.isEmpty ? " " : title)
                    .font(titleFont)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: SynchronizedTitleWidthKey.self,
                                value: geo.size.width
                            )
                        }
                    )
                Text(artist.isEmpty ? " " : artist)
                    .font(artistFont)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: SynchronizedArtistWidthKey.self,
                                value: geo.size.width
                            )
                        }
                    )
            }
            .hidden()
        )
        .onPreferenceChange(SynchronizedWidthKey.self) { newWidth in
            containerWidth = newWidth
        }
        .onPreferenceChange(SynchronizedTitleWidthKey.self) { newWidth in
            titleWidth = newWidth
        }
        .onPreferenceChange(SynchronizedArtistWidthKey.self) { newWidth in
            artistWidth = newWidth
        }
        .task(id: "\(title)|\(artist)|\(Int(containerWidth))|\(Int(titleWidth))|\(Int(artistWidth))") {
            var resetTx = Transaction()
            resetTx.disablesAnimations = true
            withTransaction(resetTx) {
                titleOffset = 0
                artistOffset = 0
            }
            
            let needsScrollTitle = (titleWidth - containerWidth) > 1.0 && containerWidth > 0
            let needsScrollArtist = (artistWidth - containerWidth) > 1.0 && containerWidth > 0
            
            guard needsScrollTitle || needsScrollArtist else { return }
            
            let distanceTitle = needsScrollTitle ? (titleWidth + gap) : 0
            let distanceArtist = needsScrollArtist ? (artistWidth + gap) : 0
            let durationTitle = needsScrollTitle ? (distanceTitle / speed) : 0
            let durationArtist = needsScrollArtist ? (distanceArtist / speed) : 0
            
            while !Task.isCancelled {
                // Pause at start (countdown before scroll begins)
                try? await Task.sleep(nanoseconds: UInt64(pauseDelay * 1_000_000_000))
                if Task.isCancelled { break }
                
                if needsScrollTitle && needsScrollArtist {
                    // Both scroll together at the exact same speed
                    withAnimation(.linear(duration: durationTitle)) {
                        titleOffset = -distanceTitle
                    }
                    withAnimation(.linear(duration: durationArtist)) {
                        artistOffset = -distanceArtist
                    }
                    
                    if durationTitle < durationArtist {
                        // Title finishes earlier, snaps back to start, and waits for Artist
                        try? await Task.sleep(nanoseconds: UInt64(durationTitle * 1_000_000_000))
                        if Task.isCancelled { break }
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            titleOffset = 0
                        }
                        
                        let remaining = durationArtist - durationTitle
                        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                        if Task.isCancelled { break }
                        withTransaction(tx) {
                            artistOffset = 0
                        }
                    } else if durationArtist < durationTitle {
                        // Artist finishes earlier, snaps back to start, and waits for Title
                        try? await Task.sleep(nanoseconds: UInt64(durationArtist * 1_000_000_000))
                        if Task.isCancelled { break }
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            artistOffset = 0
                        }
                        
                        let remaining = durationTitle - durationArtist
                        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                        if Task.isCancelled { break }
                        withTransaction(tx) {
                            titleOffset = 0
                        }
                    } else {
                        // Equal duration
                        try? await Task.sleep(nanoseconds: UInt64(durationTitle * 1_000_000_000))
                        if Task.isCancelled { break }
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            titleOffset = 0
                            artistOffset = 0
                        }
                    }
                } else if needsScrollTitle {
                    // Only Title scrolls
                    withAnimation(.linear(duration: durationTitle)) {
                        titleOffset = -distanceTitle
                    }
                    try? await Task.sleep(nanoseconds: UInt64(durationTitle * 1_000_000_000))
                    if Task.isCancelled { break }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        titleOffset = 0
                    }
                } else if needsScrollArtist {
                    // Only Artist scrolls
                    withAnimation(.linear(duration: durationArtist)) {
                        artistOffset = -distanceArtist
                    }
                    try? await Task.sleep(nanoseconds: UInt64(durationArtist * 1_000_000_000))
                    if Task.isCancelled { break }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) {
                        artistOffset = 0
                    }
                }
                // Both offsets are now 0. Countdown (pauseDelay) runs before next scroll begins.
            }
        }
    }
    
    private var titleRow: some View {
        let needsScroll = (titleWidth - containerWidth) > 1.0 && containerWidth > 0
        return Text(title.isEmpty ? " " : title)
            .font(titleFont)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                ZStack(alignment: .leading) {
                    if needsScroll {
                        HStack(spacing: gap) {
                            Text(title)
                                .font(titleFont)
                                .foregroundColor(titleColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            
                            Text(title)
                                .font(titleFont)
                                .foregroundColor(titleColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .offset(x: titleOffset)
                        .frame(width: containerWidth, alignment: .leading)
                        .clipped()
                        .mask(marqueeMask(offset: titleOffset))
                    } else {
                        Text(title)
                            .font(titleFont)
                            .foregroundColor(titleColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                },
                alignment: .leading
            )
    }
    
    private var artistRow: some View {
        let needsScroll = (artistWidth - containerWidth) > 1.0 && containerWidth > 0
        return Text(artist.isEmpty ? " " : artist)
            .font(artistFont)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                ZStack(alignment: .leading) {
                    if needsScroll {
                        HStack(spacing: gap) {
                            Text(artist)
                                .font(artistFont)
                                .foregroundColor(artistColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            
                            Text(artist)
                                .font(artistFont)
                                .foregroundColor(artistColor)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .offset(x: artistOffset)
                        .frame(width: containerWidth, alignment: .leading)
                        .clipped()
                        .mask(marqueeMask(offset: artistOffset))
                    } else {
                        Text(artist)
                            .font(artistFont)
                            .foregroundColor(artistColor)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                },
                alignment: .leading
            )
    }
    
    private func marqueeMask(offset: CGFloat) -> some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [offset < -2 ? Color.clear : Color.black, Color.black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 8)
            
            Rectangle().fill(Color.black)
            
            LinearGradient(
                colors: [Color.black, Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 12)
        }
    }
}

private struct SynchronizedWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SynchronizedTitleWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SynchronizedArtistWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Standalone Scrolling Text
struct ScrollingText: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .primary
    var speed: Double = 25
    var pauseDelay: Double = 2.0
    var gap: CGFloat = 36
    
    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    
    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                GeometryReader { geo in
                    let availableWidth = geo.size.width
                    let needsScroll = (textWidth - availableWidth) > 1.0 && availableWidth > 0
                    
                    ZStack(alignment: .leading) {
                        if needsScroll {
                            HStack(spacing: gap) {
                                Text(text)
                                    .font(font)
                                    .foregroundColor(color)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                
                                Text(text)
                                    .font(font)
                                    .foregroundColor(color)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .offset(x: offset)
                            .frame(width: availableWidth, alignment: .leading)
                            .clipped()
                            .mask(
                                HStack(spacing: 0) {
                                    LinearGradient(
                                        colors: [offset < -2 ? Color.clear : Color.black, Color.black],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: 8)
                                    
                                    Rectangle().fill(Color.black)
                                    
                                    LinearGradient(
                                        colors: [Color.black, Color.clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: 12)
                                }
                            )
                        } else {
                            Text(text)
                                .font(font)
                                .foregroundColor(color)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .onAppear {
                        containerWidth = availableWidth
                    }
                    .onChange(of: availableWidth) {
                        containerWidth = availableWidth
                    }
                }
            )
            .background(
                Text(text.isEmpty ? " " : text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { textGeo in
                            Color.clear.preference(
                                key: ScrollingTextSizeKey.self,
                                value: textGeo.size
                            )
                        }
                    )
                    .hidden()
            )
            .onPreferenceChange(ScrollingTextSizeKey.self) { size in
                textWidth = size.width
                textHeight = size.height
            }
            .task(id: "\(text)|\(Int(containerWidth))|\(Int(textWidth))") {
                var resetTx = Transaction()
                resetTx.disablesAnimations = true
                withTransaction(resetTx) {
                    offset = 0
                }
                
                guard containerWidth > 0, (textWidth - containerWidth) > 1.0 else { return }
                
                let totalDistance = textWidth + gap
                let duration = totalDistance / speed
                
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(pauseDelay * 1_000_000_000))
                    if Task.isCancelled { break }
                    
                    withAnimation(.linear(duration: duration)) {
                        offset = -totalDistance
                    }
                    
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    if Task.isCancelled { break }
                    
                    var loopTx = Transaction()
                    loopTx.disablesAnimations = true
                    withTransaction(loopTx) {
                        offset = 0
                    }
                }
            }
    }
}

private struct ScrollingTextSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(
            width: max(value.width, next.width),
            height: max(value.height, next.height)
        )
    }
}
