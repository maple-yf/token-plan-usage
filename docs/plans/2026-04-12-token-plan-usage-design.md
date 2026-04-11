# Token Plan Usage — iOS App Design Document

**Date:** 2026-04-12
**Status:** Approved
**Architecture:** MVVM, SwiftUI, iOS 17+

---

## 1. Overview

一款 iOS App，用于监控大模型 API Token 用量与剩余额度。纯本地工具，不走后端。

**前期支持 Provider：** MiniMax、GLM（智谱）

**参考：** MiniMax Token Plan Monitor（Mac 菜单栏应用），毛玻璃风格

---

## 2. Decisions

| 决策项 | 选择 |
|--------|------|
| 定位 | 纯本地工具，用户填 API Key，App 直调官方 API |
| UI 风格 | 毛玻璃（`.ultraThinMaterial`） |
| 技术栈 | SwiftUI 原生，iOS 17+ |
| 数据获取 | 默认官方 API + 可选自定义 Base URL |
| 用量图表 | 折线图（Swift Charts），可滑动选时间窗口 |
| 多 Provider 展示 | 顶部 Segment Control 切换 |
| 额外功能 | 桌面/锁屏 Widget |
| 架构方案 | 方案 A：精简 MVP，MVVM + 单 target |

---

## 3. App Structure

### 3.1 页面

**TabView** 两个 Tab：

1. **监控页（MonitorView）**
2. **设置页（SettingsView）**

### 3.2 监控页布局

```
┌─────────────────────────────┐
│  ProviderSegmentControl     │  ← .background(.ultraThinMaterial)
│  [MiniMax] [GLM]            │
├─────────────────────────────┤
│  RingProgressView           │  ← 自定义 Shape + animation
│  ┌───────┐                  │
│  │  ◯    │ MiniMax-M*       │
│  │ green │ 25 / 600 次      │
│  │  arc  │ 95% 剩余         │
│  └───────┘ 54:06 后刷新     │
├─────────────────────────────┤
│  UsageTrendChart            │  ← Swift Charts LinePlot
│  📈 折线图                  │     可滑动窗口 + 手势
│  ← 5h ━━━━━━━━━━ 5h →      │
├─────────────────────────────┤
│  UsageDetailView            │
│  已用次数  剩余次数  剩余时间  │  ← 3列 Grid
│    25      575     54:06    │
├─────────────────────────────┤
│  StatusBar                  │
│  ● API 正常  更新: 19:05   │
│        ↻ 手动刷新按钮        │  ← 点击立即拉取，刷新中 spinner
└─────────────────────────────┘
```

### 3.3 设置页布局

```
┌─────────────────────────────┐
│  Provider 配置列表            │
│  ┌─────────────────────────┐│
│  │ MiniMax           [开关] ││
│  │  API Key: sk-••••••••   ││  ← SecureField
│  │  Base URL: 官方默认 ▾    ││  ← 切换: 默认 / 自定义输入框
│  └─────────────────────────┘│
│  ┌─────────────────────────┐│
│  │ GLM               [开关] ││
│  │  API Key: •••••••••••   ││
│  │  Base URL: 官方默认 ▾    ││
│  └─────────────────────────┘│
│                             │
│  ┌─────────────────────────┐│
│  │ 刷新间隔                 ││
│  │ [5m] [10m] [15m] [手动] ││  ← Segment Control
│  └─────────────────────────┘│
│                             │
│  ┌─────────────────────────┐│
│  │ Widget 显示 Provider     ││
│  │ MiniMax ▾               ││  ← Picker
│  └─────────────────────────┘│
└─────────────────────────────┘
```

### 3.4 Widget

- **小部件**：Provider 名 + 百分比 + 环形小进度条
- **中部件**：加上已用/总量 + 剩余时间倒计时
- 通过 App Group 共享数据

---

## 4. Data Models

```swift
// Provider 配置
struct ProviderConfig: Codable {
    let id: String           // "minimax" | "glm"
    var apiKey: String
    var baseURL: String?     // nil = 使用官方默认地址
    var isEnabled: Bool
}

// 用量快照（API 返回后存储）
struct UsageSnapshot: Codable {
    let providerId: String
    let planName: String       // e.g. "MiniMax-M*"
    let usedCount: Int
    let totalCount: Int
    let remainingPercent: Double
    let refreshTime: Date?     // 额度重置时间
    let fetchedAt: Date        // 拉取时间戳
    let status: APIStatus      // .normal | .error(message)
}

enum APIStatus: Codable {
    case normal
    case error(String)
}

// 用量分布（折线图数据）
struct UsageDistribution: Codable {
    let providerId: String
    let windowStart: Date
    let windowEnd: Date
    let points: [UsagePoint]   // 每15分钟一个点
}

struct UsagePoint: Codable {
    let time: Date
    let count: Int
}
```

---

## 5. API Layer

```swift
protocol TokenProvider {
    var id: String { get }
    var defaultBaseURL: String { get }
    
    func fetchUsage(apiKey: String, baseURL: String?) async throws -> UsageSnapshot
    func fetchDistribution(apiKey: String, baseURL: String?) async throws -> UsageDistribution
}

class MiniMaxProvider: TokenProvider { ... }
class GLMProvider: TokenProvider { ... }
```

---

## 6. Storage

| 数据 | 存储位置 | 原因 |
|------|---------|------|
| ProviderConfig（含 API Key） | Keychain | 安全性 |
| UsageSnapshot / UsageDistribution | App Group UserDefaults | Widget 可读 |
| 偏好设置（刷新间隔等） | UserDefaults | 非敏感 |

**App Group ID:** `group.com.yourtoken.tokenplan`

---

## 7. Visual Design

### 7.1 主题

- 背景：`Material.ultraThinMaterial`
- 主色：系统 `Color.accentColor`
- 跟随系统明暗模式

### 7.2 状态色

| 状态 | 颜色 | 触发条件 |
|------|------|---------|
| 正常 | 🟢 green | 剩余 > 30% |
| 警告 | 🟡 orange | 剩余 10%-30% |
| 超限 | 🔴 red | 剩余 < 10% 或已用完 |

### 7.3 动画

- 环形进度：`animation(.easeInOut, value: percent)` 首次加载填充动画
- Provider 切换：`transition(.opacity)` 淡入淡出
- API 状态变化：小圆点颜色渐变
- 手动刷新：按钮 → spinner → 完成后 haptic 轻反馈

---

## 8. Error Handling

### 8.1 网络层

- 所有 API 调用 `async/await`，外层 `do/catch`
- 超时 15 秒
- 失败自动重试 1 次（间隔 3 秒），仍失败则显示错误状态

### 8.2 错误展示

| 场景 | UI 表现 |
|------|---------|
| 无网络 | 🔴 网络不可用 + 显示缓存数据（灰显 + 标注时间） |
| API Key 无效 | 🔴 认证失败 + 弹出提示引导去设置页 |
| 服务端错误 (5xx) | 🔴 服务暂不可用 + 按刷新间隔自动重试 |
| 额度为 0 | 环形进度变红 + 数字高亮警告 |
| 未配置 Provider | 引导卡片 "请先在设置中配置 API Key" |

### 8.3 边界处理

- 首次启动无缓存 → 骨架屏（Skeleton），立即触发首次拉取
- API Key 输入时去除前后空格
- Base URL 校验（必须 `https://` 开头）
- 倒计时到 0 时自动触发刷新
- App 进入前台时触发刷新（`didBecomeActive`）

### 8.4 数据过期

- Widget 数据 > 30 分钟 → 黄色警告 "数据可能已过期"
- 缓存数据 > 24 小时 → 红色 "请打开 App 刷新"

---

## 9. Testing Strategy

### 9.1 单元测试（XCTest）

| 测试目标 | 内容 |
|---------|------|
| `MiniMaxProvider` | mock URLProtocol 测试 fetchUsage 解析正确/错误响应 |
| `GLMProvider` | 同上 |
| `UsageSnapshot` | JSON 编解码 round-trip |
| `ProviderConfig` | Keychain 存取 |
| 倒计时计算 | 剩余时间计算逻辑 |

### 9.2 UI 测试

- 首次启动 → 引导卡片可见
- 设置页填入 Key → 保存 → 切回监控页 → 数据展示
- Segment 切换 Provider → 数据对应切换

### 9.3 Widget 测试

- Preview 验证三种尺寸渲染
- App Group 数据读写正确

### 9.4 不测试

- SwiftUI 声明式布局本身
- 系统毛玻璃效果
- Swift Charts 内部渲染

---

## 10. Scope Boundaries (v1 NOT doing)

- ❌ 后端服务 / 用户账号系统
- ❌ 推送通知
- ❌ 多语言（v1 仅中文）
- ❌ iPad 适配（v1 仅 iPhone）
- ❌ 更多 Provider（后续迭代加）
