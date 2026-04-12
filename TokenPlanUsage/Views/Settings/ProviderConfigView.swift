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
                    Text(config.id == "minimax" ? "MiniMax API" : "智谱 GLM API")
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
            }
        }
        .onChange(of: config.apiKey) { _, _ in
            try? KeychainService.shared.save(config)
        }
        .onChange(of: config.isEnabled) { _, _ in
            try? KeychainService.shared.save(config)
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
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    @Previewable @State var config = ProviderConfig(
        id: "minimax", apiKey: "sk-test-key-12345", baseURL: nil, isEnabled: true
    )
    ProviderConfigView(config: $config)
        .padding()
        .background(.blue.opacity(0.3))
}
