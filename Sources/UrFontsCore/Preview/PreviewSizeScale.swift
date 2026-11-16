import Foundation

/// Maps a preview point size onto a 0...1 slider position with `center` at the
/// midpoint.
///
/// A linear slider over `12...108` puts the 42 pt default at 31% travel, so the
/// thumb reads as if the default were small. The two halves stay linear, which
/// keeps the midpoint exact and the response predictable: `12...42` uses the
/// lower half, `42...108` the upper half.
public struct PreviewSizeScale: Sendable {
    public static let standard = PreviewSizeScale(range: 12...108, center: 42)

    public let range: ClosedRange<Double>
    public let center: Double

    public init(range: ClosedRange<Double>, center: Double) {
        precondition(
            range.contains(center),
            "The slider midpoint must sit inside its range."
        )
        self.range = range
        self.center = center
    }

    public func position(for size: Double) -> Double {
        let clamped = min(max(size, range.lowerBound), range.upperBound)
        if clamped <= center {
            let span = center - range.lowerBound
            guard span > 0 else { return 0.5 }
            return 0.5 * (clamped - range.lowerBound) / span
        }
        let span = range.upperBound - center
        guard span > 0 else { return 1 }
        return 0.5 + 0.5 * (clamped - center) / span
    }

    /// The inverse position mapping, unrounded. Whole-point rounding belongs to
    /// the control, which is the only place that knows the size is displayed.
    public func size(for position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        if clamped <= 0.5 {
            return range.lowerBound
                + (clamped / 0.5) * (center - range.lowerBound)
        }
        return center
            + ((clamped - 0.5) / 0.5) * (range.upperBound - center)
    }
}
