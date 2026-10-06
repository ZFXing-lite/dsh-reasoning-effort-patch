#!/usr/bin/env bash
# 给 DeepSeek Harness (DSH) 打「全局启用模型推理/思考等级」本体补丁
# 幂等：已打过补丁则跳过。用法: bash apply-reasoning-patch.sh [dsh-llm-pi-ai/lib/index.js 路径]
set -euo pipefail

# 1. 定位目标文件（优先用参数，其次走全局 npm 解析）
TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  for cand in \
    /usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js \
    /usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js \
    "$(npm root -g 2>/dev/null)/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js"; do
    [ -f "$cand" ] && TARGET="$cand" && break
  done
fi
[ -f "$TARGET" ] || { echo "[x] 找不到 dsh-llm-pi-ai/lib/index.js，请把路径作为参数传入"; exit 1; }
echo "[*] 目标: $TARGET"

# 2. 幂等检查
if grep -q 'thinkingLevelMap: { off' "$TARGET"; then
  echo "[o] 已打过推理等级补丁，无需重复操作"; exit 0
fi

# 3. 确认原始代码存在（版本漂移检测）
grep -q 'if (efforts === void 0) return { reasoning: base?.reasoning ?? false };' "$TARGET" \
  || { echo "[x] 未找到原始 resolveModelReasoning 单行分支，pi-ai 版本可能已变动，需人工核对"; exit 1; }

# 4. 备份 + 打补丁（node 做字面量替换，避免 sed 转义陷阱）
BAK="${TARGET}.bak-before-reasoning-default-$(date +%Y%m%d%H%M%S)"
cp "$TARGET" "$BAK"
echo "[*] 备份: $BAK"
node -e '
const fs = require("fs");
const f = process.argv[1];
let s = fs.readFileSync(f, "utf8");
const old = "\tif (efforts === void 0) return { reasoning: base?.reasoning ?? false };";
const neu = "\tif (efforts === void 0) {\n\t\tif (base?.reasoning !== void 0) return { reasoning: base.reasoning };\n\t\treturn { reasoning: true, thinkingLevelMap: { off: null, minimal: null, low: \"low\", medium: \"medium\", high: \"high\", xhigh: null, max: null } };\n\t}";
const n = s.split(old).length - 1;
if (n !== 1) { console.error("[x] 原始分支出现 " + n + " 次，应为 1 次，中止"); process.exit(1); }
fs.writeFileSync(f, s.replace(old, neu));
console.log("[+] 补丁已写入");
' "$TARGET"

# 5. 验证
grep -n 'thinkingLevelMap: { off' "$TARGET" \
  && echo "[v] 验证通过：hand-declared 模型默认 reasoning=true + low/medium/high"
echo "[i] 无需重启 DSH；前端刷新页面即可看到「推理等级」选项。"
echo "[i] 回滚: bash rollback-reasoning-patch.sh \"$TARGET\""
