// Services/FolderWatcherService.swift
import Foundation
import CoreServices

enum FolderWatchMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case off
    case poll1
    case poll10
    case poll30
    case poll60

    var id: String { rawValue }

    var pollingInterval: TimeInterval? {
        switch self {
        case .poll1:  return 60
        case .poll10: return 600
        case .poll30: return 1800
        case .poll60: return 3600
        default:      return nil
        }
    }
}

@MainActor
final class FolderWatcherService {
    static let shared = FolderWatcherService()

    /// Called when changes occur in a watched folder.
    /// URL is the root of the folder where a change occurred.
    private var onFolderChanged: ((URL) -> Void)?

    private var eventStreams: [String: FSEventStreamRef] = [:]
    private var pollTimers: [String: Timer] = [:]
    private var debounceTimers: [String: Timer] = [:]

    private init() {}

    func configure(onFolderChanged: @escaping (URL) -> Void) {
        self.onFolderChanged = onFolderChanged
    }

    /// Applies a set of modes — starts missing watchers and stops unused ones. Idempotent.
    func apply(modes: [String: FolderWatchMode]) {
        // Stop everything not present in the new set or where mode == .off
        let existing = Set(eventStreams.keys).union(pollTimers.keys)
        for path in existing {
            let newMode = modes[path] ?? .off
            if newMode == .off {
                stopWatching(path: path)
            }
        }

        for (path, mode) in modes {
            switch mode {
            case .off:
                stopWatching(path: path)
            case .auto:
                pollTimers.removeValue(forKey: path)?.invalidate()
                startFSEvents(path: path)
            case .poll1, .poll10, .poll30, .poll60:
                if let stream = eventStreams.removeValue(forKey: path) {
                    FSEventStreamStop(stream)
                    FSEventStreamInvalidate(stream)
                    FSEventStreamRelease(stream)
                }
                startPolling(path: path, interval: mode.pollingInterval ?? 600)
            }
        }
    }

    /// Stops all watchers.
    func stopAll() {
        for path in eventStreams.keys { stopWatching(path: path) }
        for path in pollTimers.keys { stopWatching(path: path) }
    }

    // MARK: - Private

    private func stopWatching(path: String) {
        if let stream = eventStreams.removeValue(forKey: path) {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        pollTimers.removeValue(forKey: path)?.invalidate()
        debounceTimers.removeValue(forKey: path)?.invalidate()
    }

    private func startFSEvents(path: String) {
        guard eventStreams[path] == nil else { return }

        // If folder does not physically exist, do not start (e.g., external disk disconnected)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()

        var streamContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [path] as CFArray

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let service = Unmanaged<FolderWatcherService>.fromOpaque(info).takeUnretainedValue()

            // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray of CFString.
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let paths = (cfArray as NSArray) as? [String] ?? []

            Task { @MainActor in
                for p in paths {
                    service.handleFSEvent(rawPath: p, numEvents: numEvents)
                }
            }
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &streamContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency (sec)
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        eventStreams[path] = stream
    }

    private func handleFSEvent(rawPath: String?, numEvents: Int) {
        guard let rawPath else { return }

        // Determine which watched folder the event belongs to
        let root = eventStreams.keys
            .filter { rawPath.hasPrefix($0) }
            .max(by: { $0.count < $1.count }) ?? rawPath

        // Debounce: if events arrive in a batch (e.g. copying 100 files),
        // wait 2 seconds after the last event before scanning.
        debounceTimers[root]?.invalidate()
        debounceTimers[root] = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.onFolderChanged?(URL(fileURLWithPath: root))
            }
        }
    }

    private func startPolling(path: String, interval: TimeInterval) {
        guard pollTimers[path] == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.onFolderChanged?(URL(fileURLWithPath: path))
            }
        }
        pollTimers[path] = timer
    }
}
