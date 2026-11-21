import AppKit
import SwiftUI

@main struct SliderCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        var value = 1.0
        let binding = Binding(get: { value }, set: { value = $0 })
        let parent = StableSlider(value: binding, in: 0.5...1.5, step: 0.001)
        let coordinator = parent.makeCoordinator()
        let native = TrackingSlider(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        native.minValue = 0.5; native.maxValue = 1.5; native.doubleValue = value
        native.increment = 0.001
        native.target = coordinator; native.action = #selector(StableSlider.Coordinator.changed(_:))
        precondition(native.accessibilityPerformIncrement() && abs(value - 1.001) < 0.00001)
        precondition(native.accessibilityPerformDecrement() && abs(value - 1) < 0.00001)
        native.doubleValue = 1.23456
        coordinator.changed(native)
        precondition(abs(value - 1.235) < 0.00001 && native.doubleValue == value, "Step quantization or accessibility value is wrong")
        for width in [60.0, 160.0, 300.0] {
            native.frame = NSRect(x: 37, y: 42, width: width, height: 22)
            let before = native.frame
            _ = native.accessibilityPerformIncrement()
            precondition(native.frame == before, "Value change moved the native control")
            precondition(native.layer?.animationKeys()?.isEmpty ?? true)
        }
        native.isEnabled = false
        let unchanged = value
        precondition(!native.accessibilityPerformIncrement() && value == unchanged)
        native.isEnabled = true; native.doubleValue = 1.5
        _ = native.accessibilityPerformIncrement()
        precondition(value == 1.5)
        print("Slider checks passed: continuous native control, quantization, accessibility increments, frame stability at three widths, disabled control and bounds.")
    }
}
