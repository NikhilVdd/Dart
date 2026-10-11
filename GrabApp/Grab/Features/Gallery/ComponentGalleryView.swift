import SwiftUI

struct ComponentGalleryView: View {
    @State private var mode: HomeMode = .request

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreviewPill(text: "DEVELOPMENT ONLY")
                Text("Component gallery").font(.largeTitle.bold())
                SlidingSegmentedControl(selection: $mode)
                HStack { StatusChip(status: .waiting); StatusChip(status: .completed) }
                AvatarStack(initials: ["MC", "JL", "DP"])
                GrabItemCard(item: PreviewData.charger)
                PrimaryButtonLabel(title: "Primary action", icon: "arrow.right")
                SecondaryButtonLabel(title: "Secondary action", icon: "plus")
                ContentStateCard(state: .loading)
                ContentStateCard(state: .empty)
                ContentStateCard(state: .error)
            }
            .padding(GrabTheme.pageInset)
        }
        .background(GrabBackdrop())
        .navigationTitle("Gallery")
    }
}

struct ComponentGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { ComponentGalleryView() }
    }
}
