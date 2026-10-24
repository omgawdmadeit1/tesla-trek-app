import ActivityKit
import Foundation

/// Shared Live Activity payload for an in-progress Tr3k.
/// The app and the widget extension both link this module so the attributes
/// type is the same process-to-process.
@available(iOS 16.1, *)
public struct Tr3kNavigationAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var instruction: String
        public var distanceText: String
        public var etaText: String
        public var stopName: String

        public init(instruction: String, distanceText: String, etaText: String, stopName: String) {
            self.instruction = instruction
            self.distanceText = distanceText
            self.etaText = etaText
            self.stopName = stopName
        }
    }

    public var trekName: String
    public var trekId: String

    public init(trekName: String, trekId: String) {
        self.trekName = trekName
        self.trekId = trekId
    }
}
