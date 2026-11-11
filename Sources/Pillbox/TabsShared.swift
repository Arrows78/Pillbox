import AppKit
import Foundation
import SwiftUI

let card = Design.card

extension View {
    /// Keeps the island open while one of its text fields has focus.
    @MainActor func keepsIslandOpen(while focused: Bool, in model: NotchModel) -> some View {
        onChange(of: focused) { model.pinnedOpen = $0 }
    }
}
