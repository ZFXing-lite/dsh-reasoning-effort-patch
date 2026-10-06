# DSH 全局启用模型推理/思考等级补丁

给 [DeepSeek Harness (DSH)](https://github.com/deepseek-ai) 的 `dsh-llm-pi-ai` 打一个**本体补丁**，让模型选择菜单里的「推理等级 / Reasoning Effort」选项对所有模型默认可见——包括你在 `settings.yaml` 里手动声明的模型，以及以后新建的 provider/模型。

- 适用版本：DSH `0.1.5-rc.2`（其它版本见下方「版本漂移」）
- 打完**不用重启** DSH，前端刷新页面即可看到效果
- 幂等、自动备份、可一键回滚

## 背景：为什么需要这个补丁

DSH 前端模型选择菜单本来就带「推理等级」选项，但只在模型带 `reasoning` 字段时才渲染。默认配置下它几乎永远不出现，根因有两层：

1. `settings.yaml` 里的 provider route key 是自定义名，匹配不到 pi-ai 的内建 provider，拿不到内建 reasoning 元数据。
2. 手动声明的模型条目一般只写 `id`/`name`，没有声明 `reasoningEfforts`。

于是后端 catalog 里每个模型的 `reasoning` 都是 `undefined`，前端判断 `reasoning !== void 0` 不成立，那一行永不渲染。

相关代码位置（`0.1.5-rc.2`）：

| 位置 | 作用 |
|------|------|
| `dsh-client-ui-model-selection` 的 `ModelSelect.tsx` | 前端渲染条件 `reasoning !== void 0` |
| `dsh-llm-pi-ai/lib/index.js` 的 `reasoningInfo()` | 后端产出 reasoning 字段 |
| `dsh-llm-pi-ai/lib/index.js` 的 `resolveModelReasoning()` | **本补丁的修改点** |

## 补丁内容

改 `resolveModelReasoning()` 里 hand-declared 模型的默认分支：

```js
// 原始（单行）：
if (efforts === void 0) return { reasoning: base?.reasoning ?? false };

// 打补丁后：
if (efforts === void 0) {
    if (base?.reasoning !== void 0) return { reasoning: base.reasoning };
    return { reasoning: true, thinkingLevelMap: { off: null, minimal: null, low: "low", medium: "medium", high: "high", xhigh: null, max: null } };
}
```

三种情形互不影响：

- **有内建 catalog 的模型**：继续继承 `base.reasoning`，行为不变。
- **hand-declared 模型（无 base）**：默认 `reasoning=true` + `low`/`medium`/`high` 三档，前端出现「推理等级」行。
- **显式声明了 `reasoningEfforts` 的模型**：走原有逻辑，不受影响。

> `thinkingLevelMap` 里 `off/minimal/xhigh/max` 为 `null` 表示「UI 不展示这一档」。pi-ai 支持完整档位集合，想要更多档位改这个 map 即可。

## 用法

### 一键脚本（推荐）

```bash
git clone <本仓库地址>
cd dsh-reasoning-effort-patch
bash apply-reasoning-patch.sh
```

脚本会自动定位 `dsh-llm-pi-ai/lib/index.js`（依次尝试 `/usr/lib/node_modules/...`、`/usr/local/lib/node_modules/...`、`npm root -g` 解析），找不到时把路径作为参数传入：

```bash
bash apply-reasoning-patch.sh /path/to/dsh/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js
```

看到如下输出即成功：

```
[*] 目标: /usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js
[+] 补丁已写入
[v] 验证通过：hand-declared 模型默认 reasoning=true + low/medium/high
```

然后**刷新 DSH 页面**，点模型选择按钮，菜单里出现「推理等级」，可选 low/medium/high。

### 手动打补丁

1. 找到文件（记为 `$PIAI`）：
   ```bash
   PIAI=$(npm root -g)/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js
   ```
2. 备份：
   ```bash
   cp "$PIAI" "$PIAI.bak"
   ```
3. 把 `resolveModelReasoning()` 里的这一行：
   ```js
   if (efforts === void 0) return { reasoning: base?.reasoning ?? false };
   ```
   替换成「补丁内容」一节里的三行版本。保存，刷新页面。

## 验证

- 刷新页面 → 模型选择菜单出现「推理等级」行，可选 low/medium/high。
- 以后新建 provider/模型，自动有该选项，无需再跑脚本。
- 可选：`dsh web --dump-config` 退出码为 0、进程存活，说明配置未被破坏。

## 回滚

```bash
bash rollback-reasoning-patch.sh
```

优先用打补丁时生成的 `.bak-before-reasoning-default-*` 备份恢复；没有备份就反向还原补丁。刷新页面即恢复原状。

## 注意事项

- **DSH 升级会覆盖本补丁**：`npm i -g @deepseek-ai/dsh` 会重写 `dsh-llm-pi-ai/lib/index.js`，补丁丢失。升级后重新跑一次 `apply-reasoning-patch.sh` 即可。
- **hand-declared 默认 reasoning 的副作用**：所有在 `settings.yaml` 里手动声明（只写 `id`/`name`）的模型都会默认显示推理等级选项。若某个模型或网关不支持 reasoning，选了等级可能被网关拒绝。对个别模型禁用，给它加 `reasoningEfforts: false`。
- **Anthropic 类 provider**：claude 系走 anthropic 的 thinking/budget 机制，不是标准 `reasoning_effort`。UI 仍显示选项，选等级启用 thinking。
- **无需重启**：后端每次请求重读 profiles，前端刷新触发 modelCatalog RPC 重新拉取。

## 可选：配置层双保险（非必需）

补丁已覆盖默认行为。若想显式声明（比如只给个别 provider 开启），在 `settings.yaml` 里这样写：

```yaml
    <provider-route-key>:
      compat:
        supportsReasoningEffort: true      # openai-completions 类 provider
      models:
        - id: <model-id>
          reasoningEfforts:
            low: low
            medium: medium
            high: high
```

`settings.yaml` 不受 DSH 升级影响，作为本体补丁的兜底。路径示例：`/var/lib/dsh/settings.yaml`（具体位置以你本机的 DSH 数据目录为准）。

## 版本漂移

脚本靠**字面量匹配**原始代码定位，不依赖行号，但 pi-ai 一旦改动 `resolveModelReasoning()` 的写法，匹配会失败并提示：

```
[x] 未找到原始 resolveModelReasoning 单行分支，pi-ai 版本可能已变动，需人工核对
```

这时人工打开 `$PIAI` 搜 `resolveModelReasoning`，把 `efforts === void 0` 分支按「补丁内容」改写即可，思路与版本无关。

## 许可

MIT
