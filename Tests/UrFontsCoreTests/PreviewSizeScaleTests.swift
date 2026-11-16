import Testing
@testable import UrFontsCore

struct PreviewSizeScaleTests {
    private let scale = PreviewSizeScale.standard

    @Test("the default size sits at the slider midpoint")
    func centerIsMidpoint() {
        #expect(scale.position(for: 42) == 0.5)
        #expect(scale.size(for: 0.5) == 42)
    }

    @Test("range ends map to the slider ends")
    func ends() {
        #expect(scale.position(for: 12) == 0)
        #expect(scale.position(for: 108) == 1)
        #expect(scale.size(for: 0) == 12)
        #expect(scale.size(for: 1) == 108)
    }

    @Test("the mapping is monotonic and round-trips whole sizes")
    func roundTrip() {
        for size in stride(from: 12.0, through: 108.0, by: 1.0) {
            let position = scale.position(for: size)
            #expect(scale.size(for: position).rounded() == size)
            if size < 108 {
                #expect(scale.position(for: size + 1) > position)
            }
        }
    }

    @Test("out-of-range input is clamped")
    func clamps() {
        #expect(scale.position(for: -20) == 0)
        #expect(scale.position(for: 500) == 1)
        #expect(scale.size(for: -1) == 12)
        #expect(scale.size(for: 2) == 108)
    }
}
