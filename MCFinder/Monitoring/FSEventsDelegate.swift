import Foundation

protocol FSEventsDelegate: AnyObject {
    func fsEventsMonitor(_ monitor: FSEventsMonitor, didReceiveChanges paths: Set<String>)
}
