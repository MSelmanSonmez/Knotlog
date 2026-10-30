# Knotlog — ユーザーガイド

> この翻訳は機械支援によるもので、修正を歓迎します。

Knotlog をインストールすると、ボールトが作成されます。このガイドはその後の話です。
何が自動で行われ、何を自分の手でやり、どの疑問にどのコマンドが答えるのかを説明します。
インストール自体については [README](../README.ja.md) を参照してください。
セットアップウィザードには「スタイル」の手順 (トーン、装飾、フォルダ名) があり、あとから `knotlog tone` と `knotlog flair` で変更できます。`PATH` の前のほうに古い `knotlog` があると、インストールの要約と `knotlog doctor` が警告します。フックはそちらを実行するためです。

> **旧称 Quipu。** Knotlog は Quipu の新しい名前で、旧 `quipu` コマンドはなくなりました。旧名で作ったボールトがある場合は、`knotlog migrate` で変更内容をプレビューし、`knotlog migrate --apply` で書き込んでください。古い `quipu` フックコマンドも `knotlog` に書き換えられます。手で編集したブリッジブロックは更新されず (マーカー名だけが変更されます)、警告が表示されます。

まだ Knotlog をインストールしていない場合、ワンライナーは次のとおりです。

```bash
curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
```

検証済みのリリースを取得し、`knotlog install` に引き継ぎます。チェックアウトからのインストールや Windows については
[README](../README.ja.md) にも書かれています。

## 1. Knotlog があなたのためにすること

Knotlog は、コーディングエージェントが何をしたかを、1 つのフォルダ (ボールト) の中に Markdown で書き留めます。
Claude Code のセッションの前後では、次の 3 つのことが起こります。

- **作業中**、エージェントが読み書きしたすべてのファイルが、`.knotlog/activity.log` に 1 行ずつ追記されます。タイムスタンプ、イベント、ツール、パスです。
- **セッション終了時**、それらの行が Sessions フォルダの日付付きノートにまとめられ、検索インデックスが更新されます。
- **次のセッション開始時**、Knotlog は直近の活動、未解決のスレッド、アイデンティティの 1 行をモデルのコンテキストに出力します。これにより、エージェントは前回の出来事を知った状態で始まります。最初の行は常に現在の日付、時刻、曜日名です (`now: 2026-09-02 20:15 Wednesday`)。これがないと、セッションの見出しを書くモデルは時刻を推測するしかなく、推測はずれていきます。

データベースもネットワーク呼び出しもありません。すべてのファイルは、読んで、編集して、git にコミットできる Markdown です。
Knotlog は追記するだけで、あなたの文章を書き換えることはありません。

## 2. 日々の流れ

最初に混乱しやすいのは、この流れの一部が自動で動き、一部があなたの担当だという点です。その分担は次のとおりです。

**自動で動くもの** (Claude Code アダプタ。`<vault>/.claude/settings.json` にインストールされます)。

| タイミング | 実行されるもの | 効果 |
|---|---|---|
| セッション開始時 | `knotlog remember && knotlog context --json SessionStart` | 保留中のログ行がセッションノートになり、直近のメモリが注入される |
| プロンプトを送るたび | `knotlog context --json UserPromptSubmit` | 新しいログ行が十分たまると、モデルにメモリを書き留めるよう促す |
| `Edit`/`Write`/`NotebookEdit`/`Read` の後 | `knotlog capture` | `activity.log` に 1 行が静かに追記される |
| セッション終了時 | `knotlog remember && knotlog index` | セッションノートが書かれ、インデックスが更新される |

これが動くための条件は 2 つあります。`knotlog` が `PATH` 上にあること、そして Claude Code はフックの設定を起動時に 1 度だけ読むので、
**`settings.json` を変更したら必ず再起動すること**です。

**あなたの担当:**

1. 作業しながら、ボールトのフォルダにノートを書きます。Knotlog はそこに置いたものをインデックスしますが、ノートを勝手に作ることはありません。
2. セッションの終わりに、今日のセッションノートの振り返りブロックを埋めます。3 つの見出しを持つひな形が最初から用意されています。
   エージェントに埋めさせることもできます (`SessionStart` のコンテキストがそう依頼します) が、実際に埋めたかどうかは誰もチェックしません。
3. スレッドファイル (`Threads.md`) を最新に保ちます。まだ開いているもの、閉じたものを整理します。
4. 以前のセッションの内容が必要になったら、語り直す代わりに `knotlog search` を実行します。

Knotlog は機械的な台帳を担当します。意味を書くのは、あなたとモデルです。

## 3. フォルダ

`init` は 10 個のフォルダを作成します。以下の名前は英語レイアウトのものです。トルコ語のボールトではトルコ語の名前になり、`--plain` では ASCII の名前になります。
ここに強制されるものは何もありません。スキーマではなく習慣です。

| フォルダ | こんなときに書く |
|---|---|
| `📥 Inbox` | 考えが浮かんだが、まだどこに属するか決めたくないとき |
| `🗑️ Trash` | 受信箱の中で、生の素材 (貼り付け、断片、文字起こし) を投げ込むとき |
| `🎯 Command Center` | ダッシュボードに載せたいもの。今日の焦点、入口のリンク |
| `🗂️ Projects` | 1 つの進行中の作業に関するノート。プロジェクトごとにサブフォルダ 1 つ |
| `🧠 Knowledge` | プロジェクトと関係なく、数か月後にもう一度必要になるもの |
| `🛠️ Arsenal` | 再利用するツール、スクリプト、スニペット |
| `📆 Sessions` | 手で書くことはほとんどありません。`knotlog remember` が 1 日 1 ファイルでここに書きます |
| `🔮 Companion` | コンパニオンのペルソナと、それが持つアイデンティティのノート |
| `📦 Archive` | 完了した、または凍結したもので、目の前から退けたいもの |
| `📋 Templates` | その場で編集しないこと。`note.md`、`project.md`、`session.md` をコピーして使う |

Templates フォルダにはこの 3 つのひな形が同梱されており、**検索インデックスから除外されます**。これらはコピーするための形であって、探す対象の内容ではないからです。
ノート 3 つとテンプレート 3 つがあるボールトでは、インデックスされるのはノートだけです。

## 4. 手で入力するコマンド

以下はすべてボールトの中で実行します (どのサブフォルダでも構いません。Knotlog が上へたどって `.knotlog/` を見つけます)。

**`knotlog search <terms>`** — ノートを探します。

```
$ knotlog search taskbar
0.934	🧠 Knowledge/taskbar.md	Taskbar overflow	windows,ui
0.673	🧠 Knowledge/dpi.md	DPI notes	windows
```

**`knotlog links <path>`** — ノートが何とつながっているかを見ます。ボールトからの相対パスを渡してください。

```
$ knotlog links "🧠 Knowledge/dpi.md"
outgoing links
incoming links
🧠 Knowledge/taskbar.md
```

発リンクはそのノートに書かれた `[[wikilinks]]` で、被リンクはそのノートを指しているノートです。リンク先はフォールディングされず、文字列の完全一致で解決されます。
`[[dpi]]` (ファイル名の語幹) か、ボールトからの相対パス全体を書いてください。

**`knotlog digest`** — セッションの基準位置 (ウォーターマーク) に触れずに、1 日分の活動を要約します。`--dry-run` は書き込まずに表示し、
`--date YYYY-MM-DD` で日付を指定でき、ファイルはダンプフォルダに作られます。

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

**`knotlog doctor`** — ヘルスチェックです。セクション 7 を参照してください。

**`knotlog import FILE`** — 保存した会話のエクスポート (Claude のトランスクリプト、ChatGPT のエクスポート、または `role`/`content` を持つ JSONL) をセッションノートに変換します。

```
$ knotlog import /tmp/chat.jsonl --date 2026-08-29
wrote: 📆 Sessions/2026-08-29-import-chat.jsonl.md
```

**`knotlog plan <name> --proje <Project>`** — 計画ノートを、計画が置かれるべき場所 `<projects>/<Project>/<Plans>/<name>.md` に作成します。
ローカライズされたフロントマター付きテンプレートから作られ、`$EDITOR` が設定されていればそれで開きます。計画はメモリです。
ボールトの中に置くことで、次のセッションがそれを引き継げます。そのため、プロジェクトフォルダがない場合は自動作成せずエラーになり、
既存の計画が上書きされることもありません。プロジェクトフォルダの中から実行すれば `--proje` は自動で決まります。

```
$ knotlog plan roadmap --proje Knotlog
wrote: 🗂️ Projects/Knotlog/Plans/roadmap.md
```

**`knotlog tone [--list|<slug>]`** — トーンプリセットを表示または設定します。引数なしでは、どのソースが有効でその理由 (プリセットのスラッグか、
companion.md 自身の Tone セクションか、どちらでもないか) を表示します。`--list` は同梱の 9 つのプリセット
(Default、Professional、Friendly、Candid、Quirky、Efficient、Snarky、Teaching、Kaomoji) を一覧し、有効なものに印を付けます。
`<slug>` は `.knotlog/config` に `tone=<slug>` を書き込みます。companion.md には触れません。

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

**`knotlog index`** — インデックスを手動で更新します。フックはセッション終了時にこれを実行します。セッションの外でノートを追加した後は、自分で実行してください。
`--full` はすべてを再構築します。

```
$ knotlog index
# indexed 6 (reused 5, stale 1, dropped 0)
```

**`knotlog remember`** — セッション終了を待たず、今すぐセッションノートを書きます。`--git` を付けると、その後ボールトをコミットします。
付けなければ、Knotlog が自分でコミットすることはありません。

## 5. 自分のメモリを検索する

`search` はクエリをフォールディングし、BM25 でインデックスをスコアリングして、上位の行を TAB 区切りの列
(スコア、パス、タイトル、タグ) で表示します。既定では 10 行です。

- `--limit N` — 表示する行数。
- `--paths` — パスの列だけを 1 行ずつ表示します: `knotlog search dpi --paths`。
- `--brief` — ノートの約 120 バイトのスニペットを入れた列を 1 つ追加します。10 個のノートを開く代わりに、開くべき 2 つを選ぶのに使ってください。`--paths` とは併用できません。
- `--tag ui` / `--status paused` — フロントマターが一致しないノートをすべて除外します。ランキングのヒントではなくフィルタで、併用すると AND になります。

スコアはあなたのボールト内での相対値で、絶対値ではありません。小さなボールトでは、絞り込み後の一致がゼロ未満のスコアでも正しいノートであることがあります。

**フォールディングと、それがトルコ語で重要な理由。** インデックス作成の前と検索の前に、テキストは `.knotlog/config` の `fold=` に記録されたフォールドプロファイルを通ります。
トルコ語のボールトでは `fold=tr` になり、`İ ı ğ ş ç ö ü` が ASCII 形に畳み込まれるので、クエリとノートが途中で出会えます。

```
$ knotlog search "acik kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
$ knotlog search "açık kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
```

どちらの綴りでもノートが見つかります。`default` プロファイル (英語のボールトの既定) は ASCII の大文字小文字以外を畳み込まないので、そこでは `acik` では `açık` が見つかりません。
英語レイアウトのボールトでトルコ語を書く場合は、`.knotlog/config` に `fold=tr` を設定し、`knotlog index --full` を 1 度実行してください。新しいプロファイルでインデックスを作り直す必要があります。

フォールディングは意図的に不可逆です。`açık` と `acık` は同じキーになります。既知の制限が 1 つあります。`--tag` は引数を畳み込みますが、比較先は生のフロントマターのテキストなので、
`--tag istanbul` では `İstanbul` と書かれたタグは見つかりません。

## 6. スレッドとセッションノート

セッションをまたいで物語を運ぶファイルは 4 つあります。

**今日のセッションノート** (`📆 Sessions/YYYY-MM-DD.md`) は `remember` が書きます。上部は機械的な内容で、時間範囲、ツールの回数、触れたファイルです。
その下にあるのは、Knotlog が 1 度だけ追加し、以後は二度と触れないひな形です。

```
<!-- knotlog:reflect:start -->
### What changed in this session?

### Where did the work happen?

### Threads touched or continued

<!-- knotlog:reflect:end -->
```

これを埋めるのが仕事です。同じ日に 2 回目の `remember` を実行しても、そこに書かれた内容は上書きされません。このブロックが空の間、`SessionStart` はモデルに埋めるよう頼み、ファイルの名前も伝えます。
前日のブロックが空のまま残っていた場合は、次のセッションで 1 度だけ通知され、その後は通知されなくなります。

**`Threads.md`** (トルコ語のボールトでは `Konular.md`) はボールトのルートにあり、1 日を超えて続くストーリーを `### Active threads` と `### Closed threads` の下に保持します。
`knotlog context` はこれをすべてのセッションに戻します。つまりボールト内で最もレバレッジの大きいファイルであり、同時に最も安く腐らせてしまえるファイルでもあります。
短く保ってください。閉じたスレッドは先頭に残さず、下へ移します。

### ルールファイル

`init` はボールトのルートに **`Rules.md`** (トルコ語のボールトでは `Kurallar.md`) を作成します。ボールトで作業するすべてのエージェントが継承する、振る舞いの契約です。
同梱の既定には、Knotlog が譲れないと考える 4 つのブロックがあります。

- **承認ゲート** — 金銭の移動、外部へ出るメッセージ、削除、機密情報は、承認なしに越えられません。1 回の「はい」は、1 つのセッションの 1 つのタスクにだけ有効です。
- **ゼロレベルプロトコル** — 11 個の基本的な作業習慣 (契約された範囲、開始前の完了の定義、検証出力のファイルへの書き込み、「完了」と言う前に報告する 3 つのこと、論理的な 1 ステップにつき 1 コミット、セッション終了時の 3 行など) と、それぞれが存在する理由。
- **レシートルール** — コミット、更新されたファイル、ディスクに書かれた出力がレシートです。「完了」はレシートではありません。痕跡がなければ、仕事はなかったことになります。
- **記録の規律** — 新しい記録が古い記録に取って代わるときは、古いほうを退役させます。ボールトで古い名前を検索し、閉じるか更新してください。1 つの題材に生きたコピーを 2 つ残してはいけません。

このファイルは自由に編集してください。あなたのものであり、Knotlog が上書きすることはありません (もう一方の言語の名前で既にあるファイルがあっても、既存のファイルが優先されます)。
`knotlog context` は、スレッドのセクションの後に、このファイルの見出しをすべてのセッションに注入します。`ctx_max` が絞られているときは、スレッドブロックを切る前に、このセクション全体が先に落とされます。
`doctor` は同梱テンプレートを製品ファイルとして確認します。シードを編集するまでは、手書きのメモリファイルとして数えられません。そのため、できたてのボールトでも `doctor` はクリーンに終了します。
ここに書き込んだ時点で、セクション 7 で説明する必須のナラティブ集合に加わります。

ブリッジ (`AGENTS.md`/`CLAUDE.md`) には、セッションがうまく終わらなかったときにもストーリーを保つためのチェックポイントプロトコルがあります。
作業が終わったその瞬間に記録を書くこと。作業が途中で止まったら、どこで止まったかと次のステップを書くこと。
ユーザーが離れることをほのめかしたら、閉じる前に記録を完成させること。

Knotlog がこれらのファイルを書き換えることはありません。Knotlog 側からは、すべて追記のみです。

### ファクトファイル

`init` はボールトのルートに **`Facts.md`** (トルコ語のボールトでは `Gerçekler.md`) を作成します。外部のメモリサービスを使わずに保たれる、永続的なファクトの層です。
ルールは **1 行に 1 ファクト** です。すべての箇条書きの行は、3 つのタグのどれかで始まります。
`Decision:` (行われた選択とその理由。変更されるまで有効)、`Preference:` (好む作業の仕方)、`Convention:` (このボールトでの物事の進め方) です。
載せる基準は、数か月後にも真であり、かつ役に立つこと。**アイデンティティは該当し、ニュースは該当しません**。古くなるものは、代わりに `Threads.md` かセッションノートに属します。

このファイルは自由に編集してください。あなたのものであり、Knotlog が上書きすることはありません (もう一方の言語の名前で既にあるファイルがあっても、既存のファイルが優先されます)。
`knotlog context` は、ルールのセクションの後に、ファクトの行をすべてのセッションに注入します。同じ `ctx_max` の契約のもとで、予算が絞られたときはセクション全体が落とされ、スレッドブロックが切られることはありません。
手を加えていないシードは骨組みであって記録ではありません。最初の 1 行を書くまで、コンテキストはそれについて何も出力しません。
ファイルがあるときは、`doctor` がファクトの行数を示す `ok` 行を 1 つ表示します。この層ができる前に作られたボールトでは何も表示しません。

## 7. 何かおかしいとき

`knotlog doctor` は領域ごとにセクションを表示し、最後にサマリー行を出力します。警告だけなら終了コードは 0、失敗があったときだけ 1 です。

```
summary: 151 ok, 3 warn, 0 fail
```

**メモリのどの部分が監査されるのか。** ボールト内のすべてのファイルが同じ基準で扱われるわけではありません。**ライブメモリ** — AGENTS.md/CLAUDE.md のブリッジ、スレッドファイル、
ルールとコアのノート、そして `Last-Session.md` の最新の `## ` ブロック — は、次のセッションが立脚する指示です。その中のすべてのパスが解決できなければなりません。
**履歴メモリ** — `Last-Session.md` の古いブロック、ジャーナルノート、セッションフォルダ内のすべて — は記録です。もう存在しないフォルダに言及してもよく、パスの監査はそれを読みません。
新しいセッションブロックを追記すれば、古いブロックは自動的に履歴になります。

メモリファイルの名前はボールトの言語に従います (トルコ語のボールトでは `Son-Oturum.md`/`Kurallar.md`/`Çekirdek.md`/`Günlük.md`、
英語のボールトでは `Last-Session.md`/`Rules.md`/`Core.md`/`Journal.md`)。もう一方の言語の名前も、旧名のフォールバックとして受け付けられます。
ボールトに手書きのメモリファイルがある時点で、その集合は**必須**になります。ファイルが 1 つ欠けると、それが doctor の終了コードを 1 にする唯一のメモリ関連の指摘になります。
半端に移行されたメモリ層は、セッションが黙って注入を失う原因になるからです。

重要な行の読み方:

- **tools** の `fail` — `sh`、`sed`、`awk`、`grep`、`tr`、`git` が依存のすべてです。これが 1 つでも欠けると、Knotlog が止まる唯一の種類の故障になります。
- `warn index — index.tsv missing or stale (knotlog index)` — できたてのボールト、セッションの外でノートを編集した後、そして `remember` の直後 (インデックスがまだ見ていないセッションノートを書くため) には想定どおりです。
  `knotlog index` を実行してください。
- `warn threads — Threads.md has not been updated yet` — ファイルがないか、`Active/Closed threads` ブロックがまだ空です。ひな形だけでは解消せず、書かれた内容が必要です。
  新しいボールトでは想定どおりで、後の段階では催促です。
- `warn links — N wikilink target(s) not found` — `[[link]]` がどこも指していません。解決は文字列の完全一致なので、ノートの名前を変えるとリンクが宙に浮いたまま残ります。
- `warn links — … resolve to more than one note` — 2 つのノートが同じ名前を持っており、Knotlog はどちらを指しているのか推測することを拒否します。
- `fail memory — Last-Session.md | Son-Oturum.md not found` — 必須のメモリファイルの 1 つが、現在の名前でも旧名でも存在しません。
  終了コードは 1 になります。他のメモリ関連の指摘はすべて警告です。
- `warn paths — N quoted path(s) not found` — ライブメモリ内の `` `quoted/path` `` が、ボールト内のどこも指していません。見つからないパスは、件数の下に 1 行ずつ列挙されます。
  `~/`、絶対パス、URL、ドライブレター、グロブ、シェルのスニペットは判定されません。引数が後に続くボールト内のファイル (`./knotlog doctor`) はコマンドとして扱われ、
  フォルダ名だけ (`lib/`) は、その名前のフォルダがボールト内のどこかにあれば見つかったと見なされます。
- `warn paths — … point inside git-ignored territory` — パスは存在しますが git が追跡していません。このマシンでは動きますが、ボールトをクローンしたり移動したりした日に壊れます。
- `warn memory — N memory file(s) with uncommitted changes` — メモリの安全網は git です。編集されたがコミットされていないメモリには、それがありません。コミットしてください。
- `warn last session — the newest session block does not mention today's date` — 今日のコミットはあるのに、`Last-Session.md` の最新ブロックがそれより前に書かれています。
  今日の日付はブロック全体から検索されるので、日付をまたいだセッションは誤警告になりません。

- `ok claude hooks — installed (vault)` — アダプタは `<vault>/.claude/settings.json` にあります。これが通常のインストールの姿です。
  単なる `installed` は、代わりにグローバルの `~/.claude/settings.json` で見つかったことを意味します。
  `not installed` はどちらにもないことを意味し、セクション 2 の自動の流れは動いていません。
- `warn path — path contains OneDrive` / `locale is not UTF-8` — 絵文字のフォルダ名とフォールディングに対する、環境上のリスクです。どちらも通常のボールトは壊しません。

`doctor` は何も変更しません。報告されるものは、すべてあなたが実行するコマンドです。

## 8. フックなしで Knotlog を使う

フックの仕組みを持たないエージェントのために、あるいは流れを自分の手で握りたいときのために、自動の部分は 2 つのコマンドで置き換えられます。

- `knotlog capture --git` は、作業ツリーを最後のコミットと比較し、変更された Markdown ファイルごとに 1 行を追記します。`remember` の前に実行してください。
  状態を持たないので、間にコミットを挟まずに 2 回実行すると、同じファイルが 2 回記録されます。
- `knotlog context --bridge` は、フックが注入するはずのコンテキストを、`AGENTS.md` と `CLAUDE.md` の**両方**の
  `<!-- knotlog:context:start -->` ブロックに書き込みます。どちらのファイルを読むエージェントも同じメモリを見るので、
  あるエージェントでのセッションが、別のエージェントでのセッションの内容を引き継げます。

手動のセッションは次のようになります。`context --bridge` でブリッジファイルを更新し、エージェントにそのどちらかを読ませ、作業し、
そして `knotlog capture --git && knotlog remember && knotlog index` を実行します。

### Antigravity

Antigravity にはフックの仕組みがあるので、自動の流れが使えます。ボールトから実行してください。

```
knotlog setup antigravity --dry-run   # preview, writes nothing
knotlog setup antigravity             # writes .agents/hooks.json
```

セッション開始時、フックは `remember` を実行し、直近のコンテキストをシステムメッセージとして注入します。エージェントがターンを終えると、2 つ目のフックが
セッションノートが遅れていないかを確認し (30 分に 1 回まで)、遅れていればターンが終わる前にエージェントを書きに戻します。
内容が異なる既存の `.agents/hooks.json` が上書きされることはありません。同梱のもの (`adapters/antigravity/hooks.json`) を手でマージしてください。
その後、Antigravity を再起動します。詳細: [REFERENCE.md](REFERENCE.md#antigravity)。

### Devin Desktop (Windsurf) と OpenCode

どちらにも小さな記録用のフックが入ります。コンテキストは `AGENTS.md` のブリッジから届きます。ボールトから `knotlog setup windsurf` (または `devin`) と
`knotlog setup opencode` を実行してください。`--dry-run` でプレビューできます。`.devin/hooks.json` と `.opencode/plugins/knotlog.js` が書かれ、
内容が異なるファイルが上書きされることはありません。クライアントは自分の環境から `knotlog` を実行します (Devin Desktop はログインシェルを使います)。
そのため `knotlog` がその `PATH` 上にないと、フックは黙って何もしません。2026-10-25 に Linux で実機検証済みです (Devin Desktop 3.11.216、OpenCode 1.19.4)。Windows は未検証です。
詳細: [REFERENCE.md](REFERENCE.md#windsurf--devin-desktop)。

### MCP サーバーを接続する

`knotlog mcp` を使うと、MCP クライアントがフックなしでボールトを検索し、そのコンテキストを読めます。提供されるツールは 3 つです。
`knotlog_search` (クエリと任意の件数上限)、`knotlog_context`、`knotlog_note` (今日のセッションノートへの 1 行、`knotlog note` と同じ) です。
起動したフォルダからボールトを見つけるので、ボールトの中から登録してください。

```
claude mcp add knotlog -- knotlog mcp
```

`knotlog` が `PATH` 上にない場合は、代わりに絶対パスを指定してください。別のクライアントも、引数 `mcp` を付けた同じコマンドを実行できます。
ボールトの外で起動するサーバーには、`KNOTLOG_VAULT` にボールトのフォルダを設定します。詳細: [REFERENCE.md](REFERENCE.md#mcp-server)。

## 9. 設定項目

ボールトの設定は `.knotlog/config` に、単純な `key=value` の行として保存されます。`layout`、`lang`、`fold`、`user`、`companion`、`purpose`、`tone`、`flair`、`ctx_max` です。
`fold` を変更したら、その後に `knotlog index --full` が必要です。それ以外は次のコマンドから有効になります。`ctx_max` は `init` が書き込むことはありません。
既に使える既定値 (4096) があるので、上書きしたいときだけ手で行を追加してください。`doctor` は使っている値の出どころ (env/config/default) を報告し、
config の `ctx_max=` が正の整数でなければ警告します (無視されるだけで、致命的ではありません)。

**言語の選択。** Knotlog は English、Türkçe、Español、Português (Brasil)、日本語、简体中文 を話します。インストールウィザードで選ぶか、
`--lang <code>` (`en`、`tr`、`es`、`pt-br`、`ja`、`zh-cn`) を使うか、`.knotlog/config` の `lang=` で設定してください。
その言語にないものは英語にフォールバックします。英語とトルコ語以外の翻訳は機械支援によるもので、修正を歓迎します。

`tone` は同梱の 9 つのトーンプリセットから 1 つを選びます (`knotlog tone --list` で名前と説明を表示、`knotlog tone <slug>` で設定)。
指定したプリセットがボールトの言語に実際に存在するかぎり、Knotlog が注入するコンテキストの中で、companion.md 自身の `## Tone`/`## Üslup` セクションより優先されます。
未設定のままにするか、同梱されていないスラッグを設定すると、Knotlog は companion.md の Tone セクションにフォールバックします。これはプリセットが存在する前のボールトと同じ動作です。
`purpose` と同じく、`init` の間に `tone` を尋ねる対話的な質問はありません。あるのは `--tone <slug>` フラグだけです (`install` も受け付けます)。

`flair` はトーンの上に返信の装飾を加えます。`none` (既定)、`kaomoji`、`emoji` のいずれかです。`knotlog flair` で現在の値を表示し、`knotlog flair --list` で一覧を表示し、`knotlog flair <値>` で設定します。`init` と `install` も `--flair` を受け付けます。文面は 6 言語すべてに付属します。`none` 以外の装飾は、`kaomoji` トーンのプリセットの代わりになります。

既定値が合わないときの環境変数:

(リネーム前の `QUIPU_*` という名前も引き続き使えます。両方が設定されている場合は `KNOTLOG_*` が優先されます。)

- `KNOTLOG_CTX_MAX` (4096) — Knotlog が注入するコンテキストのバイト予算。`.knotlog/config` の `ctx_max=` より優先され、それが 4096 の既定値より優先されます。
  1 回限りの上書きには環境変数を、ボールトを別のマシンへ移しても残る設定には config の `ctx_max=` を使ってください。
- `KNOTLOG_NUDGE_AFTER` (50) — モデルにメモリを書くよう促すまでの、新しいログ行の数。
- `KNOTLOG_CHECKPOINT_AFTER` (1800) — 未更新のセッションノートに続く git の活動が、チェックポイントのリマインドまたはブロックを引き起こすまでの秒数。
- `KNOTLOG_LOG_MAX` (262144) — `activity.log` が `.log.1` にローテーションされるサイズ。
- `KNOTLOG_HOOK=1` — アダプタが設定します。エラーを終了コード 0 にするので、壊れた Knotlog があなたのセッションをブロックすることはありません。

### シークレットゲート (pre-commit)

`install` は既定でボールトを Git リポジトリにし (`--no-git` で無効化)、最初のコミット 1 つと、再生成されるマシン状態用の `.gitignore` を追加します。
`init --git` は必要に応じて同じことを行います。既存の履歴にコミットが追加されることはなく、リポジトリでない既存のボールトが既定で変換されることもありません (求めるには `--git` を渡します)。
git のアイデンティティがない場合は、致命的ではなく報告されます。ボールトがリポジトリであるときは常に、
Knotlog は `.githooks/pre-commit` をインストールし、`core.hooksPath` をそこに向けます。以後すべてのコミットで、ステージされた*追加*行が、よく知られたシークレットの形
(AWS の `AKIA…`、OpenAI の `sk-…`、GitHub の `ghp_…`/`github_pat_…`、Slack の `xox…`、Google の `AIza…`、`PRIVATE KEY` ブロック、`Bearer` トークン、JWT、一般的な `api_key=`/`secret=`/`token=`/`password:` の代入 (`=` でも `:` でも))
についてスキャンされ、見つかったファイルの名前を示してコミットが拒否されます。外部の `sir-tara` スキャナが `PATH` 上にあれば、スキャン全体がそちらに委ねられます。
手で編集されたフック (Knotlog のマーカーがないもの) が上書きされることはありません。それでもコミットするには、
`git commit --no-verify` がすべてのフックをスキップし、`KNOTLOG_SKIP_SECRET_SCAN=1 git commit …` はその 1 回のコミットについてだけ、このゲートをスキップします。

`knotlog help` はすべてのコマンドを一覧表示します。`knotlog help --tr` は同じ一覧をトルコ語で表示します (他の同梱言語も同様に動作します: `--es`、`--pt-br`、`--ja`、`--zh-cn`)。

## 10. 去るとき

Knotlog が合わなかった場合でも、推測なしにマシンを元に戻せるはずです。アンインストールが削除するのは、インストールがボールトの外に置いたものだけです。

```bash
knotlog uninstall --dry-run   # see what would go
knotlog uninstall             # remove the command from PATH
```

Windows では、代わりに PowerShell から `.\uninstall.ps1` を実行してください (両方の方法でインストールした場合は、両方実行してください)。
`%LOCALAPPDATA%\Knotlog\bin` の下のシムと、ユーザーの `PATH` に追加されたエントリが削除されます。

**あなたのノートが削除されることはありません。** ボールトはそのままの場所に残り、コマンドはそのパスと、まだ中にある Knotlog のファイルを表示します。
コマンドがなければそれらのファイルは何もせず、その時点でボールトはフォルダの中の Markdown にすぎません。保持しても、移動しても、自分で削除しても構いません。
削除したい場合は、アンインストールがそのための正確な 1 行を示します。

マシン上のほかのものは何も変更されていません。Knotlog はシェルの起動ファイルを編集せず、ボールトと自身のコマンドシムの外に書き込まず、外部に通信することもありません。
