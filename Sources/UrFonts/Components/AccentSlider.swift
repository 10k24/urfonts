import AppKit
import SwiftUI

/// A native slider with an explicit accent fill.
///
/// SwiftUI's `Slider` renders untinted inside a macOS 26/27 toolbar even when
/// `.tint` is set. The preview size control lives in the status bar today; this
/// wrapper keeps the accent explicit so moving it back into a toolbar cannot
/// silently turn it gray.
struct AccentSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        slider.isContinuous = true
        if #available(macOS 26.0, *) {
            slider.tintProminence = .primary
        }
        slider.trackFillColor = .controlAccentColor
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        context.coordinator.value = $value
        if nsView.doubleValue != value {
            nsView.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func changed(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}
