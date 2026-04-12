import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var selectedRefreshInterval: TimeInterval = 300
    @State private var selectedWidgetProvider = "minimax"

    private let refreshOptions: [(String, TimeInterval)] = [
        ("5分钟", 300),
        ("10分钟", 600),
        ("15分钟", 900),
        ("手动", 0)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Provider configs
                ForEach($viewModel.providers) { $config in
                    ProviderConfigView(config: $config)
                }

                // Refresh interval
                VStack(alignment: .leading, spacing: 8) {
                    Text("刷新间隔")
                        .font(.subheadline.weight(.semibold))

                    Picker("", selection: $selectedRefreshInterval) {
                        ForEach(refreshOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                // Widget provider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Widget 显示 Provider")
                        .font(.subheadline.weight(.semibold))

                    Picker("Provider", selection: $selectedWidgetProvider) {
                        ForEach(viewModel.providers.filter { $0.isEnabled }) { provider in
                            Text(provider.id.uppercased()).tag(provider.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                // App info
                VStack(spacing: 4) {
                    Text("Token Plan Usage")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("v1.0.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("设置")
        .onChange(of: viewModel.providers) { _, newProviders in
            for config in newProviders {
                try? viewModel.updateProvider(config)
            }
        }
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
