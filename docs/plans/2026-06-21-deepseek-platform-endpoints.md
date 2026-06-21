# DeepSeek Platform Usage Endpoints

> 描述 DeepSeek 平台用量的两个端点、字段语义、合并策略及单元测试要点。
> 最近一次抓取：2026-06-21（基于真实凭据与响应验证）。

---

## 1. 端点概览

DeepSeek 平台用量需要**同时**调用两个端点才能完整展示给用户：

| 端点 | 用途 | 量纲 |
|---|---|---|
| `/api/v0/usage/cost` | 各 token 类型对应的**消费金额** | `currency`（默认 CNY） |
| `/api/v0/usage/amount` | 实际的 **token 计数** 与 **API 请求次数** | 整数 |

两个端点同源同结构，但 `amount` 字段的语义完全不同：
- `/cost`：`amount` 是**浮点** CNY 金额（`"0.688928"`）
- `/amount`：`amount` 是**整数字符串** token 数（`"27557120"`）

`REQUEST` 字段在 `/cost` 里恒为 `0`（按金额计费的接口不返回次数），必须在 `/amount` 里拿真实请求数。

---

## 2. 请求方式

两个端点共享相同的鉴权与查询参数：

```
GET https://platform.deepseek.com/api/v0/usage/cost?month={month}&year={year}
GET https://platform.deepseek.com/api/v0/usage/amount?month={month}&year={year}
```

**请求头：**

| 头部 | 值 | 必需 |
|---|---|---|
| `Authorization` | `Bearer <Platform Token>` | ✅ |
| `Accept` | `application/json` | 推荐 |
| `User-Agent` | `Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15` | 推荐（部分边缘环境下被 WAF 拦截） |
| `Cookie` | `<Platform Cookie>` | 部分账号必需 |

**凭据来源：** Keychain 中的 `ProviderConfig.platformToken` / `platformCookie`。
普通 `/user/balance` 用的 `apiKey` **不能**访问这两个端点。

---

## 3. 响应结构

### 3.1 `/usage/cost` 响应

```json
{
  "code": 0,
  "msg": "success",
  "data": {
    "biz_code": 0,
    "biz_data": [
      {
        "currency": "CNY",
        "days": [
          {
            "date": "2026-06-13",
            "data": [
              {
                "model": "deepseek-v4-pro",
                "usage": [
                  { "type": "PROMPT_TOKEN", "amount": "0" },
                  { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "0.688928" },
                  { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "1.532319" },
                  { "type": "RESPONSE_TOKEN", "amount": "0.542766" },
                  { "type": "REQUEST", "amount": "0" }
                ]
              }
            ]
          }
        ],
        "total": [ { "model": "deepseek-v4-pro", "usage": [...] } ]
      }
    ]
  }
}
```

⚠️ `biz_data` 是**数组**（外层包了一层），含 `currency` 字段。

### 3.2 `/usage/amount` 响应

```json
{
  "code": 0,
  "msg": "",
  "data": {
    "biz_code": 0,
    "biz_msg": "",
    "biz_data": {
      "days": [
        {
          "date": "2026-06-13",
          "data": [
            {
              "model": "deepseek-v4-pro",
              "usage": [
                { "type": "PROMPT_CACHE_HIT_TOKEN", "amount": "27557120" },
                { "type": "PROMPT_CACHE_MISS_TOKEN", "amount": "510773" },
                { "type": "RESPONSE_TOKEN", "amount": "90461" },
                { "type": "REQUEST", "amount": "196" }
              ]
            }
          ]
        }
      ],
      "total": [ { "model": "deepseek-v4-pro", "usage": [...] } ]
    }
  }
}
```

⚠️ `biz_data` 是**对象**（不再有外层数组），**没有** `currency` 字段。

### 3.3 字段语义

| `type` | 含义 |
|---|---|
| `PROMPT_TOKEN` | 走单独 prompt 计费通道的 token（目前为 0） |
| `PROMPT_CACHE_HIT_TOKEN` | 命中缓存的输入 token |
| `PROMPT_CACHE_MISS_TOKEN` | 未命中缓存的输入 token |
| `RESPONSE_TOKEN` | 模型输出 token |
| `REQUEST` | API 请求次数（**只在 `/amount` 里非零**） |

`amount` 在 `/cost` 是 CNY 浮点字符串，在 `/amount` 是 token 整数字符串。两端都返回 `unit` 字段，但**实际都为 `null`**，单位靠端点语义推断。

---

## 4. 合并策略

`DeepSeekProvider.fetchPlatformUsage(month:year:)` 用 `async let` 并发拉两个端点，
然后用 `(date, modelName)` 作为复合键做 join，合并为单一 `DeepSeekPlatformUsage`：

- **Cost 字段**（`*Cost` 后缀）← 来自 `/usage/cost`
- **Token/Request 字段**（`*Tokens` / `requestCount`）← 来自 `/usage/amount`

**容错：**
- 任一端点失败 → 仍返回结果，仅缺失的字段为 `0`
- 仅当两端点都失败 → `throw TokenProviderError.invalidResponse`（或对应的 HTTP 错误）

**只在 amount 端点出现的模型：** 自动追加到 `modelTotals`，cost 字段填 0。
**只在 cost 端点出现的日期/模型：** 同样保留，token 字段填 0。

### 4.1 关键代码路径

```
DeepSeekProvider.fetchPlatformUsage
  ├── async fetchPlatformCost  → DeepSeekPlatformCostResponse
  ├── async fetchPlatformAmount → DeepSeekPlatformAmountResponse
  └── 合并:
       - 按 date 索引 dailyUsage
       - 按 (date, model) 索引 modelBreakdown
       - 按 model 索引 modelTotals
```

`fetchDistribution(timeRange:)` 改用 `/usage/amount`（不再用 `/usage/cost`），
因为趋势图要展示真实 token 数（cost 数值在同一量级无意义）。

---

## 5. 单元测试

`TokenPlanUsageTests/Services/DeepSeekProviderTests.swift` 覆盖：

1. **`testFetchPlatformUsageParsesCostOnly`** — 仅 `/usage/cost` 可达，token 字段全 0
2. **`testFetchPlatformUsageParsesAmountOnly`** — 仅 `/usage/amount` 可达，cost 字段全 0
3. **`testFetchPlatformUsageMergesCostAndAmount`** — 双端点都可达，验证合并后同日/同模型 BOTH 字段都有值
4. **`testFetchPlatformUsageThrowsWhenBothEndpointsFail`** — 双端点都失败

测试用 `MockURLProtocol.requestHandler` 按 URL 路径返回不同的 fixture body，
fixture 数值与抓取的真实响应一致（`amount` 字段值直接抄自真实 JSON）。

---

## 6. UI 显示映射

| 数据 | 显示位置 | 格式化 |
|---|---|---|
| `balance.totalBalance` | "充值余额"（summary card） | `CNY 44.92` |
| `usage.totalConsumption` | "本月消费"（summary card） | `CNY 4.04` |
| `usage.totalTokens` | "总 Tokens"（summary card） | `29.6M`（K/M/G/T） |
| `usage.totalRequests` | "总请求数"（summary card） | `249` |
| 每日 `totalCost` | "消费金额" 柱状图 | Y 轴 `¥0.5 / ¥1.0` |
| 每日 `requestCount` | "API 请求次数" 折线/面积图 | Y 轴 `100 / 200` |
| 每日 `promptCacheHitTokens` / `promptCacheMissTokens` / `responseTokens` | "Tokens 分布" 堆叠柱状图 | Y 轴 `10M / 20M` |
| 模型级 `*Cost` / `*Tokens` / `requestCount` | "模型详情" 卡片 | 数字 + 颜色编码 |
| 模型合计 | "Tokens 细分" 卡片 | 命中/未命中/输出 token 计数 |

---

## 7. 已知陷阱

1. **不要把 `/cost` 的 `amount` 当 token 数显示** —— 用户最先反馈的 bug 就是这个。
2. **`/amount` 的 `biz_data` 不是数组** —— 与 `/cost` 形状不一致，单独定义 `DeepSeekPlatformAmountData` 而非复用。
3. **`PROMPT_TOKEN` 在两个端点都恒为 0** —— 仍要保留字段以防接口未来变化。
4. **`REQUEST` 只在 `/amount` 出现非零** —— `/cost` 里恒为 0（按金额计费）。
5. **User-Agent** —— 漏掉时偶尔被 WAF 拦截返回 4xx，建议保留。
6. **不要把 `unit` 字段当真** —— 实际响应里 `unit: null`，单位需自行推断。
