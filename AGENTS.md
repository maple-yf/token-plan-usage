# AGENTS.md

本文件用于向 AI 编码助手（以及新加入的开发者）说明本仓库的关键约定，帮助其正确、安全地参与开发。

## 项目概述

Token Plan Usage 是一款 iOS App，用于监控 AI 服务提供商（MiniMax、智谱 GLM、DeepSeek）的 API 额度用量。技术栈为 Swift / SwiftUI（iOS 17+），使用 XcodeGen（`project.yml`）生成 Xcode 工程，并包含 WidgetKit 桌面小组件。

详见 [README.md](README.md)。

## 测试数据：`.testData`（重要）

仓库根目录下的 **`.testData`** 文件存放用于**测试与本地调试的关键凭据**，包括各 Provider 的真实可用 API key、Platform Token、Cookie 等敏感信息。

### 用途
- 在本地运行 App 或运行测试时，可直接读取该文件中的凭据，免去手工配置。
- 用于验证各 Provider 接口请求 / 响应解析逻辑、UI 渲染、Widget 展示等。

### 安全约定（务必遵守）
- ⚠️ **该文件包含真实可用的密钥，属于敏感数据。**
- **已被 `.gitignore` 忽略，严禁提交到 Git 仓库**，也不要将其内容复制粘贴到任何会被提交或外发的地方（代码、注释、文档、Issue、聊天记录等）。
- 在代码或文档中引用示例时，请使用脱敏的占位符（如 `sk-xxxxxxxx`），不要使用文件中的真实值。
- 在日志、截图、错误信息中同样避免输出其中的密钥。

### 文件格式约定
文件为纯文本，按「平台名 + 字段名 + 值」的方式罗列，例如：

```
# 平台注释
平台名 字段名 = "值"
```

涉及的平台与字段示例：
- **MiniMax**：API key
- **GLM（智谱）**：API key
- **DeepSeek**：API key、Platform Token、Platform Cookie

如需新增 Provider 的测试凭据，请沿用上述格式追加到文件末尾，并保持 `.gitignore` 对该文件的忽略规则不变。

## 其他开发约定

- 工程文件由 `project.yml` 经 XcodeGen 生成，修改源文件组织结构后请运行 `xcodegen generate` 重新生成 `.xcodeproj`。
- API Key 在 App 中通过 **Keychain** 安全存储，切勿改用明文持久化（如 `UserDefaults`）。
- 各 Provider 的网络与解析逻辑请配合测试覆盖（参见 `TokenPlanUsageTests`）。

## 提交前凭据安全检查（必做）

> ⚠️ **每次 `git commit` 之前必须运行 `scripts/security-check.sh`**。脚本会扫描 staged diff 与 git 历史中的常见凭据模式，验证 `.gitignore` 覆盖了已知敏感文件类型。

### 快速流程

```bash
# 1. stage 待提交的内容
git add <files>

# 2. 运行检查（只扫 staged diff，CI 友好）
./scripts/security-check.sh --staged-only

# 3. 通过后再 commit
git commit -m "..."
```

### 检查内容（三层防御）

1. **`.gitignore` 覆盖验证** — 必须包含：`.testData`、`.env` / `.env.*`、`*.pem` / `*.key` / `*.p12` / `*.cer`、`secrets/`、`credentials/`。
2. **Staged diff 模式扫描** — 在 `+` 行上正则匹配：
   - `sk-[a-zA-Z0-9_-]{20,}`（OpenAI / DeepSeek / Anthropic 等常见 key 前缀）
   - `Bearer [token]`（HTTP 鉴权头）
   - `[A-Za-z0-9+/]{40,}={0,2}`（Base64 风格长字符串，捕获 DeepSeek Platform Token）
   - `smidV2=[0-9a-fA-F]{16,}`（DeepSeek 平台 Cookie）
   - `[0-9a-f]{32}\.[A-Za-z0-9]{16,}`（智谱 GLM key）
   - 通用 `(password|secret|api_key|apiKey|API_KEY|token)\s*[:=]\s*["'][^"']{8,}`（仅提示，人工 review）
3. **Git 历史全量扫描** — 遍历 `git log --all -p` 的 `+` 行，确认历史上没有漏网之鱼。

### 占位符（不会被报警）

代码、文档、注释中引用示例 key 时，必须使用以下占位符之一（脚本会跳过）：

- `sk-xxxxxxxx`
- `REPLACE_ME`
- `<API_KEY>`
- `PLACEHOLDER`

### 失败处理

- **`.gitignore` 缺失条目** → 补全后重跑。
- **staged diff 命中模式** → 移除真实凭据，替换为占位符，再次 stage。
- **历史命中模式** → 立即使用 `git filter-branch` 或 [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/) 清理，**然后强制推送 `git push --force`** 并通知所有协作者 rebase。
- **误报**（如代码里写的示例）→ 把真实字符串替换为占位符再 stage。

### 脚本的 `--strict` 模式

CI 流水线或 pre-commit hook 可用：

```bash
./scripts/security-check.sh --strict   # 发现任何问题立即 exit 1，不走人工 review
```
