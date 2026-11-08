import Foundation

/// Loads private framework functions at runtime, so a macOS update that removes one
/// disables that control instead of stopping the app from launching.
enum PrivateFramework {
    static func handle(_ path: String) -> UnsafeMutableRawPointer? {
        dlopen(path, RTLD_NOW)
    }

    static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: type) }
    }
}

/// Light and dark switching through SkyLight. No permission prompts needed.
struct SkyLightAppearance {
    private typealias Getter = @convention(c) () -> Int32
    private typealias Setter = @convention(c) (Int32) -> Int32

    private let getSwitchesAutomatically: Getter
    private let setSwitchesAutomatically: Setter
    private let getTheme: Getter
    private let setTheme: Setter

    init?() {
        guard let handle = PrivateFramework.handle("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"),
              let getAuto = PrivateFramework.symbol("SLSGetAppearanceThemeSwitchesAutomatically", in: handle, as: Getter.self),
              let setAuto = PrivateFramework.symbol("SLSSetAppearanceThemeSwitchesAutomatically", in: handle, as: Setter.self),
              let getTheme = PrivateFramework.symbol("SLSGetAppearanceThemeLegacy", in: handle, as: Getter.self),
              let setTheme = PrivateFramework.symbol("SLSSetAppearanceThemeLegacy", in: handle, as: Setter.self)
        else { return nil }
        self.getSwitchesAutomatically = getAuto
        self.setSwitchesAutomatically = setAuto
        self.getTheme = getTheme
        self.setTheme = setTheme
    }

    var switchesAutomatically: Bool {
        get { getSwitchesAutomatically() != 0 }
        nonmutating set { _ = setSwitchesAutomatically(newValue ? 1 : 0) }
    }

    var isDark: Bool {
        get { getTheme() != 0 }
        nonmutating set { _ = setTheme(newValue ? 1 : 0) }
    }
}
