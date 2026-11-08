import Foundation

public struct NightShiftStatus: Sendable, Equatable {
    public enum Mode: Int32, Sendable {
        case off = 0, sunsetToSunrise = 1, custom = 2
    }

    public struct Time: Sendable, Equatable {
        public var hour: Int
        public var minute: Int

        public init(hour: Int, minute: Int) {
            self.hour = hour
            self.minute = minute
        }

        /// Parses `HH:MM`.
        public init?(_ text: String) {
            let parts = text.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
            self.init(hour: parts[0], minute: parts[1])
        }

        public var text: String { String(format: "%02d:%02d", hour, minute) }
    }

    public var mode: Mode
    public var from: Time
    public var to: Time
    public var isEnabled: Bool
    /// Whether location access allows the sunset to sunrise mode.
    public var isSunSchedulePermitted: Bool

    /// Parses `CBBlueLightStatus`. Its layout is private, and was checked on macOS 27.2.
    init?(statusBytes bytes: UnsafeRawPointer) {
        guard let mode = Mode(rawValue: bytes.load(fromByteOffset: 4, as: Int32.self)) else { return nil }
        self.mode = mode
        self.isEnabled = bytes.load(fromByteOffset: 1, as: UInt8.self) != 0
        self.isSunSchedulePermitted = bytes.load(fromByteOffset: 2, as: UInt8.self) != 0
        self.from = Time(hour: Int(bytes.load(fromByteOffset: 8, as: Int32.self)),
                         minute: Int(bytes.load(fromByteOffset: 12, as: Int32.self)))
        self.to = Time(hour: Int(bytes.load(fromByteOffset: 16, as: Int32.self)),
                       minute: Int(bytes.load(fromByteOffset: 20, as: Int32.self)))
    }
}

/// Reads the Night Shift schedule that drives the macOS Auto appearance.
@MainActor
public final class NightShiftClient {
    private let client: NSObject

    public init?() {
        guard PrivateFramework.handle("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness") != nil,
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else { return nil }
        client = type.init()
    }

    public func status() -> NightShiftStatus? {
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector) else { return nil }

        typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let getStatus = unsafeBitCast(client.method(for: selector), to: GetStatus.self)

        // Larger than the struct, in case a macOS update makes it bigger.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 256, alignment: 16)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: 256)

        guard getStatus(client, selector, buffer) else { return nil }
        return NightShiftStatus(statusBytes: buffer)
    }

    /// Changing the schedule also moves the macOS Auto appearance, immediately if the current
    /// time falls on the other side of it.
    @discardableResult
    public func setMode(_ mode: NightShiftStatus.Mode) -> Bool {
        let selector = NSSelectorFromString("setMode:")
        guard client.responds(to: selector) else { return false }
        typealias SetMode = @convention(c) (AnyObject, Selector, Int32) -> Bool
        return unsafeBitCast(client.method(for: selector), to: SetMode.self)(client, selector, mode.rawValue)
    }

    /// Sets custom times. The mode must be `.custom` for them to take effect.
    @discardableResult
    public func setSchedule(from: NightShiftStatus.Time, to: NightShiftStatus.Time) -> Bool {
        let selector = NSSelectorFromString("setSchedule:")
        guard client.responds(to: selector) else { return false }
        typealias SetSchedule = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let setSchedule = unsafeBitCast(client.method(for: selector), to: SetSchedule.self)
        var times = [from.hour, from.minute, to.hour, to.minute].map(Int32.init)
        return times.withUnsafeMutableBytes { setSchedule(client, selector, $0.baseAddress!) }
    }
}
