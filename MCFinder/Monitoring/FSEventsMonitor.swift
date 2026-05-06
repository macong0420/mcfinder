import Foundation
import CoreServices
import OSLog

final class FSEventsMonitor: @unchecked Sendable {
    private var streams: [FSEventStreamRef] = []
    private let callbackQueue = DispatchQueue(label: "com.mcfinder.fsevents", qos: .utility)
    private var pendingPaths = Set<String>()
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 2.0
    private var lastEventId: FSEventStreamEventId = 0
    private let defaults = UserDefaults.standard
    private let lastEventIdKey = "MCFinder.lastFSEventId"

    weak var delegate: FSEventsDelegate?
    var onChangeDetected: ((Set<String>) -> Void)?

    init() {
        lastEventId = FSEventStreamEventId(defaults.integer(forKey: lastEventIdKey))
    }

    func startWatching(paths: [String]) {
        stopWatching()
        guard !paths.isEmpty else {
            // Logger.fsEvents.info("No paths to watch")
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventCallback,
            &context,
            paths as CFArray,
            lastEventId,
            1.0,
            flags
        ) else {
            // Logger.fsEvents.error("Failed to create FSEventStream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
        streams.append(stream)
        // Logger.fsEvents.info("Started watching \(paths.count) paths")
    }

    func stopWatching() {
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
        debounceWorkItem?.cancel()
    }

    fileprivate func handleEvents(paths: [String], eventId: FSEventStreamEventId) {
        for path in paths { pendingPaths.insert(path) }
        lastEventId = max(lastEventId, eventId)
        defaults.set(Int(lastEventId), forKey: lastEventIdKey)

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = self.pendingPaths
            self.pendingPaths.removeAll()
            self.delegate?.fsEventsMonitor(self, didReceiveChanges: paths)
            self.onChangeDetected?(paths)
        }
        debounceWorkItem = workItem
        callbackQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}

private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()

    let pathsPointer = eventPaths.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
    guard let pathsArrayPointer = pathsPointer.pointee else { return }
    let paths = Unmanaged<CFArray>.fromOpaque(pathsArrayPointer).takeUnretainedValue() as! [String]
    let maxEventId = (0..<numEvents).map { eventIds[$0] }.max() ?? 0

    monitor.handleEvents(paths: paths, eventId: maxEventId)
}
