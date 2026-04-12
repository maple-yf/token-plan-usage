import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MonitorView()
                    .navigationTitle("Token Usage")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("监控", systemImage: "gauge.with.dots.needle.67percent")
            }
            .tag(0)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
            .tag(1)
        }
    }
}

#Preview {
    MainTabView()
}
