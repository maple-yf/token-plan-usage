# Token Plan Usage

一款 iOS App，用于监控 AI 服务提供商的 API 额度用量。支持 **MiniMax** 和 **智谱 GLM** 两个平台，实时展示用量、剩余额度、MCP 工具配额和用量趋势。

## 预览

<table>
  <tr>
    <td><img src="Simulator%20Screenshot%20-%20iPhone%2016%20-%202026-04-12%20at%2021.24.30.png" width="300" alt="GLM 用量监控" /></td>
    <td><img src="Simulator%20Screenshot%20-%20iPhone%2016%20-%202026-04-12%20at%2021.24.51.png" width="300" alt="GLM 用量趋势" /></td>
  </tr>
  <tr>
    <td align="center">GLM 监控 — 环形进度 + MCP 配额</td>
    <td align="center">GLM 监控 — 用量趋势图表</td>
  </tr>
  <tr>
    <td><img src="Simulator%20Screenshot%20-%20iPhone%2016%20-%202026-04-12%20at%2021.25.17.png" width="300" alt="MiniMax 用量监控" /></td>
    <td><img src="Simulator%20Screenshot%20-%20iPhone%2016%20-%202026-04-12%20at%2021.25.08.png" width="300" alt="设置页面" /></td>
  </tr>
  <tr>
    <td align="center">MiniMax 监控 — 多模型用量明细</td>
    <td align="center">设置 — API Key 与刷新配置</td>
  </tr>
</table>

## 功能

- **多 Provider 支持** — MiniMax、智谱 GLM，顶部 Segment 切换
- **环形进度可视化** — 直观展示额度剩余百分比、已用量、剩余时间
- **MCP 工具配额** — GLM 专属 MCP 工具调用次数跟踪
- **多模型用量明细** — MiniMax 各子模型独立计数（speech-hd、MiniMax-M\*、coding-plan-vim 等）
- **用量趋势图表** — 历史用量折线图，直观掌握消耗节奏
- **iOS 桌面小组件** — Widget 显示选定 Provider 的额度概览
- **安全存储** — API Key 通过 Keychain 安全存储
- **自动刷新** — 支持 5/10/15 分钟间隔或手动刷新

## 技术栈

- Swift / SwiftUI
- iOS 17+
- XcodeGen（`project.yml` 生成 Xcode 工程）
- WidgetKit
- Keychain Services

## 构建

```bash
# 安装 XcodeGen（如未安装）
brew install xcodegen

# 生成 Xcode 工程
xcodegen generate

# 打开工程
open TokenPlanUsage.xcodeproj
```

在 Xcode 中选择模拟器或真机，Build & Run 即可。

## 许可证

[MIT](LICENSE)
