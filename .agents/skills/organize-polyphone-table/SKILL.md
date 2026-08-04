---
name: organize-polyphone-table
description: Organize Chinese polyphone JSON files into a consistent 字、读音、语境、例子、快速判断 structure while preserving textbook occurrence groups. Use when generating, migrating, reviewing, or validating *polyphone.json files; when replacing 拼音/组词-only records with learner-facing guidance; or when updating a viewer that consumes these tables.
---

# 整理多音字表

把多音字数据整理成可核验、可重复生成、适合学习者使用的表格。优先修复数据生成器；只有现成 JSON 时，使用随附脚本迁移。

## Step 1：盘点输入和生产链

1. 读取仓库说明和代理指令。
2. 查找 `*polyphone.json`、对应的 `*struct.json`、生成器、阅读器和测试。
3. 记录每份文件的多音字数、读音数、现有字段及 2–3 条样例。
4. 检查工作区状态，保留用户已有修改。

不要只改生成产物。如果仓库有生成器，必须同步修改生成器和测试，避免下次生成时丢失整理结果。

## Step 2：固定输出契约

保留每个字外层的来源分组：`本册出现 / 常用 / 不常用`。每个读音条目只输出：

```json
{
  "读音": "děi",
  "语境": "表示必须、需要或对情况的估计。",
  "例子": ["我得走了", "非得完成", "得三天"],
  "快速判断": "能换成“必须”或“需要”时，读 děi。"
}
```

外层 `字` 与条目中的四个字段共同构成：`字、读音、语境、例子、快速判断`。

要求：

- `读音` 使用带调拼音；轻声不加声调。
- `例子` 使用数组，通常保留 1–3 个短词或短语。
- `语境` 说明词义、语法位置或固定搭配。
- `快速判断` 给出可操作的替换、位置或固定词判断。
- 没有可靠词例时明确写“罕见、古语或词典保留读音”，不要编造释义。

## Step 3：确定证据优先级

按以下顺序取证：

1. 课本逐字注音：决定是否属于 `本册出现`。
2. 项目人工校对规则：决定语法敏感字和已知误读。
3. 本册词例：优先作为例子。
4. 短语词典和常用词表：补充其他常用读音。
5. 无可靠词例的词典读音：归入 `不常用` 并提示查词典。

词库只证明“某词可能对应某读音”，不自动提供准确释义。不要把自动生成的词例描述成完整词义。

## Step 4：先写人工规则

为不能仅靠词例判断的字维护 `(字, 读音)` 人工规则表。至少覆盖结构助词“的、地、得”：

- `的 de`：名词前的修饰语；`dí`：的确；`dì`：目标或命中；`dī`：出租车口语。
- `地 de`：动作前说明方式；`dì`：土地或地点。
- `得 de`：动作后补充程度或结果；`dé`：获得；`děi`：必须或需要。

发现自动词例与标准读音冲突时，增加人工规则或短语修正，不要仅修改某一份输出 JSON。

## Step 5：修改生成器

1. 保留现有读音发现、分组和词频排序逻辑。
2. 将旧字段 `拼音 / 组词` 转成 `读音 / 例子`。
3. 人工规则优先；其余读音根据词例生成保守的语境和快速判断。
4. 使用临时排序字段时，在序列化前删除它。
5. 更新输出说明、CLI 文档和单元测试。

如果没有生成器，运行迁移脚本：

```bash
python .agents/skills/organize-polyphone-table/scripts/organize_polyphones.py \
  out/*polyphone.json --in-place
```

脚本兼容旧的 `拼音 / 组词` 格式，重复运行不会覆盖已经人工整理好的新字段。

## Step 6：同步消费者

检查阅读器、导出器和校对工具是否仍读取 `拼音 / 组词`。优先让消费者读取新字段，同时短期兼容旧字段：

```javascript
const pronunciation = entry["读音"] || entry["拼音"];
const examples = entry["例子"] || entry["组词"] || [];
```

在读音选择界面显示语境和快速判断，确保整理结果不只存在于原始 JSON 中。

## Step 7：逐层校验

先运行结构校验：

```bash
python .agents/skills/organize-polyphone-table/scripts/organize_polyphones.py \
  out/*polyphone.json --check
```

再执行：

1. 项目单元测试和脚本语法检查。
2. JSON 解析及字段全集检查。
3. 核对每份文件的多音字数和读音数。
4. 抽查“的、地、得”以及至少一个本册字、常用字和罕见字。
5. 检查差异中没有旧字段残留、临时字段或无关文件。

## Step 8：交付

报告修改的文件、每册字数与读音数、人工规则覆盖范围、测试结果及仍需人工判断的罕见读音。除非用户明确要求，不要提交版本控制记录。

## 脚本

使用 `scripts/organize_polyphones.py` 迁移或校验现有多音字 JSON。脚本仅依赖 Python 标准库；写入时采用同目录临时文件后原子替换。
