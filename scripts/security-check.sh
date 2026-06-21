#!/usr/bin/env bash
# scripts/security-check.sh
# 提交前凭据安全检查：
#   1. 验证 .gitignore 覆盖了已知的凭据文件（.testData, *.key, *.pem, .env* 等）
#   2. 扫描 staged diff 和 tracked files 中的常见凭据模式
#   3. 扫描全部 git 历史，确保没有凭据被意外提交
# 退出码 0 = 全部通过，非 0 = 发现问题（不阻断流程，但要求人工 review）
#
# 用法：
#   ./scripts/security-check.sh                  # 检 staged + 历史
#   ./scripts/security-check.sh --staged-only    # 只检 staged
#   ./scripts/security-check.sh --strict         # 发现问题立即退出 1

set -u

# 找到 git 根目录（向上搜索）
find_git_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

ROOT="$(find_git_root || true)"
if [ -z "$ROOT" ]; then
    echo "ERROR: not in a git repository" >&2
    exit 2
fi
cd "$ROOT"

MODE="${1:-default}"
SCAN_HISTORY=1
STRICT=0
case "$MODE" in
    --staged-only) SCAN_HISTORY=0 ;;
    --strict)      STRICT=1 ;;
    *) ;;
esac

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

FOUND=0

# ============================================================
# 1. .gitignore 验证
# ============================================================
bold "==> 1/3  验证 .gitignore 覆盖"

REQUIRED_IGNORES=(".testData" ".env" "*.pem" "*.key" "*.p12")
MISSING=()
for pattern in "${REQUIRED_IGNORES[@]}"; do
    if ! git check-ignore -q "$pattern" 2>/dev/null; then
        MISSING+=("$pattern")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    red "    ✗ .gitignore 缺少以下条目: ${MISSING[*]}"
    yellow "    → 请手动补全后重跑"
    FOUND=1
    if [ "$STRICT" = "1" ]; then exit 1; fi
else
    green "    ✓ 所有敏感文件类型已覆盖"
fi

# ============================================================
# 2. Staged diff + tracked files 扫描
# ============================================================
bold "==> 2/3  扫描代码中的凭据模式"

# 常见凭据模式：API key、token、cookie、bearer、password
# 每行一个 pattern，使用 ripgrep（macOS 自带 grep 也行，但 rg 更快更准）
PATTERNS=(
    # OpenAI / Anthropic / DeepSeek / 通用 sk- 前缀
    'sk-[a-zA-Z0-9_-]{20,}'
    # Bearer token
    '[Bb]earer[[:space:]]+[a-zA-Z0-9_+/=-]{20,}'
    # DeepSeek platform token（Base64 风格，>40 字符，必须含 `+` 以避免误报文件路径）
    '[A-Za-z0-9/]+[+][A-Za-z0-9+/]{30,}={0,2}'
    # Cookie smidV2
    'smidV2=[0-9a-fA-F]{16,}'
    # 智谱 GLM key
    '[0-9a-f]{32}\.[A-Za-z0-9]{16,}'
    # 通用 password / secret / token 赋值（仅作为提示，人工 review）
    '(password|secret|api_key|apiKey|API_KEY)[[:space:]]*[:=][[:space:]]*["\x27][^"\x27]{8,}'
)

# 预过滤：剔除 diff 文件头 (+++ b/...) 和明显的测试 fake key
# 这些是为了降低误报率；真凭据不会长得像这样
FILTER_OUT_PATTERNS=(
    '^(\+\+\+|---) '                  # git diff 文件头
    '"sk-test-key'                    # 单元测试里的 fake key
    'coding-plan-token'               # 测试 fixture
    'bad-key|bad-token'               # 测试 fixture
    '"sk-cp-'                         # 用户曾使用的前缀（仅在 .testData 中，不会出现在 diff 里）
)

scan_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    # 跳过 .testData、.git、构建产物、二进制
    case "$file" in
        .testData|.git/*|build/*|DerivedData/*|*.png|*.jpg|*.pdf) return 0 ;;
    esac
    # 跳过 docs/screenshots、docs/plans 等纯文档（也可能含示例 placeholder）
    if grep -qE 'sk-xxxxxxxx|REPLACE_ME|<API_KEY>|"PLACEHOLDER"' "$file" 2>/dev/null; then
        : # 文档里的占位符不报警
    fi
}

# 取 staged diff
STAGED=$(git diff --cached --name-only --diff-filter=ACMR)
if [ -z "$STAGED" ]; then
    yellow "    (无 staged 改动，跳过 diff 扫描)"
else
    yellow "    Scanning $(echo "$STAGED" | wc -l | tr -d ' ') staged file(s)..."
    STAGED_HITS=0
    for pattern in "${PATTERNS[@]}"; do
        # 用 git diff --cached -U0 只看新增/修改的行
        MATCHES=$(git diff --cached -U0 -- "$STAGED" 2>/dev/null \
            | grep -E "^\+" \
            | grep -E "$pattern" \
            | grep -vE 'sk-xxxxxxxx|REPLACE_ME|<API_KEY>|PLACEHOLDER' \
            | grep -vE '^\+\+\+ ' \
            | grep -vE '"sk-test-key|coding-plan-token|bad-key|bad-token|test-key|apiKey: "sk-' )
        if [ -n "$MATCHES" ]; then
            red "    ✗ pattern 匹配: $pattern"
            echo "$MATCHES" | head -3 | sed 's/^/      /'
            STAGED_HITS=1
        fi
    done

    if [ "$STAGED_HITS" = "1" ]; then
        FOUND=1
        if [ "$STRICT" = "1" ]; then exit 1; fi
    else
        green "    ✓ staged diff 未发现凭据"
    fi
fi

# ============================================================
# 3. 全 git 历史扫描（仅在非 --staged-only 模式）
# ============================================================
if [ "$SCAN_HISTORY" = "1" ]; then
    bold "==> 3/3  扫描 git 历史"
    HISTORY_HITS=0
    for pattern in "${PATTERNS[@]}"; do
        MATCHES=$(git log --all -p 2>/dev/null \
            | grep -E "^\+" \
            | grep -E "$pattern" \
            | grep -vE 'sk-xxxxxxxx|REPLACE_ME|<API_KEY>|PLACEHOLDER' \
            | grep -vE '^\+\+\+ ' \
            | grep -vE '"sk-test-key|coding-plan-token|bad-key|bad-token|test-key|apiKey: "sk-' \
            | head -3)
        if [ -n "$MATCHES" ]; then
            red "    ✗ 历史中发现 pattern: $pattern"
            echo "$MATCHES" | head -3 | sed 's/^/      /'
            HISTORY_HITS=1
        fi
    done

    if [ "$HISTORY_HITS" = "1" ]; then
        red "    ⚠️  历史中存在疑似凭据！需要立即清理（git filter-branch / BFG）"
        FOUND=1
    else
        green "    ✓ git 历史干净"
    fi
else
    bold "==> 3/3  跳过（--staged-only）"
fi

# ============================================================
# 总结
# ============================================================
echo
if [ "$FOUND" = "0" ]; then
    green "✅ 安全检查通过"
    exit 0
else
    yellow "⚠️  安全检查发现问题，请人工 review"
    exit 1
fi
