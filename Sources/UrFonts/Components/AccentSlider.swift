import AppKit
import SwiftUI
import UrFontsCore

/// A native slider with an explicit accent fill.
///
/// SwiftUI's `Slider` renders untinted inside a macOS 26/27 toolbar even when
/// `.tint` is set. The preview size control lives in the status bar today; this
/// wrapper keeps the accent explicit so moving it back into a toolbar cannot
/// silently turn it gray.
///
/// When `center` is set, that user value sits at the visual midpoint so the
/// default does not look like the low end of the range. The slider still speaks
/// in user units: mapping back and forth, whole-point rounding and clamping all
/// live here.
struct AccentSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var center: Double?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSlider {
        context.coordinator.configure(value: $value, range: range, center: center)
        let slider = NSSlider(
            value: context.coordinator.position(for: value),
            minValue: 0,
            maxValue: 1,
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
        context.coordinator.configure(value: $value, range: range, center: center)
        let target = context.coordinator.position(for: value)
        if nsView.doubleValue != target {
            nsView.doubleValue = target
        }
    }

    final class Coordinator: NSObject {
        private var value: Binding<Double>?
        private var range: ClosedRange<Double> = 0...1
        private var scale: PreviewSizeScale?

        func configure(
            value: Binding<Double>,
            range: ClosedRange<Double>,
            center: Double?
        ) {
            self.value = value
            self.range = range
            self.scale = center.map { PreviewSizeScale(range: range, center: $0) }
        }

        func position(for size: Double) -> Double {
            if let scale {
                return scale.position(for: size)
            }
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return 0 }
            return (size - range.lowerBound) / span
        }

        private func size(for position: Double) -> Double {
            if let scale {
                return scale.size(for: position)
            }
            return range.lowerBound + position * (range.upperBound - range.lowerBound)
        }

        @objc func changed(_ sender: NSSlider) {
            // Whole-point sizes only: the label already shows an integer, and
            // fractional sizes produce inconsistent metrics between ticks.
            let mapped = size(for: sender.doubleValue)
            let rounded = min(
                max(mapped.rounded(), range.lowerBound),
                range.upperBound
            )
            sender.doubleValue = position(for: rounded)
            value?.wrappedValue = rounded
        }
    }
}
