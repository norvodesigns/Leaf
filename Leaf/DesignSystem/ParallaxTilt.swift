import CoreMotion
import SwiftUI

/// A calm tilt for parallax: device-motion gravity at 30 Hz through `TiltFilter` (smoothed, a dead zone, clamped,
/// drifting back to however the phone is held), shared, running only while something on screen asks for it and never
/// in Low Power Mode. `tilt` changes only when the change is big enough to see, so a phone held still or lying flat
/// causes no updates at all. Callers don't start it under Reduce Motion.
@MainActor
@Observable
final class ParallaxTilt {
    static let shared = ParallaxTilt()

    /// How far the phone has moved from the way it is held, x to the right and y down, each within ±`TiltFilter.limit`.
    private(set) var tilt = RibbonVector.zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var filter = TiltFilter()

    private init() {}

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        filter.reset()
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            if let next = self.filter.feed(RibbonVector(x: g.x, y: -g.y)) {
                self.tilt = next
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        filter.reset()
        if tilt != .zero { tilt = .zero }
    }
}
