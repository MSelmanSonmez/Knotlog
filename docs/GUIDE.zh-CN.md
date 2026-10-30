# Knotlog — 用户指南

> 本译文由机器辅助完成，欢迎指正。

你已经安装了 Knotlog，它也创建了一个知识库。本指南讲的是接下来的事：
哪些事会自动发生，哪些事要你亲手做，以及哪条命令能回答哪个问题。
关于安装本身，请参阅 [README](../README.zh-CN.md)。
安装向导包含一个“风格”步骤（语气、点缀、文件夹名称），之后可用 `knotlog tone` 和 `knotlog flair` 修改。如果 `PATH` 中更靠前的位置有较旧的 `knotlog`，安装摘要和 `knotlog doctor` 会发出警告，因为钩子运行的是那一个。

> **前身为 Quipu。** Knotlog 是 Quipu 的新名称；旧的 `quipu` 命令已移除。如果你有用旧名称创建的知识库，运行 `knotlog migrate` 预览变更，运行 `knotlog migrate --apply` 写入变更；它还会把旧的 `quipu` 钩子命令改写为 `knotlog`。你手工编辑过的桥接块不会被刷新（只会重命名其标记），并会给出警告。

如果你还没有安装 Knotlog，一行命令即可：

```bash
curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
```

它会获取一个经过校验的发布版本，并交给 `knotlog install` 继续处理；
[README](../README.zh-CN.md) 还介绍了基于检出仓库的安装方式以及 Windows。

## 1. Knotlog 为你做什么

Knotlog 把你的编码智能体做过的事用 Markdown 记在一个文件夹——也就是知识库——里。
围绕一次 Claude Code 会话，会发生三件事：

- **你工作时**，智能体读取或写入的每个文件都会作为一行追加到
  `.knotlog/activity.log`：时间戳、事件、工具、路径。
- **会话结束时**，这些行会被汇总成会话文件夹下一份带日期的笔记，
  同时刷新搜索索引。
- **下一次会话开始时**，Knotlog 会把最近的活动、未完成的线索和一行身份信息
  打印回模型的上下文——让智能体一开场就知道上次发生了什么。
  第一行始终是当前的日期、时间和星期名称（`now: 2026-09-02 20:15 Wednesday`）——
  没有它，模型写会话标题时只能猜时间，而猜测会越来越偏。

这里没有数据库，也没有网络调用。每个文件都是 Markdown，你可以阅读、
编辑，并提交到 git。Knotlog 只做追加，绝不改写你的文字。

## 2. 日常循环

最先让人困惑的是：这个循环有一部分会自己运行，有一部分是你的事。
划分如下。

**自动运行**（Claude Code 适配器，安装在
`<vault>/.claude/settings.json`）：

| 时机 | 运行什么 | 效果 |
|---|---|---|
| 会话开始 | `knotlog remember && knotlog context --json SessionStart` | 待处理的日志行变成会话笔记；最近的记忆被注入 |
| 你发送每条提示 | `knotlog context --json UserPromptSubmit` | 新增足够多的日志行后，提醒模型把记忆写下来 |
| `Edit`/`Write`/`NotebookEdit`/`Read` 之后 | `knotlog capture` | 向 `activity.log` 静默追加一行 |
| 会话结束 | `knotlog remember && knotlog index` | 写入会话笔记并刷新索引 |

要让它正常工作有两个条件：`knotlog` 必须在你的 `PATH` 中，而且 Claude Code
只在启动时读取一次钩子配置——**修改 `settings.json` 之后请重启它**。

**需要你来做：**

1. 工作时把笔记写进知识库的各个文件夹。Knotlog 会为你放进去的内容建立索引；
   它不会自己编造笔记。
2. 会话结束时，填写今天会话笔记中的反思块。
   骨架已经在那里，带有三个标题。智能体可以代你填——
   `SessionStart` 的上下文会要求它这么做——但没有人检查它是否真的填了。
3. 保持线索文件（`Threads.md`）是最新的：哪些仍未完成，哪些已关闭。
4. 需要找以前会话里的内容时，运行 `knotlog search`，而不是重新讲一遍。

Knotlog 负责机械的流水账。含义由你和模型来写。

## 3. 文件夹

`init` 会创建十个文件夹。下面的名称是英文布局；土耳其语知识库会得到土耳其语名称，
`--plain` 则得到 ASCII 名称。这里没有任何强制规定——这是一种习惯，不是模式（schema）。

| 文件夹 | 何时写在这里…… |
|---|---|
| `📥 Inbox` | 有了一个想法，但你暂时不想决定它归哪里 |
| `🗑️ Trash` | 在收件箱里倾倒原始素材——粘贴内容、片段、转录稿 |
| `🎯 Command Center` | 它属于仪表盘：今天的重点、入口链接 |
| `🗂️ Projects` | 笔记关于某一项进行中的工作——每个项目一个子文件夹 |
| `🧠 Knowledge` | 几个月后你还会想再用到它，且与任何项目无关 |
| `🛠️ Arsenal` | 它是一个可复用的工具、脚本或代码片段 |
| `📆 Sessions` | 几乎从不手写——`knotlog remember` 会写到这里，每天一个文件 |
| `🔮 Companion` | 伙伴（companion）的人设，以及它所携带的身份笔记 |
| `📦 Archive` | 事情已经完成或被冻结，你想让它不碍事 |
| `📋 Templates` | 不要原地编辑——把 `note.md`、`project.md` 或 `session.md` 复制出来用 |

Templates 文件夹自带这三个骨架，并且**被排除在搜索索引之外**：
它们是用来复制的样式，不是用来被找到的内容。一个有三条笔记和三个模板的知识库，
索引的是笔记，不是模板。

## 4. 你要输入的命令

下面的一切都在知识库内运行（任何子文件夹都可以——Knotlog 会向上查找
`.knotlog/`）。

**`knotlog search <terms>`** — 查找笔记。

```
$ knotlog search taskbar
0.934	🧠 Knowledge/taskbar.md	Taskbar overflow	windows,ui
0.673	🧠 Knowledge/dpi.md	DPI notes	windows
```

**`knotlog links <path>`** — 查看一条笔记与哪些内容相连。传入相对于知识库的路径。

```
$ knotlog links "🧠 Knowledge/dpi.md"
outgoing links
incoming links
🧠 Knowledge/taskbar.md
```

出链是该笔记中写下的 `[[wikilinks]]`；入链是指向它的笔记。链接目标按精确字符串解析，
不做折叠——请写 `[[dpi]]`（文件名主干）或相对于知识库的完整路径。

**`knotlog digest`** — 汇总某一天的活动，且不触动会话水位线。
`--dry-run` 只打印不写入，`--date YYYY-MM-DD` 选择某一天，
文件会落在转储文件夹中。

```
$ knotlog digest --dry-run
---
Activity digest: 2026-08-30
type: digest
status: generated
---

Range: 2026-08-30T22:56 → 2026-08-30T22:56 (2 events)
Tools: Edit 1, Write 1
Touched files (top 10):
- 🧠 Knowledge/dpi.md (1)
- 🧠 Knowledge/taskbar.md (1)
```

**`knotlog doctor`** — 健康检查。见第 7 节。

**`knotlog import FILE`** — 把保存下来的对话导出（Claude 转录稿、
ChatGPT 导出，或带 `role`/`content` 的 JSONL）转成会话笔记。

```
$ knotlog import /tmp/chat.jsonl --date 2026-08-29
wrote: 📆 Sessions/2026-08-29-import-chat.jsonl.md
```

**`knotlog plan <name> --proje <Project>`** — 在计划应该在的位置打开一份计划笔记：
`<projects>/<Project>/<Plans>/<name>.md`，用本地化的 front-matter 模板生成，
若设置了 `$EDITOR` 则用它打开。计划就是记忆——
把它们放在知识库里，下一次会话才会继承它们，
所以项目文件夹不存在时会报错，绝不会自动创建，
已有的计划也绝不会被覆盖。在项目文件夹内部运行时，
`--proje` 会自行解析。

```
$ knotlog plan roadmap --proje Knotlog
wrote: 🗂️ Projects/Knotlog/Plans/roadmap.md
```

**`knotlog tone [--list|<slug>]`** — 显示或设置语气预设。不带参数时，
会打印当前生效的来源及原因（某个预设 slug、companion.md 自带的
Tone 部分，或两者都没有）；`--list` 浏览随附的九个预设
（Default、Professional、Friendly、Candid、Quirky、Efficient、Snarky、
Teaching、Kaomoji）并标出当前生效的那个；`<slug>` 会把 `tone=<slug>` 写入
`.knotlog/config`——绝不会触碰 companion.md。

```
$ knotlog tone --list
Tone presets:
  varsayilan   Default — The preset tone and voice
  profesyonel  Professional — Polished and clear
  ...
* etkili       Efficient — Brief, tight, clear
  ...
$ knotlog tone
active tone: Efficient (preset: etkili)
```

**`knotlog index`** — 手动刷新索引。钩子会在会话结束时做这件事；
在会话之外添加笔记后，请自己运行一次。`--full` 会重建全部内容。

```
$ knotlog index
# indexed 6 (reused 5, stale 1, dropped 0)
```

**`knotlog remember`** — 现在就写入会话笔记，而不是等到会话结束。加上
`--git` 会在之后提交知识库；不加的话，Knotlog 绝不会提交。

## 5. 搜索你自己的记忆

`search` 会对查询做折叠，用 BM25 给索引打分，并把最佳的若干行
以制表符（TAB）分隔的列打印出来：分数、路径、标题、标签。默认十行。

- `--limit N` — 返回多少行。
- `--paths` — 只输出路径列，每行一个：`knotlog search dpi --paths`。
- `--brief` — 多一列，内容是笔记约 120 字节的摘要。用它来挑选要打开哪两条笔记，
  而不是把十条都打开。不能与 `--paths` 同时使用。
- `--tag ui` / `--status paused` — 丢掉 frontmatter 不匹配的所有笔记。
  它们是过滤条件，不是排序提示；组合使用时是 AND 关系。

分数是相对于你的知识库的，不是绝对值——在很小的知识库里，
过滤后命中的结果分数可能低于零，却依然是对的笔记。

**折叠，以及它对土耳其语为什么重要。** 在建立索引之前和搜索之前，
文本都会经过一个折叠配置，记录为 `.knotlog/config` 中的 `fold=`。
土耳其语知识库会得到 `fold=tr`：`İ ı ğ ş ç ö ü` 会折叠为各自的
ASCII 形式，这样查询和笔记就能在中间相遇。

```
$ knotlog search "acik kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
$ knotlog search "açık kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
```

两种写法都能找到这条笔记。`default` 配置——英文知识库使用的那个——
除了 ASCII 大小写之外不做任何折叠，所以在那里 `acik` 找不到 `açık`。
如果你在英文布局的知识库里写土耳其语，请在 `.knotlog/config` 中设置 `fold=tr`，
然后运行一次 `knotlog index --full`；索引必须用新的配置重建。

折叠是有意为之的有损操作：`açık` 和 `acık` 会折叠成同一个键。
有一个已知的缺口：`--tag` 会折叠它的参数，但拿它与原始的
frontmatter 文本比较，所以 `--tag istanbul` 找不到写成 `İstanbul` 的标签。

## 6. 线索与会话笔记

有四个文件在会话之间承载着故事。

**今天的会话笔记**（`📆 Sessions/YYYY-MM-DD.md`）由 `remember` 写入。
上半部分是机械记录——时间范围、工具计数、被触碰的文件。下面是
Knotlog 只添加一次、之后再也不碰的骨架：

```
<!-- knotlog:reflect:start -->
### What changed in this session?

### Where did the work happen?

### Threads touched or continued

<!-- knotlog:reflect:end -->
```

填写它是你的工作。同一天再次运行 `remember` 不会覆盖
已经写在那里的内容。只要这个块还是空的，`SessionStart` 就会要求模型
去填写，并指明这个文件；如果昨天的块被留空，下一次
会话只会被告知一次，之后这个提示就会被丢弃。

**`Threads.md`**（土耳其语知识库中是 `Konular.md`）位于知识库根目录，保存那些
比一天更长久的故事线，分在 `### Active threads` 和 `### Closed threads` 之下。`knotlog context` 会把
它回灌到每一次会话中，这使它成为知识库里杠杆最高的文件——
也是最容易任其腐烂的文件。保持简短；已经关闭的线索
应该往下移，而不是留在顶部。

### 规则文件

`init` 会在知识库根目录放入 **`Rules.md`**（土耳其语知识库中是 `Kurallar.md`）——
这是在知识库中工作的每个智能体都会继承的行为契约。
随附的默认内容包含 Knotlog 认为不可商量的四个块：

- **审批关口** — 资金流动、对外消息、删除和
  机密，未经批准绝不越过；一次同意只覆盖一个会话中的一项任务。
- **零级协议** — 十一条基线工作习惯（契约范围、
  开工前先有完成定义、把验证输出写入
  文件、说“完成”之前要报告的三件事、
  每个逻辑步骤一次提交、会话结束时的三行总结等等），每一条都附有
  存在的理由。
- **收据规则** — 一次提交、一个被更新的文件、写到磁盘的输出就是
  收据；“完成了”不是。没有痕迹，就没有工作。
- **记录纪律** — 当新记录取代旧记录时，让旧的退役：
  在知识库中搜索旧名称，关闭或更新它；绝不让同一个主题留下两份有效副本。

你可以随意编辑这个文件——它是你的；Knotlog 绝不会覆盖它（已有的
文件即使以另一种语言的名称存在也优先）。`knotlog context` 会把
这个文件的标题注入每个会话，位置在线索部分之后；当 `ctx_max` 被压得很紧时，会整体丢弃这一部分，而不会先去削减线索块。
`doctor` 会在产品文件中检查随附的模板。在你编辑
种子文件之前，它不算手写的记忆文件——所以全新的知识库
运行 `doctor` 仍然是干净退出；一旦你往里写入内容，它就加入第 7 节
所述的必备叙事文件集合。

桥接文件（`AGENTS.md`/`CLAUDE.md`）带有检查点协议，
用来在会话糟糕收场时让故事不中断：工作一完成就写下记录，
而不是等到会话结束；工作中途停下时，写下停在哪里以及下一步；
当用户暗示要离开时，先把记录写完再关闭。

Knotlog 绝不会改写这些文件中的任何一个。在它这一侧，全部都是只追加。

### 事实文件

`init` 会在知识库根目录放入 **`Facts.md`**（土耳其语知识库中是 `Gerçekler.md`）——
这是持久事实层，无需任何外部记忆服务。
规则是**一行一个事实**：每个项目符号行都以三个标签之一开头——`Decision:`
（已做出的选择及其理由，在改变之前一直有效）、
`Preference:`（你喜欢怎样工作）、`Convention:`（这个知识库里事情怎么运转）。
入选标准：一行内容在几个月后必须依然既真实又有用——**身份信息够格，新闻不够**；
任何会过时的内容都应该放进 `Threads.md` 或会话笔记。

你可以随意编辑这个文件——它是你的；Knotlog 绝不会覆盖它（已有的
文件即使以另一种语言的名称存在也优先）。`knotlog context` 会把
事实行注入每个会话，位置在规则部分之后，遵循同样的
`ctx_max` 约定：预算被挤压时整体丢弃这一部分，绝不削减
线索块。未改动的种子文件只是骨架，不是记录——在你写下第一行之前，
context 对它保持沉默。当文件存在时，`doctor` 会打印一行
写明事实行数的 `ok`；在这一层出现之前创建的知识库里则保持沉默。

## 7. 看起来不对劲时

`knotlog doctor` 会按区域分节打印，并给出一行汇总。只有警告时退出码为 0，
只有出现失败时才为 1。

```
summary: 151 ok, 3 warn, 0 fail
```

**记忆的哪一部分会被审计？** 知识库中并非每个文件都按同一标准要求。
**活记忆**——AGENTS.md/CLAUDE.md 桥接文件、
线索文件、规则和核心笔记，以及 `Last-Session.md` 中最新的 `## ` 块——
是下一次会话赖以立足的指令；其中的每个路径都必须能解析。
**历史记忆**——`Last-Session.md` 中较旧的块、日志笔记、
会话文件夹下的一切——是一份记录；它有权提到已经不存在的文件夹，
路径审计从不读取它。追加一个新的会话块，旧的那个就会自动变成
历史。

记忆文件的名称遵循知识库的语言（土耳其语知识库中是 `Son-Oturum.md`/`Kurallar.md`/
`Çekirdek.md`/`Günlük.md`，英文知识库中是 `Last-Session.md`/`Rules.md`/
`Core.md`/`Journal.md`），另一种语言的名称会作为旧版后备被接受。
一旦你的知识库里有了手写的记忆文件，这一组就变成**必备**：
缺少一个文件，是唯一会让 doctor 退出码变成 1 的记忆类发现——
记忆层只迁移了一半，正是会话悄无声息丢失注入内容的原因。

如何阅读重要的几行：

- **tools** 下的 `fail` — `sh`、`sed`、`awk`、`grep`、`tr`、`git` 就是
  全部的依赖清单。缺少其中一个，是唯一会让 Knotlog 停摆的故障。
- `warn index — index.tsv missing or stale (knotlog index)` — 在全新的
  知识库、在会话之外编辑笔记之后，以及紧接在 `remember` 之后都属预期——
  因为它写了一份索引还没见过的会话笔记。运行 `knotlog index`。
- `warn threads — Threads.md has not been updated yet` — 文件缺失，或者
  它的 `Active/Closed threads` 块仍然是空的。仅有骨架不能消除这条警告；
  写入的内容才行。新知识库上属预期，之后则是一次提醒。
- `warn links — N wikilink target(s) not found` — 某个 `[[link]]` 指向了空处。
  解析是精确字符串匹配，所以改名的笔记会留下一个悬空链接。
- `warn links — … resolve to more than one note` — 两条笔记同名，
  Knotlog 拒绝猜测你指的是哪一条。
- `fail memory — Last-Session.md | Son-Oturum.md not found` — 必备记忆文件之一
  无论用当前名称还是旧版名称都不存在。
  退出码 1；其他所有记忆类发现都只是警告。
- `warn paths — N quoted path(s) not found` — 你的活记忆中的某个 `` `quoted/path` ``
  指向了知识库中不存在的东西。每个缺失的路径会在计数下方各占一行列出。
  `~/`、绝对路径、URL、盘符、通配符和
  shell 片段从不被评判；后面跟着参数的知识库文件
  （`./knotlog doctor`）是命令，而只有文件夹名称的路径（`lib/`）只要知识库中
  任何位置存在同名文件夹，就算找到。
- `warn paths — … point inside git-ignored territory` — 路径存在，但 git
  并不跟踪它：它在这台机器上能用，等知识库被克隆或移动那天就坏了。
- `warn memory — N memory file(s) with uncommitted changes` — 你的记忆的
  安全网是 git；编辑了但未提交的记忆没有安全网。去提交。
- `warn last session — the newest session block does not mention today's date` —
  今天有一次提交，但 `Last-Session.md` 最新的块是更早写的。
  今天的日期会在整个块中搜索，所以跨过午夜的会话
  不会误报。

- `ok claude hooks — installed (vault)` — 适配器位于
  `<vault>/.claude/settings.json`。正常安装就是这个样子。
  单独的 `installed` 表示它是在全局的 `~/.claude/settings.json` 中找到的。
  `not installed` 表示两处都没有，第 2 节中的自动循环没有运行。
- `warn path — path contains OneDrive` / `locale is not UTF-8` — 对于 emoji 文件夹名和
  折叠而言的环境风险。两者都不会弄坏一个正常的知识库。

`doctor` 不会修改任何东西。它报告的每一项都是留给你去运行的命令。

## 8. 不使用钩子来使用 Knotlog

对于没有钩子接口的智能体——或者你想把循环握在自己手里——
两条命令可以取代自动的那部分：

- `knotlog capture --git` 把工作区与最后一次提交做 diff，
  并为每个变化的 Markdown 文件追加一行。请在 `remember` 之前运行。它是无状态的：
  中间不提交就运行两次，同样的文件会被记录两次。
- `knotlog context --bridge` 把钩子本会注入的上下文写进
  `AGENTS.md` 和 `CLAUDE.md` **两者**中的一个 `<!-- knotlog:context:start -->` 块。
  任何读取其中一个文件的智能体看到的都是同一份记忆——
  这正是一个智能体中的会话能接上另一个智能体会话成果的方式。

于是一次手动会话是这样的：用 `context --bridge` 刷新桥接文件，
让智能体读取其中一个，工作，然后运行
`knotlog capture --git && knotlog remember && knotlog index`。

### Antigravity

Antigravity 有钩子接口，所以它能获得自动循环。在知识库中运行：

```
knotlog setup antigravity --dry-run   # preview, writes nothing
knotlog setup antigravity             # writes .agents/hooks.json
```

会话开始时，钩子会运行 `remember`，并把最近的上下文作为
系统消息注入。当智能体结束一个回合时，第二个钩子会检查
会话笔记是否已经落后（最多每 30 分钟一次），如果是，
就让智能体在回合结束之前回去写它。已存在且内容不同的
`.agents/hooks.json` 绝不会被覆盖；请手动合并随附的那份
（`adapters/antigravity/hooks.json`）。之后请重启 Antigravity。
详情：[REFERENCE.md](REFERENCE.md#antigravity)。

### Devin Desktop (Windsurf) 与 OpenCode

两者都会得到一个小型的记录钩子；它们的上下文来自 `AGENTS.md`
桥接。在知识库中运行 `knotlog setup windsurf`（或 `devin`）以及
`knotlog setup opencode`；`--dry-run` 用于预览。它们会写入
`.devin/hooks.json` 和 `.opencode/plugins/knotlog.js`，并且绝不覆盖内容
不同的文件。客户端会从它自己的环境运行 `knotlog`（Devin
Desktop 使用你的登录 shell），所以 `knotlog` 必须在那个 `PATH` 中，否则钩子
会悄无声息地什么都不做。已于 2026-10-25 在 Linux 上实机验证（Devin Desktop
3.11.216、OpenCode 1.19.4）；Windows 未验证。详情：
[REFERENCE.md](REFERENCE.md#windsurf--devin-desktop)。

### 连接 MCP 服务器

`knotlog mcp` 让 MCP 客户端无需钩子就能搜索知识库并读取它的上下文。它提供三个工具：
`knotlog_search`（一个查询和一个可选的数量上限）、
`knotlog_context`，以及 `knotlog_note`（向今天的会话笔记写入一行，
等同于 `knotlog note`）。它根据启动时所在的文件夹来查找知识库，
所以请在知识库内部注册它：

```
claude mcp add knotlog -- knotlog mcp
```

如果 `knotlog` 不在你的 `PATH` 中，请改用绝对路径。其他
客户端可以用参数 `mcp` 运行同一条命令；对于在知识库之外启动的服务器，
请把 `KNOTLOG_VAULT` 设为知识库文件夹。详情：
[REFERENCE.md](REFERENCE.md#mcp-server)。

## 9. 配置项

知识库设置保存在 `.knotlog/config` 中，是朴素的 `key=value` 行：`layout`、
`lang`、`fold`、`user`、`companion`、`purpose`、`tone`、`flair`、`ctx_max`。修改
`fold` 之后需要运行 `knotlog index --full`；其他项在下一条命令时生效。
`ctx_max` 从不由 `init` 写入——它已经有可用的默认值（4096），
所以只有想覆盖它时才需要手动加这一行；
`doctor` 会报告它所使用的值来自哪里（env/config/
default），并在 config 中的 `ctx_max=` 不是正整数时给出警告
（会被忽略，不致命）。

**选择语言。** Knotlog 支持 English、Türkçe、Español、Português
(Brasil)、日本語 和 简体中文。可以在安装向导中选择，用
`--lang <code>`（`en`、`tr`、`es`、`pt-br`、`ja`、`zh-cn`），或者在
`.knotlog/config` 中设置 `lang=`；你所选语言中缺失的内容会回退到
英文。除英文和土耳其语之外的翻译都是机器辅助的，欢迎指正。

`tone` 从随附的九个语气预设中选一个（`knotlog tone --list` 显示
名称和说明，`knotlog tone <slug>` 进行设置）——只要所指名的预设
在该知识库的语言中确实存在，它在 Knotlog 注入的上下文里就优先于
companion.md 自带的 `## Tone`/`## Üslup` 部分。不设置它，或者把它设为一个
并未随附的 slug，Knotlog 就会回退到
companion.md 的 Tone 部分——与预设出现之前知识库的行为相同。和 `purpose` 一样，`init` 期间
没有针对 `tone` 的交互式提问；只有 `--tone <slug>` 标志（`install` 也接受）。

`flair` 在语气之上为回复添加点缀：`none`（默认）、`kaomoji` 或 `emoji`。`knotlog flair` 显示当前值，`knotlog flair --list` 列出选项，`knotlog flair <值>` 进行设置；`init` 和 `install` 也接受 `--flair`。文本提供全部六种语言。除 `none` 之外的点缀会取代 `kaomoji` 语气预设。

当默认值不合适时，可以使用环境变量：

（改名之前的 `QUIPU_*` 名称仍然有效；两者都设置时，`KNOTLOG_*` 优先。）

- `KNOTLOG_CTX_MAX` (4096) — Knotlog 注入的上下文的字节预算。优先于
  `.knotlog/config` 的 `ctx_max=`，而后者又优先于
  4096 的默认值——一次性覆盖用环境变量，
  想让设置在知识库迁到另一台机器后依然保留则用 config 中的 `ctx_max=`。
- `KNOTLOG_NUDGE_AFTER` (50) — 在提醒模型写下记忆之前的新增日志行数。
- `KNOTLOG_CHECKPOINT_AFTER` (1800) — 未修改的会话笔记在出现后续 git 活动后，
  经过多少秒会触发检查点提醒或阻止。
- `KNOTLOG_LOG_MAX` (262144) — `activity.log` 轮转为 `.log.1` 之前的大小。
- `KNOTLOG_HOOK=1` — 由适配器设置。它使错误以 0 退出，
  这样一个出故障的 Knotlog 永远不会阻塞你的会话。

### 机密关口（pre-commit）

`install` 默认会把知识库变成一个 Git 仓库（`--no-git` 可以选择不要），
并添加一次基线提交，以及一份用于再生机器状态的 `.gitignore`；
`init --git` 则按需做同样的事。已有的历史绝不会被提交进去，
已有的非仓库知识库绝不会被默认行为转换（传入 `--git` 才会提出请求），
缺少 git 身份只会被报告，不致命。只要知识库是一个仓库，
Knotlog 就会安装 `.githooks/pre-commit` 并把 `core.hooksPath` 指向它。此后每次
提交都会扫描*新增*的暂存行中常见的机密形态——AWS
`AKIA…`、OpenAI `sk-…`、GitHub `ghp_…`/`github_pat_…`、Slack `xox…`、Google
`AIza…`、`PRIVATE KEY` 块、`Bearer` 令牌、JWT，以及通用的
`api_key=`/`secret=`/`token=`/`password:` 赋值（`=` 或 `:` 均可）——并拒绝该提交，同时指出它发现问题的文件。如果 `PATH` 中有
外部的 `sir-tara` 扫描器，整个扫描就委托给它。手工编辑过的钩子
（没有 Knotlog 标记的那种）绝不会被覆盖。要强行提交：
`git commit --no-verify` 会跳过所有钩子，而
`KNOTLOG_SKIP_SECRET_SCAN=1 git commit …` 只为那一次提交跳过这道关口。

`knotlog help` 会列出所有命令；`knotlog help --tr` 以土耳其语打印同样的列表
（其他随附语言同理：`--es`、`--pt-br`、`--ja`、`--zh-cn`）。

## 10. 离开

如果 Knotlog 不适合你，你应该能毫无猜测地把机器还原。
卸载只会移除安装时放在你的知识库之外的东西：

```bash
knotlog uninstall --dry-run   # see what would go
knotlog uninstall             # remove the command from PATH
```

在 Windows 上，请改为在 PowerShell 中运行 `.\uninstall.ps1`（如果两种方式都装过，则两个都运行）——
它会移除 `%LOCALAPPDATA%\Knotlog\bin` 下的垫片，
以及它添加到你用户 `PATH` 中的条目。

**你的笔记绝不会被删除。** 知识库原封不动地留在原处，
命令会打印它的路径，以及仍留在其中的 Knotlog 文件。没有这个命令，
这些文件是惰性的——到那时知识库只是文件夹里的 Markdown，
你可以保留它、移动它，或者自己删除它。如果你想删除，卸载会给你
确切的那一行命令。

机器上的其他东西都没有被改动：Knotlog 从不编辑 shell 启动文件，
从不在知识库及它自己的命令垫片之外写入，也从不“回连”任何服务器。
