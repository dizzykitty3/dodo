import SwiftUI

/// A consistent icon column for list cards and list management rows.
struct ListSymbol: View {
    let name: String
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 32

    var body: some View {
        Image(systemName: name)
            .frame(width: size, height: size, alignment: .center)
    }
}
