# Knotlog — guia do usuário

> Esta tradução é assistida por máquina; correções são bem-vindas. O original em inglês é [GUIDE.md](GUIDE.md).

Você instalou o Knotlog e ele criou um cofre (vault). Este guia trata do que vem
depois: o que acontece sozinho, o que você faz à mão e qual comando responde a
qual pergunta. Para a instalação em si, veja o [README](../README.pt-BR.md).
O assistente de instalação tem uma etapa de Estilo (tom, enfeite, nomes das pastas) que você pode mudar depois com `knotlog tone` e `knotlog flair`. Se houver um `knotlog` mais antigo antes no seu `PATH`, o resumo da instalação e o `knotlog doctor` avisam, porque os hooks executam esse.

> **Antigo Quipu.** Knotlog é o novo nome do Quipu; o antigo comando `quipu` não existe mais. Se você tem um cofre criado com o nome antigo, execute `knotlog migrate` para ver as mudanças e `knotlog migrate --apply` para gravá-las; ele também reescreve os antigos comandos de hook `quipu` para `knotlog`. Um bloco de ponte que você editou à mão não é atualizado (só os marcadores são renomeados) e você recebe um aviso.

Se você ainda não instalou o Knotlog, o método de uma linha é:

```bash
curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
```

Ele baixa uma versão verificada e passa o controle para `knotlog install`; o
[README](../README.pt-BR.md) também cobre as instalações a partir de um checkout e o Windows.

## 1. O que o Knotlog faz por você

O Knotlog anota o que o seu agente de código fez, em Markdown, dentro de uma
única pasta — o cofre. Em torno de uma sessão do Claude Code, acontecem três
coisas:

- **Enquanto você trabalha**, cada arquivo que o agente lê ou grava é acrescentado
  como uma linha em `.knotlog/activity.log`: data e hora, evento, ferramenta, caminho.
- **Quando a sessão termina**, essas linhas são reunidas em uma nota datada na
  pasta de Sessões, e o índice de busca é atualizado.
- **Quando a próxima sessão começa**, o Knotlog devolve ao contexto do modelo a
  atividade recente, as threads abertas e uma linha de identidade — assim o
  agente já começa sabendo o que aconteceu da última vez. A primeiríssima linha é
  sempre a data, a hora e o dia da semana atuais (`now: 2026-09-02 20:15 Wednesday`) —
  sem ela, um modelo que escreve o título de uma sessão tem de adivinhar a hora,
  e os palpites vão se desviando.

Não há banco de dados nem chamada de rede. Cada arquivo é Markdown que você pode
ler, editar e versionar no git. O Knotlog só acrescenta; nunca reescreve a sua prosa.

## 2. O ciclo diário

O que mais confunde no começo: uma parte do ciclo roda sozinha e outra é sua.
Veja a divisão.

**Roda sozinho** (o adaptador do Claude Code, instalado em
`<vault>/.claude/settings.json`):

| Quando | O que roda | Efeito |
|---|---|---|
| A sessão começa | `knotlog remember && knotlog context --json SessionStart` | as linhas pendentes do log viram uma nota de sessão; a memória recente é injetada |
| A cada prompt que você envia | `knotlog context --json UserPromptSubmit` | depois de linhas novas suficientes no log, o modelo é lembrado de anotar a memória |
| Depois de `Edit`/`Write`/`NotebookEdit`/`Read` | `knotlog capture` | uma linha acrescentada ao `activity.log`, em silêncio |
| A sessão termina | `knotlog remember && knotlog index` | a nota de sessão é escrita e o índice é atualizado |

Duas condições para isso funcionar: o `knotlog` precisa estar no seu `PATH`, e o
Claude Code lê a configuração de hooks uma única vez, na inicialização —
**reinicie-o depois de qualquer mudança em `settings.json`**.

**Fica por sua conta:**

1. Escreva notas nas pastas do cofre ao longo do caminho. O Knotlog indexa o que
   você coloca ali; ele não inventa notas.
2. No fim de uma sessão, preencha o bloco de reflexão da nota de sessão de hoje.
   O esqueleto já está lá, com três títulos. O agente pode preenchê-lo — o
   contexto do `SessionStart` pede isso a ele — mas ninguém verifica se ele
   preencheu.
3. Mantenha o arquivo de threads (`Threads.md`) em dia: o que ainda está aberto,
   o que foi encerrado.
4. Execute `knotlog search` quando precisar de algo de uma sessão anterior, em vez
   de recontar tudo.

O Knotlog mantém o registro mecânico. O significado é escrito por você e pelo modelo.

## 3. As pastas

`init` cria dez pastas. Os nomes abaixo são do layout em inglês; um cofre em
turco recebe nomes em turco, e `--plain` recebe nomes em ASCII. Nada aqui é
imposto — é um hábito, não um esquema.

| Pasta | Escreva aqui quando… |
|---|---|
| `📥 Inbox` | um pensamento chega e você ainda não quer decidir onde ele fica |
| `🗑️ Trash` | despejar material bruto dentro da caixa de entrada — colagens, fragmentos, transcrições |
| `🎯 Command Center` | ele pertence ao painel: o foco de hoje, links de entrada |
| `🗂️ Projects` | a nota trata de um trabalho ativo — uma subpasta por projeto |
| `🧠 Knowledge` | você vai querer de novo daqui a meses, independentemente de qualquer projeto |
| `🛠️ Arsenal` | é uma ferramenta, um script ou um trecho para reutilizar |
| `📆 Sessions` | quase nunca à mão — `knotlog remember` escreve aqui, um arquivo por dia |
| `🔮 Companion` | a persona do companheiro e as notas de identidade que ele carrega |
| `📦 Archive` | a coisa está concluída ou congelada, e você quer tirá-la do caminho |
| `📋 Templates` | nunca edite no lugar — copie `note.md`, `project.md` ou `session.md` para fora |

A pasta Templates vem com esses três esqueletos e é **excluída do índice de
busca**: são formas para copiar, não conteúdo para encontrar. Um cofre com três
notas e três modelos indexa as notas, não os modelos.

## 4. Comandos que você digita

Tudo abaixo roda dentro do cofre (qualquer subpasta serve — o Knotlog sobe os
diretórios até achar o `.knotlog/`).

**`knotlog search <termos>`** — encontra uma nota.

```
$ knotlog search taskbar
0.934	🧠 Knowledge/taskbar.md	Taskbar overflow	windows,ui
0.673	🧠 Knowledge/dpi.md	DPI notes	windows
```

**`knotlog links <caminho>`** — mostra a que uma nota se conecta. Informe o
caminho relativo ao cofre.

```
$ knotlog links "🧠 Knowledge/dpi.md"
outgoing links
incoming links
🧠 Knowledge/taskbar.md
```

Os links de saída são os `[[wikilinks]]` escritos nessa nota; os de entrada são
as notas que apontam para ela. Os alvos dos links são resolvidos por string
exata, sem normalização — escreva `[[dpi]]` (o nome do arquivo sem extensão) ou o
caminho completo relativo ao cofre.

**`knotlog digest`** — resume um dia de atividade sem mexer na marca d'água da
sessão. `--dry-run` imprime em vez de gravar, `--date YYYY-MM-DD` escolhe um dia,
e o arquivo vai para a pasta de despejo.

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

**`knotlog doctor`** — a verificação de saúde. Veja a seção 7.

**`knotlog import FILE`** — transforma uma exportação de conversa salva
(transcrição do Claude, exportação do ChatGPT ou JSONL com `role`/`content`) em
uma nota de sessão.

```
$ knotlog import /tmp/chat.jsonl --date 2026-08-29
wrote: 📆 Sessions/2026-08-29-import-chat.jsonl.md
```

**`knotlog plan <nome> --proje <Project>`** — abre uma nota de plano onde os
planos devem ficar: `<projects>/<Project>/<Plans>/<nome>.md`, criada a partir do
modelo localizado com front matter e aberta no `$EDITOR`, se definido. Planos
são memória — mantê-los dentro do cofre é o que faz a próxima sessão herdá-los;
por isso uma pasta de projeto inexistente é um erro, nunca criada
automaticamente, e um plano existente nunca é sobrescrito. Execute o comando de
dentro de uma pasta de projeto e o `--proje` se resolve sozinho.

```
$ knotlog plan roadmap --proje Knotlog
wrote: 🗂️ Projects/Knotlog/Plans/roadmap.md
```

**`knotlog tone [--list|<slug>]`** — mostra ou define o preset de tom. Sem
argumentos, mostra qual fonte está ativa e por quê (um slug de preset, a seção
Tone do próprio companion.md, ou nenhum); `--list` mostra os nove presets
incluídos (Default, Professional, Friendly, Candid, Quirky, Efficient, Snarky,
Teaching, Kaomoji) e marca o ativo; `<slug>` grava `tone=<slug>` em
`.knotlog/config` — nunca mexe no companion.md.

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

**`knotlog index`** — atualiza o índice à mão. Os hooks fazem isso no fim da
sessão; execute você mesmo depois de adicionar notas fora de uma sessão. `--full`
reconstrói tudo.

```
$ knotlog index
# indexed 6 (reused 5, stale 1, dropped 0)
```

**`knotlog remember`** — escreve a nota de sessão agora, em vez de no fim da
sessão. Acrescente `--git` para fazer commit do cofre depois; sem ele, o Knotlog
nunca faz commit.

## 5. Buscando na sua própria memória

`search` normaliza a consulta, pontua o índice com BM25 e imprime as melhores
linhas em colunas separadas por TAB: pontuação, caminho, título, tags. Dez linhas
por padrão.

- `--limit N` — quantas linhas.
- `--paths` — só a coluna do caminho, uma por linha: `knotlog search dpi --paths`.
- `--brief` — uma coluna extra com um trecho de ~120 bytes da nota. Use para
  escolher quais duas notas abrir em vez de abrir dez. Não pode ser combinado com
  `--paths`.
- `--tag ui` / `--status paused` — descartam toda nota cujo frontmatter não
  corresponde. São filtros, não dicas de ranqueamento; combinados, valem como E.

As pontuações são relativas ao seu cofre, não absolutas — num cofre pequeno, uma
correspondência filtrada pode pontuar abaixo de zero e ainda assim ser a nota certa.

**Normalização, e por que ela importa para o turco.** Antes de indexar e antes de
buscar, o texto passa por um perfil de normalização registrado como `fold=` em
`.knotlog/config`. Um cofre em turco recebe `fold=tr`: `İ ı ğ ş ç ö ü` se reduzem
às formas ASCII, de modo que a consulta e a nota se encontram no meio do caminho.

```
$ knotlog search "acik kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
$ knotlog search "açık kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
```

As duas grafias encontram a nota. O perfil `default` — o que um cofre em inglês
recebe — não normaliza nada além da caixa ASCII, então nele `acik` não encontra
`açık`. Se você escreve turco num cofre com layout em inglês, defina `fold=tr` em
`.knotlog/config` e execute `knotlog index --full` uma vez; o índice precisa ser
reconstruído com o novo perfil.

A normalização perde informação de propósito: `açık` e `acık` se reduzem à mesma
chave. Uma lacuna conhecida: `--tag` normaliza o argumento, mas o compara com o
texto bruto do frontmatter, então `--tag istanbul` não encontra uma tag escrita
`İstanbul`.

## 6. Threads e notas de sessão

Quatro arquivos levam a história de uma sessão para a outra.

**A nota de sessão de hoje** (`📆 Sessions/YYYY-MM-DD.md`) é escrita por `remember`.
O topo é mecânico — intervalo de tempo, contagem de ferramentas, arquivos tocados.
Abaixo dele há um esqueleto que o Knotlog adiciona uma vez e nunca mais toca:

```
<!-- knotlog:reflect:start -->
### What changed in this session?

### Where did the work happen?

### Threads touched or continued

<!-- knotlog:reflect:end -->
```

Preenchê-lo é o seu trabalho. Um segundo `remember` no mesmo dia não sobrescreve
o que está escrito ali. Enquanto o bloco estiver vazio, o `SessionStart` pede ao
modelo que o preencha e informa o arquivo; se o bloco de ontem ficou vazio, a
próxima sessão é avisada uma vez e depois o aviso é descartado.

**`Threads.md`** (`Konular.md` em um cofre turco) fica na raiz do cofre e guarda
as histórias que duram mais de um dia, sob `### Active threads` e `### Closed threads`.
O `knotlog context` o devolve a cada sessão, o que faz dele o arquivo de maior
alavancagem do cofre — e o mais barato de deixar apodrecer. Mantenha-o curto; uma
thread que foi encerrada deve descer, não ficar no topo.

### O arquivo de regras

`init` cria **`Rules.md`** (`Kurallar.md` em um cofre turco) na raiz do cofre —
um contrato de comportamento que todo agente que trabalha no cofre herda. O
padrão incluído traz quatro blocos que o Knotlog considera inegociáveis:

- **Portões de aprovação** — movimentação de dinheiro, mensagens enviadas para
  fora, exclusão e segredos nunca são cruzados sem aprovação; um sim vale para
  uma tarefa em uma sessão.
- **Protocolos de nível zero** — onze hábitos básicos de trabalho (escopo do
  contrato, uma definição de pronto antes de começar, gravar a saída da
  verificação em um arquivo, as três coisas a informar antes de dizer "pronto",
  um commit por passo lógico, três linhas no fim da sessão, e mais), cada um com
  o motivo de existir.
- **A regra do recibo** — um commit, um arquivo atualizado, uma saída gravada em
  disco é um recibo; "pronto" não é. Sem rastro, sem trabalho.
- **Disciplina de registro** — quando um registro novo substitui um antigo,
  aposente o antigo: procure o nome antigo no cofre, feche-o ou atualize-o; nunca
  deixe duas cópias vivas do mesmo assunto.

Edite o arquivo à vontade — ele é seu; o Knotlog nunca o sobrescreve (um arquivo
existente prevalece mesmo sob o nome do outro idioma). O `knotlog context` injeta
os títulos do arquivo em toda sessão, depois da seção de threads; um `ctx_max`
apertado descarta esta seção inteira antes de chegar a cortar o bloco de threads.
O `doctor` verifica os modelos incluídos entre os arquivos do produto. Enquanto
você não editar o arquivo inicial, ele não conta como um arquivo de memória
escrito à mão — assim um cofre novo ainda sai limpo do `doctor`; no momento em
que você escreve nele, ele entra no conjunto narrativo obrigatório descrito na
seção 7.

A ponte (`AGENTS.md`/`CLAUDE.md`) traz o protocolo de ponto de controle que
mantém a história viva quando as sessões terminam mal: escreva o registro no
instante em que o trabalho acaba, não no fim da sessão; quando o trabalho para no
meio, escreva onde parou e o próximo passo; quando o usuário der a entender que
vai sair, termine o registro antes de encerrar.

Nenhum desses arquivos é reescrito pelo Knotlog. Todos são somente-acréscimo do lado dele.

### O arquivo de fatos

`init` cria **`Facts.md`** (`Gerçekler.md` em um cofre turco) na raiz do cofre —
a camada de fatos persistentes, mantida sem nenhum serviço de memória externo. A
regra é **uma linha, um fato**: cada linha de lista começa com uma de três tags —
`Decision:` (uma escolha feita e seu motivo, válida até ser mudada),
`Preference:` (como você gosta de trabalhar), `Convention:` (como as coisas
funcionam neste cofre). O critério de entrada: uma linha precisa continuar
verdadeira e útil daqui a meses — **identidade entra, notícia não**; tudo o que
envelhece pertence ao `Threads.md` ou às notas de sessão.

Edite o arquivo à vontade — ele é seu; o Knotlog nunca o sobrescreve (um arquivo
existente prevalece mesmo sob o nome do outro idioma). O `knotlog context` injeta
as linhas de fatos em toda sessão, depois da seção de regras, sob o mesmo
contrato do `ctx_max`: um orçamento apertado descarta a seção inteira e nunca
corta o bloco de threads. Um arquivo inicial intocado é o esqueleto, não um
registro — o contexto fica quieto sobre ele até você escrever a primeira linha.
O `doctor` imprime uma linha `ok` com a contagem de linhas de fatos quando o
arquivo existe e fica em silêncio em cofres anteriores a essa camada.

## 7. Quando algo parece errado

`knotlog doctor` imprime uma seção por área e uma linha de resumo. Ele sai com 0
quando há apenas avisos, e com 1 somente quando algo falhou.

```
summary: 151 ok, 3 warn, 0 fail
```

**Que parte da sua memória é auditada?** Nem todo arquivo de um cofre é cobrado
com o mesmo rigor. A **memória viva** — as pontes AGENTS.md/CLAUDE.md, o arquivo
de threads, as notas de regras e de núcleo, e o bloco `## ` mais novo de
`Last-Session.md` — é a instrução sobre a qual a próxima sessão vai se apoiar;
todo caminho dentro dela precisa resolver. A **memória histórica** — os blocos
mais antigos de `Last-Session.md`, a nota de diário, tudo sob a pasta de
sessões — é um registro; ela tem o direito de citar pastas que não existem mais,
e a auditoria de caminhos nunca a lê. Acrescente um novo bloco de sessão e o
antigo vira histórico automaticamente.

Os nomes dos arquivos de memória seguem o idioma do cofre (`Son-Oturum.md`/`Kurallar.md`/
`Çekirdek.md`/`Günlük.md` em um cofre turco, `Last-Session.md`/`Rules.md`/
`Core.md`/`Journal.md` em um cofre em inglês), e o nome do outro idioma é aceito
como alternativa legada. No momento em que o seu cofre tem um arquivo de memória
escrito à mão, esse conjunto passa a ser **obrigatório**: um arquivo ausente é o
único achado de memória que leva o código de saída do doctor a 1 — uma camada de
memória migrada pela metade é como as sessões perdem as injeções em silêncio.

Como ler as linhas que importam:

- `fail` em **tools** — `sh`, `sed`, `awk`, `grep`, `tr`, `git` são toda a lista
  de dependências. A falta de um deles é o único tipo de quebra que impede o Knotlog.
- `warn index — index.tsv missing or stale (knotlog index)` — esperado num cofre
  novo, depois de editar notas fora de uma sessão e logo depois de `remember` —
  que escreve uma nota de sessão que o índice ainda não viu. Execute `knotlog index`.
- `warn threads — Threads.md has not been updated yet` — o arquivo não existe, ou
  o bloco `Active/Closed threads` ainda está vazio. O esqueleto sozinho não
  resolve; conteúdo escrito, sim. Esperado num cofre novo, um lembrete mais tarde.
- `warn links — N wikilink target(s) not found` — um `[[link]]` aponta para o
  nada. A resolução é por string exata, então uma nota renomeada deixa um link
  pendente para trás.
- `warn links — … resolve to more than one note` — duas notas têm o mesmo nome e
  o Knotlog se recusa a adivinhar qual você quis dizer.
- `fail memory — Last-Session.md | Son-Oturum.md not found` — um dos arquivos de
  memória obrigatórios não existe nem sob o nome atual nem sob o legado. Código
  de saída 1; todos os outros achados de memória são avisos.
- `warn paths — N quoted path(s) not found` — um `` `quoted/path` `` na sua
  memória viva aponta para algo que não existe no cofre. Cada caminho ausente é
  listado em sua própria linha abaixo da contagem. `~/`, caminhos absolutos, URLs,
  letras de unidade, globs e trechos de shell nunca são julgados; um arquivo do
  cofre seguido de argumentos (`./knotlog doctor`) é um comando, e um nome de
  pasta solto (`lib/`) conta como encontrado se existir uma pasta com esse nome
  em qualquer lugar do cofre.
- `warn paths — … point inside git-ignored territory` — o caminho existe, mas o
  git não o rastreia: funciona nesta máquina e quebra no dia em que o cofre for
  clonado ou movido.
- `warn memory — N memory file(s) with uncommitted changes` — a rede de segurança
  da sua memória é o git; memória editada mas sem commit não tem nenhuma. Faça o commit.
- `warn last session — the newest session block does not mention today's date` —
  existe um commit de hoje, mas o bloco mais novo de `Last-Session.md` foi escrito
  antes. A data de hoje é procurada no bloco inteiro, então uma sessão que
  atravessou a meia-noite não é um falso alarme.

- `ok claude hooks — installed (vault)` — o adaptador está em
  `<vault>/.claude/settings.json`. É assim que uma instalação normal aparece.
  `installed` simples significa que foi encontrado no `~/.claude/settings.json`
  global. `not installed` significa que nenhum dos dois existe, e o ciclo
  automático da seção 2 não está rodando.
- `warn path — path contains OneDrive` / `locale is not UTF-8` — riscos do
  ambiente para nomes de pasta com emoji e para a normalização. Nenhum dos dois
  quebra um cofre normal.

O `doctor` não modifica nada. Tudo o que ele relata é um comando para você executar.

## 8. Usando o Knotlog sem hooks

Para agentes sem superfície de hooks — ou quando você quer o ciclo sob a sua
própria mão — dois comandos substituem a parte automática:

- `knotlog capture --git` compara a árvore de trabalho com o último commit e
  acrescenta uma linha por arquivo Markdown alterado. Execute-o antes de
  `remember`. Ele não guarda estado: execute duas vezes sem fazer commit no meio
  e os mesmos arquivos são registrados duas vezes.
- `knotlog context --bridge` grava o contexto que os hooks injetariam em um bloco
  `<!-- knotlog:context:start -->` em **ambos**, `AGENTS.md` e `CLAUDE.md`.
  Qualquer agente que leia um dos dois vê a mesma memória — é assim que uma
  sessão em um agente retoma o que uma sessão em outro fez.

Uma sessão manual fica assim: atualize os arquivos de ponte com `context --bridge`
e deixe o agente ler um deles, trabalhe, depois execute
`knotlog capture --git && knotlog remember && knotlog index`.

### Antigravity

O Antigravity tem uma superfície de hooks, então recebe o ciclo automático. A
partir do cofre:

```
knotlog setup antigravity --dry-run   # preview, writes nothing
knotlog setup antigravity             # writes .agents/hooks.json
```

No início da sessão, o hook executa `remember` e injeta o contexto recente como
mensagem de sistema. Quando o agente termina um turno, um segundo hook verifica
se a nota de sessão ficou para trás (no máximo uma vez a cada 30 minutos) e, em
caso afirmativo, manda o agente de volta para escrevê-la antes de o turno acabar.
Um `.agents/hooks.json` existente que seja diferente nunca é sobrescrito; mescle
à mão o arquivo incluído (`adapters/antigravity/hooks.json`). Reinicie o
Antigravity depois. Detalhes: [REFERENCE.md](REFERENCE.md#antigravity).

### Devin Desktop (Windsurf) e OpenCode

Os dois recebem um pequeno hook de registro; o contexto deles vem da ponte
`AGENTS.md`. A partir do cofre, execute `knotlog setup windsurf` (ou `devin`) e
`knotlog setup opencode`; `--dry-run` mostra uma prévia. Eles gravam
`.devin/hooks.json` e `.opencode/plugins/knotlog.js`, e nunca sobrescrevem um
arquivo diferente. O cliente executa `knotlog` a partir do próprio ambiente (o
Devin Desktop usa o seu shell de login), então o `knotlog` precisa estar nesse
`PATH`, ou o hook não faz nada, em silêncio. Verificado ao vivo no Linux em
2026-10-25 (Devin Desktop 3.11.216, OpenCode 1.19.4); o Windows não foi
verificado. Detalhes: [REFERENCE.md](REFERENCE.md#windsurf--devin-desktop).

### Conectando o servidor MCP

`knotlog mcp` permite que um cliente MCP busque no cofre e leia o seu contexto
sem hooks. Ele oferece três ferramentas: `knotlog_search` (uma consulta e um
limite opcional), `knotlog_context` e `knotlog_note` (uma linha na nota de sessão
de hoje, igual a `knotlog note`). Ele encontra o cofre a partir da pasta em que
é iniciado, então registre-o de dentro do cofre:

```
claude mcp add knotlog -- knotlog mcp
```

Se o `knotlog` não estiver no seu `PATH`, informe o caminho absoluto. Outro
cliente pode executar o mesmo comando com o argumento `mcp`; para um servidor
iniciado fora do cofre, defina `KNOTLOG_VAULT` com a pasta do cofre. Detalhes:
[REFERENCE.md](REFERENCE.md#mcp-server).

## 9. Ajustes

As configurações do cofre ficam em `.knotlog/config` como linhas simples
`chave=valor`: `layout`, `lang`, `fold`, `user`, `companion`, `purpose`, `tone`, `flair`,
`ctx_max`. Mudar `fold` exige `knotlog index --full` depois; as outras valem a
partir do próximo comando. O `ctx_max` nunca é gravado pelo `init` — ele já tem
um padrão que funciona (4096), então acrescente a linha à mão só se quiser
substituí-lo; o `doctor` informa de onde veio o valor que ele está usando
(env/config/default) e avisa se um `ctx_max=` da config não for um inteiro
positivo (ignorado, não fatal).

**Escolhendo um idioma.** O Knotlog fala English, Türkçe, Español, Português
(Brasil), 日本語 e 简体中文. Escolha um no assistente de instalação, com
`--lang <código>` (`en`, `tr`, `es`, `pt-br`, `ja`, `zh-cn`), ou definindo
`lang=` em `.knotlog/config`; o que faltar no seu idioma volta para o inglês. As
traduções que não são em inglês nem em turco são assistidas por máquina, e
correções são bem-vindas.

`tone` escolhe um dos nove presets de tom incluídos (`knotlog tone --list` mostra
nome + descrição, `knotlog tone <slug>` o define) — ele prevalece sobre a seção
`## Tone`/`## Üslup` do próprio companion.md no contexto que o Knotlog injeta,
sempre que o preset nomeado realmente existe para o idioma do cofre. Deixe-o sem
definir, ou defina um slug que não existe, e o Knotlog volta para a seção Tone do
companion.md — o mesmo comportamento que um cofre tinha antes de existirem
presets. Como `purpose`, não há pergunta interativa para `tone` durante o `init`;
só a flag `--tone <slug>` (também aceita pelo `install`).

`flair` acrescenta um enfeite às respostas por cima do tom: `none` (padrão), `kaomoji` ou `emoji`. `knotlog flair` mostra o valor, `knotlog flair --list` lista as opções e `knotlog flair <valor>` define; `init` e `install` também aceitam `--flair`. Os textos vêm nos seis idiomas. Qualquer enfeite diferente de `none` substitui a predefinição de tom `kaomoji`.

Variáveis de ambiente, quando os padrões não servem:

(Os nomes `QUIPU_*` anteriores à mudança de nome ainda funcionam; quando ambos estão definidos, `KNOTLOG_*` vence.)

- `KNOTLOG_CTX_MAX` (4096) — orçamento em bytes do contexto que o Knotlog injeta.
  Tem prioridade sobre o `ctx_max=` do `.knotlog/config`, que tem prioridade
  sobre o padrão 4096 — use a variável de ambiente para uma substituição pontual,
  ou `ctx_max=` na config para um ajuste que sobrevive à mudança do cofre para
  outra máquina.
- `KNOTLOG_NUDGE_AFTER` (50) — linhas novas no log antes de o modelo ser
  incentivado a anotar a memória.
- `KNOTLOG_CHECKPOINT_AFTER` (1800) — segundos antes de uma nota de sessão não
  modificada, com atividade posterior no git, disparar um lembrete ou bloqueio
  de ponto de controle.
- `KNOTLOG_LOG_MAX` (262144) — tamanho do `activity.log` antes de ele rodar para `.log.1`.
- `KNOTLOG_HOOK=1` — definida pelos adaptadores. Faz os erros saírem com 0, de
  modo que um Knotlog quebrado nunca bloqueia a sua sessão.

### O portão de segredos (pre-commit)

O `install` faz do cofre um repositório Git por padrão (`--no-git` desativa) e
adiciona um commit-base mais um `.gitignore` para o estado de máquina
regenerado; `init --git` faz o mesmo sob demanda. Um histórico existente nunca
recebe commits, um cofre existente que não seja repositório nunca é convertido
pelo padrão (passe `--git` para pedir isso), e a falta de identidade git é
relatada, não fatal. Sempre que o cofre é um repositório, o Knotlog instala
`.githooks/pre-commit` e aponta `core.hooksPath` para ele. A cada commit, ele
então examina as linhas *adicionadas* no stage em busca de formatos conhecidos de
segredo — AWS `AKIA…`, OpenAI `sk-…`, GitHub `ghp_…`/`github_pat_…`, Slack
`xox…`, Google `AIza…`, blocos `PRIVATE KEY`, tokens `Bearer`, JWTs e
atribuições genéricas como `api_key=`/`secret=`/`token=`/`password:` (com `=` ou `:`) — e rejeita o commit, apontando o arquivo em que
encontrou. Se um scanner externo `sir-tara` estiver no seu `PATH`, a varredura
inteira é delegada a ele. Um hook editado à mão (sem o marcador do Knotlog) nunca
é sobrescrito. Para fazer o commit mesmo assim: `git commit --no-verify` pula
todos os hooks, e `KNOTLOG_SKIP_SECRET_SCAN=1 git commit …` pula só este portão
naquele commit.

`knotlog help` lista todos os comandos; `knotlog help --tr` imprime a mesma lista
em turco (os outros idiomas incluídos funcionam do mesmo jeito: `--es`, `--pt-br`, `--ja`, `--zh-cn`).

## 10. Indo embora

Se o Knotlog não é para você, você deve poder ter a sua máquina de volta sem
adivinhação. O uninstall remove apenas o que o install colocou fora do seu cofre:

```bash
knotlog uninstall --dry-run   # see what would go
knotlog uninstall             # remove the command from PATH
```

No Windows, execute `.\uninstall.ps1` no PowerShell em vez disso (ou também, se
você instalou das duas maneiras) — ele remove os atalhos em
`%LOCALAPPDATA%\Knotlog\bin` e a entrada que adicionou ao `PATH` do seu usuário.

**Suas notas nunca são apagadas.** O cofre fica exatamente onde está, e o comando
imprime o caminho dele junto com os arquivos do Knotlog que continuam lá dentro.
Esses arquivos ficam inertes sem o comando — nesse ponto o cofre é só Markdown em
pastas, e você pode guardá-lo, movê-lo ou apagá-lo você mesmo. O uninstall mostra
a linha exata para apagá-lo, se for isso que você quer.

Mais nada na sua máquina foi alterado: o Knotlog nunca edita arquivos de
inicialização do shell, nunca grava fora do cofre e do seu próprio atalho de
comando, e nunca envia dados a ninguém.
