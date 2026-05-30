import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: SyntaxAppModel

    var body: some View {
        NavigationSplitView {
            AppSidebar(
                selectedRoute: appModel.selectedSidebarRoute,
                onSelectRoute: appModel.handleSidebarSelection
            )
        } detail: {
            DashboardShellView()
                .environmentObject(appModel)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1180, minHeight: 760)
        .task {
            appModel.startIfNeeded()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SyntaxAppModel())
}
