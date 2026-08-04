---
name: correct-struct-pinyin
description: Audit and correct per-character pinyin in textbook *struct.json files using corresponding *polyphone.json tables, with explicit review plans, conflict detection, source-annotation protection, atomic application, and Markdown status reports. Use when Codex needs to find contextual polyphone mistakes, review suggested readings, safely write approved pronunciation corrections, or report corrected, unchanged, and manual-review locations.
---

# 校正 struct.json 注音

读取多音字表，为对应 `struct.json` 生成候选修正；逐项结合上下文确认后，再通过带前置条件的计划文件写回。禁止仅按单字默认音或“本册出现”分组全局覆盖。

## Step 1：盘点文件与生成链

1. 读取仓库指令并检查工作区状态。
2. 配对 `*-polyphone.json` 与同名前缀的 `*-struct.json`。
3. 找到 struct 生成器、polyphone 生成器、人工短语规则、阅读器和测试。
4. 校验正文与拼音逐字对齐；记录每册注音单元数。

如果存在生成器，最终必须同步持久化人工短语规则，不能只修改输出文件。

## Step 2：生成候选报告

运行：

```bash
python .agents/skills/correct-struct-pinyin/scripts/correct_struct_pinyin.py \
  out/*polyphone.json --audit-dir /tmp/polyphone-audit
```

脚本执行以下保守筛选：

- 从文件名推导对应 `-struct.json`。
- 只在词例完整命中时产生证据，优先最长词例。
- 同一位置的最长证据指向多个读音时记为冲突。
- 当前注音不在该字的表格读音集合中时不建议修改；这通常是课本轻声、儿化或原书特有标注。
- 审计阶段绝不写入 struct。

每份审计同时生成 JSON 计划和 Markdown 表格。JSON 包含 `候选 / 冲突 / 修正 /
保留不改 / 人工复核`，后三个决策数组初始为空；Markdown 中未决的候选和冲突
统一显示为 `人工复核`。

## Step 3：逐项审核候选

逐项审核后分类，不能只删除候选：

- 确认需要修改：复制到 `修正`。
- 确认原注音正确：复制到 `保留不改`，并填写 `依据`。
- 仍无法确定：复制到 `人工复核`，说明疑点。

所有条目保留 `路径、序、字、原拼音、建议拼音、词例、上下文`。

按以下优先级判断：

1. PDF 原书逐字注音：最高优先级，除非用户明确指出原书有误。
2. 人工校对规则和权威词典语境。
3. 多音字表的 `语境 / 快速判断 / 例子`。
4. 当前句法、词义和固定搭配。
5. 自动词库建议：只能作为线索。

必须特别检查：

- 轻声：`眼睛 jing、衣服 fu、娃娃 wa、明白 bai` 等不得按字典本调覆盖。
- 儿化：`一块儿 kuàir、哪儿 nǎr、伙伴儿 bànr` 等保留合并标注。
- 变调：`一、不` 根据后字声调判断，不能仅凭词例列表。
- 多义固定词：`落下来`读 `luò`，不能因“落下”词例机械改成 `là`。
- 同形冲突：`一样、一些、不了、吆喝、肚子` 等若表中同时归入多个读音，必须人工判断。

不确定时不要加入 `修正`，将其留在候选或冲突中并报告人工复核。

## Step 4：应用已批准计划

运行：

```bash
python .agents/skills/correct-struct-pinyin/scripts/correct_struct_pinyin.py \
  --apply-plan /tmp/polyphone-audit/*-pinyin-audit.json
```

脚本在写入前验证：

- 目标文件、JSON 路径和字符仍存在。
- `序` 对应字符与计划的 `字` 一致。
- 当前拼音仍等于 `原拼音`。
- `建议拼音` 存在于配套多音字表。

任一前置条件失败时整份文件不写入。成功时使用同目录临时文件原子替换。
应用成功后，脚本把 `修正` 记录为 `已修正`，补齐句子上下文，并在计划旁重新生成
Markdown 状态报告。

只需从已审核的 JSON 重新生成最终报告时运行：

```bash
python .agents/skills/correct-struct-pinyin/scripts/correct_struct_pinyin.py \
  --render-report /tmp/polyphone-audit/*-pinyin-audit.json --report-dir out
```

每份 Markdown 必须有一张统一表格，至少包含：

| 位置索引 | 所在的句子上下文 | 原注音 | 修正后的注音 | 状态 |
|---|---|---|---|---|

状态只能使用：`已修正 / 保留不改 / 人工复核`。人工复核项的修正后注音写成
`待定（候选读音）`，不得伪装成已经修改。

如果修正计划与初始审计分开保存，并且已经确认“其余候选全部保留、冲突全部复核”，
可合并完成报告：

```bash
python .agents/skills/correct-struct-pinyin/scripts/correct_struct_pinyin.py \
  --finalize-report /tmp/polyphone-audit/*-pinyin-audit.json \
  --approved-plan /tmp/polyphone-audit/*-approved.json --report-dir out
```

不得在尚未逐项审核候选时使用 `--finalize-report`，因为它会把未批准候选明确记录为
`保留不改`。

## Step 5：持久化生成规则

对于确认的修正，检查 struct 生成器为何产生旧读音：

- 词库切分错误：添加明确短语读音规则。
- PDF 已有注音：修复源注音提取或合并，不要用生成音覆盖。
- 轻声、儿化或变调：增加有测试的上下文规则。
- 仅数据人工校对：记录为显式覆盖数据，并说明来源。

重新生成目标文件后，确认修正不会回退。

## Step 6：校验与交付

1. 再次生成候选报告，确认已批准位置不再出现。
2. 校验所有 `全文/拼音` 及附录 `字或词/拼音` 长度对齐。
3. 运行项目测试、JSON 解析、脚本语法和差异检查。
4. 抽查每册已改位置及轻声、儿化、变调保护样例。
5. 检查最终 Markdown 覆盖全部已修正、保留不改和人工复核项，且位置索引、上下文、
   原注音、修正后注音和状态齐全。
6. 报告每册候选数、冲突数、实际修正数、保留数、未决项和测试结果。

除非用户明确要求，不要提交版本控制记录。

## 脚本

使用 `scripts/correct_struct_pinyin.py` 生成 JSON/Markdown 审计报告、应用人工批准的
修正计划，并从历史决策重新渲染 Markdown 状态表。脚本仅依赖 Python 标准库。
