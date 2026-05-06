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
        guard !paths.isEmpty else { return }

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
            return
        }

        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
        streams.append(stream)
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

// FSEventStream callback.
//
// IMPORTANT: when the stream is created with `kFSEventStreamCreateFlagUseCFTypes`,
// the `eventPaths` parameter IS the `CFArrayRef` itself — not a pointer to one.
// The previous implementation did `eventPaths.assumingMemoryBound(to: UMRP?.self).pointee`,
// dereferencing one extra level, which read 8 bytes of garbage and crashed
// (`EXC_BAD_ACCESS` on Thread 4 / com.mcfinder.fsevents) the moment any file
// system event arrived. Cast `eventPaths` directly as a CFArray.
private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo, numEvents > 0 else { return }
    let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()

    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    guard let paths = cfPaths as? [String], !paths.isEmpty else { return }

    var maxEventId: FSEventStreamEventId = 0
    for i in 0..<numEvents {
        if eventIds[i] > maxEventId { maxEventId = eventIds[i] }
    }

    monitor.handleEvents(paths: paths, eventId: maxEventId)
}
