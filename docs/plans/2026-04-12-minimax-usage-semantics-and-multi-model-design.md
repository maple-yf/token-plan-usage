# MiniMax Usage Semantics Fix & Multi-Model Display

## Problem

1. `currentIntervalUsageCount` in MiniMax API is **used count**, but code treats it as remaining count
2. API returns 11 model entries, only MiniMax-M* is displayed; rest are discarded

## Design

### 1. Fix usage_count semantics (MiniMaxProvider.swift)

```
Before: remainingCount = usageCount, usedCount = total - usageCount
After:  usedCount = usageCount, remainingCount = total - usageCount
```

### 2. Multi-model data model (UsageSnapshot.swift)

New struct `MiniMaxModelQuota`:
- `modelName: String`
- `usedCount: Int`
- `totalCount: Int`
- `remainingCount: Int`

New field on `UsageSnapshot`: `modelQuotas: [MiniMaxModelQuota]?` (nil for non-MiniMax providers)

### 3. Parse all models (MiniMaxProvider.swift)

Map every `modelRemains` entry to `MiniMaxModelQuota`. Sort: MiniMax-M* first, then by totalCount descending.

### 4. Display view (MiniMaxModelsView.swift)

Card per model, reusing MCPQuotaView style:
- Model name as header
- Progress bar (green >50%, orange ≤50%)
- 已用 / 剩余 / 总量 stats row

### 5. Integration (MonitorView.swift)

Show MiniMaxModelsView when `snapshot.modelQuotas` is non-nil, same position as MCPQuotaView.

## Files to modify

- `TokenPlanUsage/Services/Providers/MiniMaxProvider.swift` - fix semantics, parse all models
- `TokenPlanUsage/Models/UsageSnapshot.swift` - add MiniMaxModelQuota struct and modelQuotas field
- `TokenPlanUsage/Views/Monitor/MonitorView.swift` - integrate MiniMaxModelsView
- `TokenPlanUsageWidget/TokenPlanUsageWidget.swift` - update widget if needed
- New: `TokenPlanUsage/Views/Monitor/MiniMaxModelsView.swift` - multi-model display
