#!/usr/bin/env bash
# 回滚「全局启用模型推理/思考等级」本体补丁
# 用法: bash rollback-reasoning-patch.sh [dsh-llm-pi-ai/lib/index.js 路径]
set -euo pipefail

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

if ! grep -q 'thinkingLevelMap: { off' "$TARGET"; then
  echo "[o] 未打补丁，无需回滚"; exit 0
fi

# 优先用 apply 脚本生成的备份恢复
BAK=$(ls -1t "${TARGET}.bak-before-reasoning-default-"* 2>/dev/null | head -1 || true)
if [ -n "${BAK:-}" ] && grep -q 'if (efforts === void 0) return { reasoning: base?.reasoning ?? false };' "$BAK"; then
  cp "$BAK" "$TARGET"
  echo "[+] 已从备份恢复: $BAK"
else
  # 没有备份就反向打补丁
  node -e '
const fs = require("fs");
const f = process.argv[1];
let s = fs.readFileSync(f, "utf8");
const old = "\tif (efforts === void 0) {\n\t\tif (base?.reasoning !== void 0) return { reasoning: base.reasoning };\n\t\treturn { reasoning: true, thinkingLevelMap: { off: null, minimal: null, low: \"low\", medium: \"medium\", high: \"high\", xhigh: null, max: null } };\n\t}";
const neu = "\tif (efforts === void 0) return { reasoning: base?.reasoning ?? false };";
const n = s.split(old).length - 1;
if (n !== 1) { console.error("[x] 补丁块出现 " + n + " 次，应为 1 次，中止"); process.exit(1); }
fs.writeFileSync(f, s.replace(old, neu));
console.log("[+] 已反向还原补丁");
' "$TARGET"
fi

grep -q 'thinkingLevelMap: { off' "$TARGET" \
  && { echo "[x] 回滚失败"; exit 1; } \
  || echo "[v] 验证通过：已恢复原始 resolveModelReasoning 分支"
echo "[i] 前端刷新页面即恢复原状。"
