import Foundation

public struct NightShiftStatus: Sendable, Equatable {
    public enum Mode: Int32, Sendable {
        case off = 0, sunsetToSunrise = 1, custom = 2
    }

    public struct Time: Sendable, Equatable {
        public var hour: Int
        public var minute: Int
    }

    public var mode: Mode
    public var from: Time
    public var to: Time
    public var isEnabled: Bool

    /// Parses `CBBlueLightStatus`. Its layout is private, and was checked on macOS 27.2.
    init?(statusBytes bytes: UnsafeRawPointer) {
        guard let mode = Mode(rawValue: bytes.load(fromByteOffset: 4, as: Int32.self)) else { return nil }
        self.mode = mode
        self.isEnabled = bytes.load(fromByteOffset: 1, as: UInt8.self) != 0
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
}
