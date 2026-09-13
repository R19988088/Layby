import SwiftUI

/// Only the capsule surface remains; the window owns its persistent drag handle.
struct ShelfCapsuleView: View {
    @Bindable var store: ShelfStore

    var body: some View {
        ShelfGlassChrome(cornerRadius: ShelfLayout.capsuleCornerRadius)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ShelfDropBorder(isTargeted: store.isDropTargeted, cornerRadius: ShelfLayout.capsuleCornerRadius)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
