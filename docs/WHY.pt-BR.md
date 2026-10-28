# Por que o Knotlog

> Esta tradução é assistida por máquina; correções são bem-vindas. O original em inglês é [WHY.md](WHY.md).

## O problema

Abra hoje um agente de terminal e ele não sabe nada sobre ontem.

Você passou três horas com ele ontem à noite. Explicou o projeto. Rejeitou duas
abordagens e disse por quê. Fechou numa terceira. Hoje de manhã você abre o mesmo
agente na mesma pasta, e nada disso está lá. Então você explica de novo. Mais
curto desta vez, porque você cansou de explicar — o que significa que ele recebe
a versão pior.

Esse é o problema inteiro. Não que o modelo seja fraco — o modelo está ótimo. Ele
só começa cada sessão do zero, e quem carrega o contexto por cima desse buraco é
você.

Depois de algumas semanas assim, você percebe o que passou a fazer. Mantém um
arquivo de rascunho com coisas para colar no começo. Evita sessões longas porque
recomeçar custa caro. Para de perguntar "por que fizemos assim?" porque ninguém
lembra, você inclusive.

## O que o Knotlog faz em vez disso

O Knotlog anota o que aconteceu, em Markdown, em uma única pasta.

Enquanto o agente trabalha, cada arquivo que ele lê ou grava é acrescentado como
uma linha a um log. Quando a sessão termina, essas linhas viram uma nota datada.
Quando a próxima sessão começa, a atividade recente e as threads abertas são
devolvidas ao contexto do modelo antes mesmo de você digitar qualquer coisa.

Assim, amanhã de manhã o agente já abre sabendo o que você fez ontem à noite e
por quê. Não porque ele lembra — porque ele lê.

Essa é a ideia inteira. O resto desta página explica por que ele foi construído
desse jeito.

## Por que não custa nada

Esta é a parte sobre a qual as pessoas perguntam primeiro, porque a maioria das
ferramentas de memória para agentes de código cobra pela infraestrutura.

Elas cobram por um motivo. Uma ferramenta como o claude-mem executa um processo
worker separado para decidir o que uma sessão significou. Esse worker não tem
nenhum modelo dentro, então precisa de um vindo de algum lugar: um banco de dados
vetorial para a recuperação, embeddings para preenchê-lo, uma chave de API para
gerá-los. Infraestrutura de verdade, custo de verdade, repassado a você.

O Knotlog não tem esse problema, porque nunca precisou de um segundo cérebro. O
agente já está rodando. Você já está pagando por ele. Então a parte que entende
o significado é o modelo que você já tem no circuito — o Knotlog só lhe dá um
lugar para anotar as coisas e as lê de volta no momento certo.

Sem banco de dados. Sem embeddings. Sem chave de API. Nada para cobrar de você,
porque não há nada rodando que possa custar dinheiro.

## Os arquivos são seus

A sua memória são arquivos Markdown numa pasta que você escolheu.

Abra-os em qualquer editor. Leia-os sem nenhuma ferramenta. Coloque-os no git e
veja o seu próprio pensamento mudar ao longo dos meses. Leve-os para o Obsidian,
para outra ferramenta de memória ou para um editor de texto simples daqui a cinco
anos.

Não há nada para exportar, porque nada jamais foi importado para um formato que
só um programa consegue ler. O Knotlog acrescenta a esses arquivos; nunca
reescreve o que você escreveu. Se você apagar o Knotlog amanhã, tudo o que ele
registrou continua lá, ainda legível.

## Offline e local

O Knotlog não faz chamadas de rede por conta própria. O único comando que faz é
`knotlog update`, e só quando você o executa: ele baixa a versão mais recente
do GitHub. Nem upload, nem telemetria, nem conta.

Suas notas estão no seu disco. O que o seu agente tocou às 2 da manhã está no seu
disco. Isso importa se você trabalha com código de clientes, com qualquer coisa
sob NDA, ou num avião. Também significa que o Knotlog não pode quebrar porque um
serviço saiu do ar, mudou o preço ou acabou com o plano gratuito.

## Zero dependências

O Knotlog é um único script de shell POSIX. Ele usa `sed`, `awk`, `grep`, `tr` e
`git` — ferramentas que a sua máquina já tem.

Sem Python. Sem Node. Sem `jq`. Nada para `npm install`, nada para manter em
sincronia com a versão de um runtime, nada que quebre quando você atualizar algo
sem relação daqui a seis meses.

Isso não é um alarde de minimalismo. É o motivo de a instalação funcionar. Não
há árvore de dependências para resolver, então não há nada em que a instalação
possa falhar. A suíte de testes roda em Linux, macOS e Windows a cada commit,
porque o mesmo script roda nos três.

## Turco e inglês, os dois de verdade

A maioria das ferramentas trata o que não é inglês como uma camada de tradução
colada no final. Aqui isso vai mais fundo do que as strings da interface.

A busca normaliza o texto antes de indexar e antes de consultar. Em um cofre em
turco, `İ ı ğ ş ç ö ü` se reduzem às formas ASCII dos dois lados, então
`acik kaynak` e `açık kaynak` encontram a mesma nota. Essa normalização é um
mapa de caracteres de verdade, escrito regra por regra — não uma chamada
esperançosa a `lowercase()` que estraga o İ pontuado e dá o assunto por encerrado.

A interface, o layout das pastas, o texto de ajuda, os modelos iniciais e a
persona do companheiro existem nos dois idiomas. Você escolhe um na instalação e
o cofre é construído nele.

## O que ele não é

O Knotlog não é um mecanismo de busca que entende a sua prosa. A busca dele é
lexical e ranqueada com BM25 — boa para achar uma nota de que você se lembra pela
metade, não para responder a uma pergunta sobre ela. O entendimento acontece onde
deve: no modelo que lê os resultados.

O Knotlog também não escreve as suas reflexões por você. Ele registra o que
aconteceu de forma mecânica — arquivos, horários, ferramentas — e deixa um
esqueleto em cada nota de sessão para a parte que só você ou o modelo podem
preencher: o que mudou e por quê. Se ninguém preencher, ninguém preencheu. O
Knotlog impõe o formato, não o significado.

E ele não adivinha a sua estrutura. Ele indexa as notas que você escreve. Não as
inventa.

## O resumo honesto

Se você usa um agente de código todos os dias, você já tem um problema de
memória. E já o resolve à mão, mal, com contexto colado e um arquivo de rascunho.

O Knotlog é um pequeno script que faz essa parte por você, em arquivos que são
seus, numa máquina que continua sendo sua, de graça.

Comece aqui: o [README](../README.pt-BR.md) para instalar, o [guia do usuário](GUIDE.pt-BR.md)
para o ciclo diário.
