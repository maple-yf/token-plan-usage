import SwiftUI

struct ProviderConfigView: View {
    @Binding var config: ProviderConfig
    @State private var showAPIKey = false
    @State private var useCustomBaseURL = false
    @State private var customBaseURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.id.uppercased())
                        .font(.headline)
                    Text(providerDescription(config.id))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $config.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if config.isEnabled {
                Divider()
                    .background(.white.opacity(0.2))

                // API Key field
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        if showAPIKey {
                            TextField("sk-...", text: $config.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.subheadline, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $config.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Base URL picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $useCustomBaseURL) {
                        Text("官方默认").tag(false)
                        Text("自定义").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useCustomBaseURL {
                        TextField("https://...", text: $customBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                }

                // Platform token/cookie (DeepSeek only)
                if config.id == "deepseek" {
                    Divider()
                        .background(.white.opacity(0.2))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Platform Token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            if showAPIKey {
                                TextField("从 platform.deepseek.com 获取", text: Binding(
                                    get: { config.platformToken ?? "" },
                                    set: { config.platformToken = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.subheadline, design: .monospaced))
                            } else {
                                SecureField("从 platform.deepseek.com 获取", text: Binding(
                                    get: { config.platformToken ?? "" },
                                    set: { config.platformToken = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.subheadline, design: .monospaced))
                            }
                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("登录 platform.deepseek.com，从浏览器开发者工具中获取 Token")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Platform Cookie（可选）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("可选，辅助认证", text: Binding(
                            get: { config.platformCookie ?? "" },
                            set: { config.platformCookie = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.subheadline, design: .monospaced))
                    }
                }
            }
        }
        .onChange(of: config.apiKey) { _, _ in
            try? KeychainService.shared.save(config)
        }
        .onChange(of: config.isEnabled) { _, isEnabled in
            try? KeychainService.shared.save(config)
            SharedStore.shared.toggleProviderVisibility(config.id)
        }
        .onChange(of: config.baseURL) { _, _ in
            try? KeychainService.shared.save(config)
        }
        .onChange(of: useCustomBaseURL) { _, isCustom in
            if !isCustom {
                config.baseURL = nil
            }
        }
        .onChange(of: customBaseURL) { _, newValue in
            if useCustomBaseURL {
                config.baseURL = newValue.isEmpty ? nil : newValue
            }
        }
        .onChange(of: config.platformToken) { _, _ in
            try? KeychainService.shared.save(config)
        }
        .onChange(of: config.platformCookie) { _, _ in
            try? KeychainService.shared.save(config)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func providerDescription(_ id: String) -> String {
        switch id {
        case "minimax": return "MiniMax API"
        case "glm": return "智谱 GLM API"
        case "deepseek": return "DeepSeek API"
        default: return id.uppercased()
        }
    }
}

#Preview {
    @Previewable @State var config = ProviderConfig(
        id: "deepseek", apiKey: "sk-test-key-12345", baseURL: nil, isEnabled: true
    )
    ProviderConfigView(config: $config)
        .padding()
        .background(.blue.opacity(0.3))
}
