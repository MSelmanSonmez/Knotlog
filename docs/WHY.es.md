# Por qué Knotlog

*Esta es una traducción asistida por máquina de [WHY.md](WHY.md); la versión en inglés es la referencia y las correcciones son bienvenidas.*

## El problema

Abre hoy un agente de terminal y no sabrá nada de ayer.

Anoche pasaste tres horas con él. Le explicaste el proyecto. Rechazaste dos
enfoques y dijiste por qué. Te quedaste con un tercero. Esta mañana abres el
mismo agente en la misma carpeta y nada de eso está. Así que lo explicas otra
vez. Más corto esta vez, porque estás cansado de explicar, lo que significa que
recibe la peor versión.

Ese es todo el problema. No que el modelo sea débil — el modelo está bien.
Simplemente empieza cada sesión desde cero, y eres tú quien lleva el contexto de
un lado al otro.

Tras unas semanas así notas lo que has empezado a hacer. Guardas un archivo de
borrador con cosas para pegar al principio. Evitas las sesiones largas porque
reiniciar sale caro. Dejas de preguntar "¿por qué lo hicimos así?" porque nadie
lo recuerda, tú incluido.

## Qué hace Knotlog en su lugar

Knotlog anota lo que pasó, en Markdown, en una sola carpeta.

Mientras el agente trabaja, cada archivo que lee o escribe se añade como una
línea a un registro. Cuando termina la sesión, esas líneas se convierten en una
nota con fecha. Cuando empieza la siguiente sesión, la actividad reciente y los
hilos abiertos se vuelven a imprimir en el contexto del modelo antes de que
escribas nada.

Así, mañana por la mañana el agente abre sabiendo qué hiciste anoche y por qué.
No porque recuerde — porque lee.

Esa es toda la idea. El resto de esta página explica por qué está construido
como está.

## Por qué no cuesta nada

Esto es lo primero que pregunta la gente, porque la mayoría de las herramientas
de memoria para agentes de programación cobran por la infraestructura.

Cobran por una razón. Una herramienta como claude-mem ejecuta un proceso
trabajador aparte para decidir qué significó una sesión. Ese trabajador no lleva
un modelo dentro, así que necesita uno de algún sitio: una base de datos
vectorial para la recuperación, embeddings para llenarla, una clave de API para
generarlos. Infraestructura real, coste real, repercutido en ti.

Knotlog no tiene ese problema, porque nunca necesitó un segundo cerebro. El
agente ya está en marcha. Ya lo estás pagando. Así que la parte que entiende el
significado es el modelo que ya tienes en el circuito — Knotlog solo le da un
lugar donde anotar cosas y se las devuelve en el momento justo.

Sin base de datos. Sin embeddings. Sin clave de API. Nada que facturarte, porque
no hay nada en ejecución que pueda costar dinero.

## Los archivos son tuyos

Tu memoria son archivos Markdown en una carpeta que elegiste tú.

Ábrelos en cualquier editor. Léelos sin ninguna herramienta. Ponlos en git y
mira cómo cambia tu propio pensamiento a lo largo de los meses. Llévalos a
Obsidian, o a otra herramienta de memoria, o a un editor de texto plano dentro
de cinco años.

No hay nada que exportar, porque nunca se importó nada a un formato que solo un
programa pueda leer. Knotlog añade a estos archivos; nunca reescribe lo que tú
escribiste. Si borras Knotlog mañana, todo lo que registró sigue ahí, igual de
legible.

## Sin conexión, y en local

Knotlog no hace llamadas de red. No hay `curl` dentro, ni subidas, ni telemetría,
ni cuenta.

Tus notas están en tu disco. Lo que tu agente tocó a las 2 de la madrugada está
en tu disco. Eso importa si trabajas con código de clientes, con algo bajo un
acuerdo de confidencialidad, o en un avión. También significa que Knotlog no
puede romperse porque un servicio se caiga, cambie sus precios o cierre su plan
gratuito.

## Cero dependencias

Knotlog es un único script de shell POSIX. Usa `sed`, `awk`, `grep`, `tr` y
`git` — herramientas que tu máquina ya tiene.

Sin Python. Sin Node. Sin `jq`. Nada que `npm install`, nada que mantener
sincronizado con la versión de un entorno de ejecución, nada que se rompa cuando
actualices algo no relacionado dentro de seis meses.

No es presumir de minimalismo. Es la razón por la que la instalación funciona.
No hay un árbol de dependencias que resolver, así que no hay nada en lo que la
instalación pueda fallar. La batería de pruebas se ejecuta en Linux, macOS y
Windows en cada commit, porque el mismo script funciona en los tres.

## Turco e inglés, ambos como se debe

La mayoría de las herramientas tratan lo que no es inglés como una capa de
traducción añadida al final. Aquí llega más hondo que las cadenas de la
interfaz.

La búsqueda pliega el texto antes de indexar y antes de consultar. En una bóveda
turca, `İ ı ğ ş ç ö ü` se reducen a sus formas ASCII en ambos lados, de modo que
`acik kaynak` y `açık kaynak` encuentran la misma nota. Ese plegado es un mapa de
caracteres real, escrito regla por regla — no una llamada optimista a
`lowercase()` que estropea la İ con punto y da el asunto por zanjado.

La interfaz, la estructura de carpetas, el texto de ayuda, las plantillas
iniciales y el asistente con su personalidad existen en ambos idiomas. Eliges uno
al instalar y la bóveda se construye en él.

## Lo que no es

Knotlog no es un buscador que entienda tu prosa. Su búsqueda es léxica y se
ordena con BM25 — buena para encontrar una nota que recuerdas a medias, no para
responder preguntas sobre ella. La comprensión ocurre donde debe: en el modelo
que lee los resultados.

Knotlog tampoco escribe tus reflexiones por ti. Registra lo que pasó de forma
mecánica — archivos, horas, herramientas — y deja una plantilla en cada nota de
sesión para la parte que solo tú o el modelo podéis aportar: qué cambió y por
qué. Si nadie la rellena, nadie la rellena. Knotlog hace cumplir el formato, no
el significado.

Y no adivina tu estructura. Indexa las notas que escribes. No las inventa.

## El resumen honesto

Si usas un agente de programación a diario, ya tienes un problema de memoria. Ya
lo estás resolviendo a mano, mal, con contexto pegado y un archivo de borrador.

Knotlog es un pequeño script que hace esa parte por ti, en archivos que son tuyos,
en una máquina que sigue siendo tuya, gratis.

Empieza aquí: el [README](../README.es.md) para instalar, [la guía de usuario](GUIDE.es.md) para
el ciclo diario.
