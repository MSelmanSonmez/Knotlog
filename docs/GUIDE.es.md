# Knotlog — guía de usuario

*Esta es una traducción asistida por máquina de [GUIDE.md](GUIDE.md); la versión en inglés es la referencia y las correcciones son bienvenidas.*

Instalaste Knotlog y creó una bóveda. Esta guía es lo que viene después: qué
ocurre por sí solo, qué haces tú a mano y qué comando responde a cada pregunta.
Para la instalación en sí, consulta el [README](../README.es.md).
El asistente de instalación tiene un paso de Estilo (tono, adorno, nombres de carpetas) que puedes cambiar después con `knotlog tone` y `knotlog flair`. Si hay un `knotlog` más antiguo antes en tu `PATH`, el resumen de la instalación y `knotlog doctor` te avisan, porque los hooks ejecutan ese.

> **Antes llamado Quipu.** Knotlog es el nuevo nombre de Quipu; el antiguo comando `quipu` ya no existe. Si tienes una bóveda creada con el nombre antiguo, ejecuta `knotlog migrate` para previsualizar los cambios y `knotlog migrate --apply` para escribirlos; también reescribe los antiguos comandos de hook `quipu` como `knotlog`. Un bloque puente que hayas editado a mano no se refresca (solo se renombran sus marcadores) y recibes un aviso.

Si aún no has instalado Knotlog, el método de una línea es:

```bash
curl -fsSL https://raw.githubusercontent.com/MSelmanSonmez/Knotlog/main/install.sh | sh
```

Descarga una versión verificada y cede el control a `knotlog install`; el
[README](../README.es.md) también cubre las instalaciones desde un checkout y Windows.

## 1. Qué hace Knotlog por ti

Knotlog anota lo que hizo tu agente de programación, en Markdown, dentro de una
sola carpeta — la bóveda. En torno a una sesión de Claude Code ocurren tres cosas:

- **Mientras trabajas**, cada archivo que el agente lee o escribe se añade como
  una línea a `.knotlog/activity.log`: marca de tiempo, evento, herramienta, ruta.
- **Cuando termina la sesión**, esas líneas se pliegan en una nota con fecha
  dentro de la carpeta de sesiones, y se refresca el índice de búsqueda.
- **Cuando empieza la siguiente sesión**, Knotlog imprime de vuelta en el
  contexto del modelo la actividad reciente, los hilos abiertos y una línea de
  identidad — para que el agente abra sabiendo lo que pasó la última vez. La
  primerísima línea es siempre la fecha, la hora y el nombre del día de la
  semana actuales (`now: 2026-09-02 20:15 Wednesday`) — sin ella, un modelo que
  escribe el encabezado de una sesión tiene que adivinar la hora, y las
  suposiciones se desvían.

No hay base de datos ni llamadas de red. Cada archivo es Markdown que puedes
leer, editar y subir a git. Knotlog solo añade; nunca reescribe tu prosa.

## 2. El ciclo diario

Lo que primero confunde a la gente: una parte del ciclo se ejecuta sola y otra
es tuya. Así se reparte.

**Se ejecuta solo** (el adaptador de Claude Code, instalado en
`<vault>/.claude/settings.json`):

| Cuándo | Qué se ejecuta | Efecto |
|---|---|---|
| Empieza la sesión | `knotlog remember && knotlog context --json SessionStart` | las líneas de registro pendientes se convierten en una nota de sesión; se inyecta la memoria reciente |
| Cada prompt que envías | `knotlog context --json UserPromptSubmit` | tras suficientes líneas nuevas de registro, se recuerda al modelo que anote su memoria |
| Después de `Edit`/`Write`/`NotebookEdit`/`Read` | `knotlog capture` | se añade una línea a `activity.log`, en silencio |
| Termina la sesión | `knotlog remember && knotlog index` | se escribe la nota de sesión y se refresca el índice |

Dos condiciones para que funcione: `knotlog` debe estar en tu `PATH`, y Claude
Code lee la configuración de los hooks una sola vez al arrancar — **reinícialo
tras cualquier cambio en `settings.json`**.

**Lo que haces tú:**

1. Escribe notas en las carpetas de la bóveda sobre la marcha. Knotlog indexa lo
   que pones ahí; no inventa notas.
2. Al final de una sesión, rellena el bloque de reflexión de la nota de sesión
   de hoy. La plantilla ya está ahí, con tres encabezados. El agente puede
   rellenarla — el contexto de `SessionStart` se lo pide — pero nadie comprueba
   que lo haya hecho.
3. Mantén al día el archivo de hilos (`Threads.md`): qué sigue abierto, qué se cerró.
4. Ejecuta `knotlog search` cuando necesites algo de una sesión anterior, en
   lugar de volver a contarlo.

Knotlog lleva el libro mecánico. El significado lo escriben el modelo y tú.

## 3. Las carpetas

`init` crea diez carpetas. Los nombres de abajo son la estructura en inglés; una
bóveda turca recibe nombres turcos, y `--plain` los recibe en ASCII. Nada de
esto se impone — son un hábito, no un esquema.

| Carpeta | Escribe aquí cuando… |
|---|---|
| `📥 Inbox` | te llega una idea y todavía no quieres decidir dónde va |
| `🗑️ Trash` | vuelcas material en bruto dentro de la bandeja de entrada — pegados, fragmentos, transcripciones |
| `🎯 Command Center` | pertenece al panel: el foco de hoy, enlaces de entrada |
| `🗂️ Projects` | la nota trata de un trabajo activo — una subcarpeta por proyecto |
| `🧠 Knowledge` | la querrás de nuevo dentro de meses, independientemente de cualquier proyecto |
| `🛠️ Arsenal` | es una herramienta, un script o un fragmento para reutilizar |
| `📆 Sessions` | casi nunca a mano — `knotlog remember` escribe aquí, un archivo por día |
| `🔮 Companion` | la personalidad del asistente y las notas de identidad que lleva |
| `📦 Archive` | la cosa está terminada o congelada, y quieres quitarla de en medio |
| `📋 Templates` | nunca edites en el sitio — copia `note.md`, `project.md` o `session.md` |

La carpeta Templates incluye esos tres esqueletos y está **excluida del índice
de búsqueda**: son formas que copiar, no contenido que encontrar. Una bóveda con
tres notas y tres plantillas indexa las notas, no las plantillas.

## 4. Comandos que escribes

Todo lo de abajo se ejecuta dentro de la bóveda (sirve cualquier subcarpeta —
Knotlog sube por el árbol hasta encontrar `.knotlog/`).

**`knotlog search <terms>`** — encuentra una nota.

```
$ knotlog search taskbar
0.934	🧠 Knowledge/taskbar.md	Taskbar overflow	windows,ui
0.673	🧠 Knowledge/dpi.md	DPI notes	windows
```

**`knotlog links <path>`** — mira con qué se conecta una nota. Dale la ruta
relativa a la bóveda.

```
$ knotlog links "🧠 Knowledge/dpi.md"
outgoing links
incoming links
🧠 Knowledge/taskbar.md
```

Los enlaces salientes son los `[[wikilinks]]` escritos en esa nota; los entrantes
son las notas que apuntan a ella. Los destinos de los enlaces se resuelven por
cadena exacta, sin plegar — escribe `[[dpi]]` (el nombre de archivo sin
extensión) o la ruta completa relativa a la bóveda.

**`knotlog digest`** — resume un día de actividad sin tocar la marca de agua de
la sesión. `--dry-run` imprime en lugar de escribir, `--date YYYY-MM-DD` elige
un día, y el archivo cae en la carpeta de volcado.

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

**`knotlog doctor`** — la revisión de salud. Ver la sección 7.

**`knotlog import FILE`** — convierte una exportación guardada de una
conversación (transcripción de Claude, exportación de ChatGPT o JSONL con
`role`/`content`) en una nota de sesión.

```
$ knotlog import /tmp/chat.jsonl --date 2026-08-29
wrote: 📆 Sessions/2026-08-29-import-chat.jsonl.md
```

**`knotlog plan <name> --proje <Project>`** — abre una nota de plan donde
corresponden los planes: `<projects>/<Project>/<Plans>/<name>.md`, creada a
partir de la plantilla localizada con front matter y abierta en `$EDITOR` si
está definido. Los planes son memoria — mantenerlos dentro de la bóveda es lo
que hace que la siguiente sesión los herede, así que una carpeta de proyecto
inexistente es un error, nunca se crea automáticamente, y un plan existente
nunca se sobrescribe. Ejecútalo desde dentro de una carpeta de proyecto y
`--proje` se resuelve solo.

```
$ knotlog plan roadmap --proje Knotlog
wrote: 🗂️ Projects/Knotlog/Plans/roadmap.md
```

**`knotlog tone [--list|<slug>]`** — muestra o fija el preset de tono. Sin
argumentos imprime qué fuente está activa y por qué (un slug de preset, la
propia sección Tone de companion.md, o ninguna); `--list` recorre los nueve
presets incluidos (Default, Professional, Friendly, Candid, Quirky, Efficient,
Snarky, Teaching, Kaomoji) y marca el activo; `<slug>` escribe `tone=<slug>` en
`.knotlog/config` — nunca toca companion.md.

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

**`knotlog index`** — refresca el índice a mano. Los hooks lo hacen al terminar
la sesión; ejecútalo tú tras añadir notas fuera de una sesión. `--full`
reconstruye todo.

```
$ knotlog index
# indexed 6 (reused 5, stale 1, dropped 0)
```

**`knotlog remember`** — escribe la nota de sesión ahora en lugar de al terminar
la sesión. Añade `--git` para hacer commit de la bóveda después; sin él,
Knotlog nunca hace commit.

## 5. Buscar en tu propia memoria

`search` pliega la consulta, puntúa el índice con BM25 e imprime las mejores
filas como columnas separadas por TAB: puntuación, ruta, título, etiquetas. Diez
filas por defecto.

- `--limit N` — cuántas filas.
- `--paths` — solo la columna de rutas, una por línea: `knotlog search dpi --paths`.
- `--brief` — una columna extra con un fragmento de ~120 bytes de la nota. Úsalo
  para elegir cuáles dos notas abrir en lugar de abrir diez. No se puede
  combinar con `--paths`.
- `--tag ui` / `--status paused` — descarta toda nota cuyo frontmatter no
  coincida. Son filtros, no pistas de ordenación; combinados, son un AND.

Las puntuaciones son relativas a tu bóveda, no absolutas — en una bóveda pequeña
una coincidencia filtrada puede puntuar por debajo de cero y aun así ser la nota
correcta.

**El plegado, y por qué importa para el turco.** Antes de indexar y antes de
buscar, el texto pasa por un perfil de plegado registrado como `fold=` en
`.knotlog/config`. Una bóveda turca recibe `fold=tr`: `İ ı ğ ş ç ö ü` se reducen
a sus formas ASCII, de modo que la consulta y la nota se encuentran a medio
camino.

```
$ knotlog search "acik kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
$ knotlog search "açık kaynak"
2.003	🧠 Bilgi/opencv.md	OpenCV kurulumu	python
```

Ambas grafías encuentran la nota. El perfil `default` — el que recibe una
bóveda en inglés — no pliega nada más allá de las mayúsculas ASCII, así que ahí
`acik` no encuentra `açık`. Si escribes turco en una bóveda con estructura en
inglés, fija `fold=tr` en `.knotlog/config` y ejecuta `knotlog index --full`
una vez; el índice debe reconstruirse con el nuevo perfil.

El plegado pierde información a propósito: `açık` y `acık` se reducen a la misma
clave. Una laguna conocida: `--tag` pliega su argumento pero lo compara con el
texto crudo del frontmatter, así que `--tag istanbul` no encontrará una
etiqueta escrita `İstanbul`.

## 6. Hilos y notas de sesión

Cuatro archivos llevan la historia de una sesión a otra.

**La nota de sesión de hoy** (`📆 Sessions/YYYY-MM-DD.md`) la escribe
`remember`. La parte de arriba es mecánica — intervalo de tiempo, recuento de
herramientas, archivos tocados. Debajo hay una plantilla que Knotlog añade una
vez y nunca vuelve a tocar:

```
<!-- knotlog:reflect:start -->
### What changed in this session?

### Where did the work happen?

### Threads touched or continued

<!-- knotlog:reflect:end -->
```

Rellenarla es tu trabajo. Un segundo `remember` el mismo día no sobrescribirá
lo que esté escrito ahí. Mientras el bloque esté vacío, `SessionStart` le pide
al modelo que lo rellene y nombra el archivo; si el bloque de ayer quedó vacío,
se avisa una vez a la siguiente sesión y luego el aviso se descarta.

**`Threads.md`** (`Konular.md` en una bóveda turca) está en la raíz de la bóveda y guarda las historias que duran más
de un día, bajo `### Active threads` y `### Closed threads`. `knotlog context`
lo devuelve a cada sesión, lo que lo convierte en el archivo de más
influencia de la bóveda — y el más barato de dejar pudrirse. Mantenlo corto; un
hilo que se cerró debe bajar, no quedarse arriba.

### El archivo de reglas

`init` siembra **`Rules.md`** (`Kurallar.md` en una bóveda turca) en la raíz de
la bóveda — un contrato de comportamiento que hereda todo agente que trabaje en
la bóveda. El valor por defecto incluido lleva cuatro bloques que Knotlog
considera innegociables:

- **Puertas de aprobación** — el movimiento de dinero, los mensajes salientes,
  el borrado y los secretos nunca se cruzan sin aprobación; un sí cubre una
  tarea en una sesión.
- **Protocolos de nivel cero** — once hábitos de trabajo básicos (alcance del
  contrato, una definición de terminado antes de empezar, escribir la salida de
  verificación en un archivo, las tres cosas que informar antes de decir
  "hecho", un commit por paso lógico, tres líneas al final de la sesión, y
  más), cada uno con la razón por la que existe.
- **La regla del recibo** — un commit, un archivo actualizado, una salida
  escrita en disco es un recibo; "hecho" no lo es. Sin rastro, no hay trabajo.
- **Disciplina de registro** — cuando un registro nuevo sustituye a uno viejo,
  retira el viejo: busca el nombre antiguo en la bóveda, ciérralo o
  actualízalo; nunca dejes dos copias vivas de un mismo asunto.

Edita el archivo con libertad — es tuyo; Knotlog nunca lo sobrescribe (un
archivo existente gana incluso bajo el nombre del otro idioma). `knotlog
context` inyecta los encabezados del archivo en cada sesión, después de la
sección de hilos; un `ctx_max` ajustado descarta esta sección entera antes de
recortar el bloque de hilos. `doctor` revisa las plantillas incluidas entre sus
archivos del producto. Mientras no edites la semilla, no cuenta como un archivo
de memoria escrito a mano — así una bóveda nueva sigue saliendo limpia de
`doctor`; en cuanto escribes en ella, pasa a formar parte del conjunto
obligatorio que se describe en la sección 7.

El puente (`AGENTS.md`/`CLAUDE.md`) lleva el protocolo de puntos de control que
mantiene viva la historia cuando las sesiones terminan mal: escribe el registro
en el momento en que acaba el trabajo, no al final de la sesión; cuando el
trabajo se detiene a medias, escribe dónde se quedó y el siguiente paso; cuando
el usuario da a entender que se va, termina el registro antes de cerrar.

Knotlog nunca reescribe ninguno de estos archivos. Todos son de solo añadir por su parte.

### El archivo de hechos

`init` siembra **`Facts.md`** (`Gerçekler.md` en una bóveda turca) en la raíz de
la bóveda — la capa de hechos persistentes, mantenida sin ningún servicio de
memoria externo. La regla es **una línea, un hecho**: cada línea con viñeta
empieza con una de tres etiquetas — `Decision:` (una elección hecha y su razón,
válida hasta que cambie), `Preference:` (cómo te gusta trabajar), `Convention:`
(cómo funcionan las cosas en esta bóveda). El listón para entrar: una línea
debe seguir siendo cierta y útil dentro de meses — **la identidad cuenta, las
noticias no**; lo que caduca va en `Threads.md` o en las notas de sesión.

Edita el archivo con libertad — es tuyo; Knotlog nunca lo sobrescribe (un
archivo existente gana incluso bajo el nombre del otro idioma). `knotlog
context` inyecta las líneas de hechos en cada sesión, después de la sección de
reglas, bajo el mismo contrato de `ctx_max`: un presupuesto ajustado descarta
la sección entera y nunca recorta el bloque de hilos. Una semilla sin tocar es
el esqueleto, no un registro — el contexto calla sobre ella hasta que escribes
tu primera línea. `doctor` imprime una fila `ok` con el número de líneas de
hechos cuando el archivo existe y calla en las bóvedas anteriores a esta capa.

## 7. Cuando algo parece ir mal

`knotlog doctor` imprime una sección por área y una línea de resumen. Sale con
0 cuando solo hay avisos, y con 1 solo cuando algo falló.

```
summary: 151 ok, 3 warn, 0 fail
```

**¿Qué parte de tu memoria se audita?** No todos los archivos de una bóveda se
miden con el mismo rasero. La **memoria viva** — los puentes AGENTS.md/CLAUDE.md,
el archivo de hilos, las notas de reglas y de núcleo, y el bloque `## ` más
reciente de `Last-Session.md` — es la instrucción sobre la que se apoyará la
siguiente sesión; toda ruta dentro de ella debe resolverse. La **memoria
histórica** — los bloques más antiguos de `Last-Session.md`, la nota del diario,
todo lo que hay bajo la carpeta de sesiones — es un registro; tiene derecho a
mencionar carpetas que ya no existen, y la auditoría de rutas nunca la lee. Añade
un bloque de sesión nuevo y el anterior pasa a ser historia automáticamente.

Los nombres de los archivos de memoria siguen el idioma de la bóveda
(`Son-Oturum.md`/`Kurallar.md`/`Çekirdek.md`/`Günlük.md` en una bóveda turca,
`Last-Session.md`/`Rules.md`/`Core.md`/`Journal.md` en una inglesa), y el nombre
del otro idioma se acepta como alternativa heredada. En cuanto tu bóveda lleva
un archivo de memoria escrito a mano, ese conjunto pasa a ser **obligatorio**:
un archivo ausente es el único hallazgo de memoria que lleva el código de salida
de doctor a 1 — una capa de memoria migrada a medias es cómo las sesiones pierden
sus inyecciones en silencio.

Cómo leer las líneas que importan:

- `fail` en **tools** — `sh`, `sed`, `awk`, `grep`, `tr`, `git` son toda la lista
  de dependencias. Que falte una es el único tipo de avería que detiene a Knotlog.
- `warn index — index.tsv missing or stale (knotlog index)` — esperable en una
  bóveda nueva, tras editar notas fuera de una sesión, y justo después de
  `remember` — que escribe una nota de sesión que el índice aún no ha visto.
  Ejecuta `knotlog index`.
- `warn threads — Threads.md has not been updated yet` — falta el archivo, o su
  bloque `Active/Closed threads` sigue vacío. La plantilla sola no lo despeja;
  el contenido escrito sí. Esperable en una bóveda nueva, un recordatorio más
  adelante.
- `warn links — N wikilink target(s) not found` — un `[[link]]` apunta a la
  nada. La resolución es por cadena exacta, así que una nota renombrada deja un
  enlace colgando.
- `warn links — … resolve to more than one note` — dos notas comparten nombre y
  Knotlog se niega a adivinar cuál querías decir.
- `fail memory — Last-Session.md | Son-Oturum.md not found` — uno de los
  archivos de memoria obligatorios no existe ni con su nombre actual ni con el
  heredado. Código de salida 1; cualquier otro hallazgo de memoria es un aviso.
- `warn paths — N quoted path(s) not found` — una `` `ruta/entre/comillas` `` en
  tu memoria viva apunta a la nada en la bóveda. Cada ruta ausente se lista en
  su propia fila bajo el recuento. `~/`, las rutas absolutas, las URL, las letras
  de unidad, los globs y los fragmentos de shell nunca se juzgan; un archivo de
  la bóveda seguido de argumentos (`./knotlog doctor`) es un comando, y un
  nombre de carpeta suelto (`lib/`) cuenta como encontrado si existe una carpeta
  con ese nombre en cualquier lugar de la bóveda.
- `warn paths — … point inside git-ignored territory` — la ruta existe pero git
  no la sigue: funciona en esta máquina y se rompe el día que se clone o se mueva
  la bóveda.
- `warn memory — N memory file(s) with uncommitted changes` — la red de seguridad
  de tu memoria es git; la memoria editada pero sin commit no tiene ninguna.
  Haz commit.
- `warn last session — the newest session block does not mention today's date` —
  existe un commit de hoy, pero el bloque más reciente de `Last-Session.md` se
  escribió antes. La fecha de hoy se busca en el bloque entero, así que una
  sesión que cruzó la medianoche no es una falsa alarma.

- `ok claude hooks — installed (vault)` — el adaptador está en
  `<vault>/.claude/settings.json`. Así se ve una instalación normal. Un simple
  `installed` significa que se encontró en el `~/.claude/settings.json` global.
  `not installed` significa que no existe ninguno, y el ciclo automático de la
  sección 2 no se está ejecutando.
- `warn path — path contains OneDrive` / `locale is not UTF-8` — riesgos del
  entorno para los nombres de carpeta con emoji y para el plegado. Ninguno
  rompe una bóveda normal.

`doctor` no modifica nada. Todo lo que reporta es un comando para que lo ejecutes tú.

## 8. Usar Knotlog sin hooks

Para agentes sin superficie de hooks — o cuando quieres el ciclo bajo tu propia
mano — dos comandos sustituyen la parte automática:

- `knotlog capture --git` compara el árbol de trabajo con el último commit y
  añade una línea por cada archivo Markdown cambiado. Ejecútalo antes de
  `remember`. No guarda estado: ejecútalo dos veces sin hacer commit entre
  medias y los mismos archivos se registran dos veces.
- `knotlog context --bridge` escribe el contexto que inyectarían los hooks en un
  bloque `<!-- knotlog:context:start -->` en **ambos** `AGENTS.md` y `CLAUDE.md`.
  Cualquier agente que lea uno de los dos archivos ve la misma memoria — así es
  como una sesión en un agente recoge lo que hizo una sesión en otro.

Una sesión manual es entonces: refresca los archivos puente con `context --bridge`
y deja que el agente lea uno de ellos, trabaja, y luego ejecuta
`knotlog capture --git && knotlog remember && knotlog index`.

### Antigravity

Antigravity tiene superficie de hooks, así que recibe el ciclo automático. Desde la bóveda:

```
knotlog setup antigravity --dry-run   # preview, writes nothing
knotlog setup antigravity             # writes .agents/hooks.json
```

Al empezar la sesión el hook ejecuta `remember` e inyecta el contexto reciente
como mensaje de sistema. Cuando el agente termina un turno, un segundo hook
comprueba si la nota de sesión se ha quedado atrás (como máximo una vez cada 30
minutos) y, de ser así, envía al agente a escribirla antes de que termine el
turno. Un `.agents/hooks.json` existente que sea distinto nunca se sobrescribe;
fusiona a mano el incluido (`adapters/antigravity/hooks.json`). Reinicia
Antigravity después. Detalles: [REFERENCE.md](REFERENCE.md#antigravity).

### Devin Desktop (Windsurf) y OpenCode

Ambos reciben un pequeño hook de registro; su contexto viene del puente
`AGENTS.md`. Desde la bóveda, ejecuta `knotlog setup windsurf` (o `devin`) y
`knotlog setup opencode`; `--dry-run` previsualiza. Escriben
`.devin/hooks.json` y `.opencode/plugins/knotlog.js`, y nunca sobrescriben un
archivo distinto. El cliente ejecuta `knotlog` desde su propio entorno (Devin
Desktop usa tu shell de inicio de sesión), así que `knotlog` debe estar en ese
`PATH` o el hook no hará nada en silencio. Verificado en vivo en Linux el
2026-10-25 (Devin Desktop 3.11.216, OpenCode 1.19.4); Windows no está
verificado. Detalles: [REFERENCE.md](REFERENCE.md#windsurf--devin-desktop).

### Conectar el servidor MCP

`knotlog mcp` permite a un cliente MCP buscar en la bóveda y leer su contexto
sin hooks. Ofrece tres herramientas: `knotlog_search` (una consulta y un límite
opcional), `knotlog_context` y `knotlog_note` (una línea en la nota de sesión de
hoy, igual que `knotlog note`). Encuentra la bóveda a partir de la carpeta donde
arranca, así que regístralo desde dentro de la bóveda:

```
claude mcp add knotlog -- knotlog mcp
```

Si `knotlog` no está en tu `PATH`, da la ruta absoluta en su lugar. Otro cliente
puede ejecutar el mismo comando con el argumento `mcp`; para un servidor
iniciado fuera de la bóveda, fija `KNOTLOG_VAULT` a la carpeta de la bóveda.
Detalles: [REFERENCE.md](REFERENCE.md#mcp-server).

## 9. Ajustes

Los ajustes de la bóveda viven en `.knotlog/config` como líneas simples
`key=value`: `layout`, `lang`, `fold`, `user`, `companion`, `purpose`, `tone`, `flair`,
`ctx_max`. Cambiar `fold` requiere `knotlog index --full` después; los demás
surten efecto en el siguiente comando. `init` nunca escribe `ctx_max` — ya
tiene un valor por defecto que funciona (4096), así que añade la línea a mano
solo si quieres sobrescribirlo; `doctor` informa de dónde salió el valor que
está usando (env/config/default), y avisa si un `ctx_max=` de la configuración
no es un entero positivo (se ignora, no es fatal).

**Elegir un idioma.** Knotlog habla English, Türkçe, Español, Português
(Brasil), 日本語 y 简体中文. Elige uno en el asistente de instalación, con
`--lang <code>` (`en`, `tr`, `es`, `pt-br`, `ja`, `zh-cn`), o fijando `lang=`
en `.knotlog/config`; lo que falte en tu idioma recurre al inglés. Las
traducciones que no son inglés/turco están asistidas por máquina, y las
correcciones son bienvenidas.

`tone` elige uno de los nueve presets de tono incluidos (`knotlog tone --list`
muestra nombre + descripción, `knotlog tone <slug>` lo fija) — se impone a la
propia sección `## Tone`/`## Üslup` de companion.md en el contexto que inyecta
Knotlog siempre que el preset nombrado exista de verdad para el idioma de la
bóveda. Déjalo sin fijar, o fíjalo a un slug que no se distribuye, y Knotlog
recurre a la sección Tone de companion.md — el mismo comportamiento que tenía
una bóveda antes de que existieran los presets. Como `purpose`, no hay pregunta
interactiva para `tone` durante `init`; solo la opción `--tone <slug>` (que
también acepta `install`).

`flair` añade un adorno a las respuestas encima del tono: `none` (por defecto), `kaomoji` o `emoji`. `knotlog flair` lo muestra, `knotlog flair --list` los lista y `knotlog flair <valor>` lo establece; `init` e `install` también aceptan `--flair`. Los textos vienen en los seis idiomas. Cualquier adorno distinto de `none` sustituye al preajuste de tono `kaomoji`.

Variables de entorno, cuando los valores por defecto no encajan:

(Los nombres `QUIPU_*` anteriores al cambio de nombre siguen funcionando; cuando ambos están definidos, gana `KNOTLOG_*`.)

- `KNOTLOG_CTX_MAX` (4096) — presupuesto en bytes del contexto que inyecta
  Knotlog. Tiene prioridad sobre el `ctx_max=` de `.knotlog/config`, que tiene
  prioridad sobre el valor por defecto 4096 — usa la variable de entorno para un
  cambio puntual, o `ctx_max=` en la configuración para un ajuste que sobreviva
  al mover la bóveda a otra máquina.
- `KNOTLOG_NUDGE_AFTER` (50) — líneas de registro nuevas antes de empujar al
  modelo a anotar su memoria.
- `KNOTLOG_CHECKPOINT_AFTER` (1800) — segundos antes de que una nota de sesión
  sin modificar con actividad git posterior dispare un recordatorio o bloqueo de
  punto de control.
- `KNOTLOG_LOG_MAX` (262144) — tamaño de `activity.log` antes de rotar a `.log.1`.
- `KNOTLOG_HOOK=1` — lo fijan los adaptadores. Hace que los errores salgan con
  0, para que un Knotlog roto nunca bloquee tu sesión.

### La puerta de secretos (pre-commit)

`install` convierte la bóveda en un repositorio Git por defecto (`--no-git` lo
desactiva) y añade un commit base más un `.gitignore` para el estado de máquina
regenerado; `init --git` hace lo mismo bajo demanda. Nunca se hace commit sobre
un historial existente, nunca se convierte por defecto una bóveda existente que
no sea repositorio (pasa `--git` para pedirlo), y la falta de identidad git se
informa, no es fatal. Siempre que la bóveda sea un repositorio, Knotlog instala
`.githooks/pre-commit` y apunta `core.hooksPath` a él. Cada commit escanea
entonces las líneas *añadidas* en el área de preparación en busca de formas
conocidas de secretos — AWS `AKIA…`, OpenAI `sk-…`, GitHub
`ghp_…`/`github_pat_…`, Slack `xox…`, Google `AIza…`, bloques `PRIVATE KEY`,
tokens `Bearer`, JWT y asignaciones genéricas
`api_key=`/`secret=`/`token=`/`password:` (con `=` o `:`) — y rechaza el commit,
nombrando el archivo donde lo encontró. Si hay un escáner externo `sir-tara` en
tu `PATH`, el escaneo completo se delega en él. Un hook editado a mano (uno sin
el marcador de Knotlog) nunca se sobrescribe. Para hacer commit de todos modos:
`git commit --no-verify` se salta todos los hooks, y
`KNOTLOG_SKIP_SECRET_SCAN=1 git commit …` se salta solo esta puerta para ese
commit.

`knotlog help` lista cada comando; `knotlog help --es` imprime la misma lista en
español (los demás idiomas incluidos funcionan igual: `--tr`, `--pt-br`, `--ja`, `--zh-cn`).

## 10. Marcharse

Si Knotlog no es para ti, deberías poder recuperar tu máquina sin adivinanzas.
Desinstalar quita solo lo que la instalación puso fuera de tu bóveda:

```bash
knotlog uninstall --dry-run   # see what would go
knotlog uninstall             # remove the command from PATH
```

En Windows, ejecuta `.\uninstall.ps1` desde PowerShell en su lugar (o además, si
instalaste de ambas formas) — quita los accesos directos bajo
`%LOCALAPPDATA%\Knotlog\bin` y la entrada que añadió a tu `PATH` de usuario.

**Tus notas nunca se borran.** La bóveda se queda exactamente donde está, y el
comando imprime su ruta junto con los archivos de Knotlog que aún contiene.
Esos archivos están inertes sin el comando — la bóveda es entonces solo Markdown
en carpetas, y puedes conservarla, moverla o borrarla tú mismo. Desinstalar te
muestra la línea exacta para borrarla si eso es lo que quieres.

Nada más en tu máquina se cambió: Knotlog nunca edita los archivos de arranque
del shell, nunca escribe fuera de la bóveda y de su propio acceso directo, y
nunca llama a casa.
