import SwiftUI

extension View {
    /// SwiftUI sheets prevent app termination by default. Opt out so Cmd+Q
    /// works while a sheet is open. The modifier is macOS 15.4+; older systems
    /// keep the default behavior.
    @ViewBuilder
    func allowsAppTermination() -> some View {
        if #available(macOS 15.4, *) {
            presentationPreventsAppTermination(false)
        } else {
            self
        }
    }
}
