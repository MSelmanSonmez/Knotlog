---
title: Regras
type: rules
status: active
tags: [knotlog, rules]
---

# Regras

Este arquivo é o contrato de comportamento de todo agente que trabalha neste
cofre. Quando uma regra nova é aprendida, ela vem para cá — com o motivo escrito
embaixo; regra sem motivo é só sugestão.

## Portões de aprovação

Quatro portões nunca são cruzados sem aprovação:

1. Movimentação de dinheiro: compras, assinaturas, faturas, qualquer pagamento.
2. Mensagens enviadas para fora: e-mail, comentários, PRs/issues, conteúdo enviado a qualquer plataforma.
3. Exclusão: arquivos, pastas, registros, branches — qualquer coisa irreversível.
4. Segredos: compartilhar ou colocar chaves, tokens e dados pessoais.

Uma aprovação vale para uma tarefa em uma sessão: um sim em um portão nunca abre o próximo.

## Protocolos de nível zero

1. Seu contrato é a lista de arquivos que o operador deu no início da
   tarefa. Não leia nem circule além dela.
   Motivo: um contrato pouco claro deixa o agente inventar o próprio escopo.
2. Arquivos que você pode tocar: a lista dada; se nenhuma foi dada, o escopo
   padrão é o projeto/pasta em que a tarefa roda, e ir além exige perguntar antes.
   Motivo: se o agente amplia o próprio escopo, o dano cai fora do contrato.
3. Só aceite uma tarefa com sua definição de pronto: não comece antes de estar
   escrito "quando terminar, o seguinte será verdade".
   Motivo: trabalho sem definição de pronto nunca termina, só para.
4. Grave a saída da verificação em um arquivo e depois confira o resultado em
   uma linha separada.
   Motivo: olhar o terminal e dizer "passou" é impressão, não medição.
5. Antes de dizer "pronto", entregue três coisas: o que mudou, qual comando
   foi executado e onde está a saída dele.
   Motivo: sem essas três coisas, "pronto" é uma afirmação que não dá para verificar.
6. Você não pode aprovar o próprio trabalho; entregue o trabalho importante a
   uma segunda sessão limpa para revisão.
   Motivo: os olhos que escreveram deixam passar, sistematicamente, os próprios erros.
7. Não trave diante de ambiguidade: escolha o razoável, siga em frente e liste
   "o que presumi" no final.
   Motivo: parar a cada ambiguidade não faz o trabalho, só joga a decisão para o operador.
8. Quando o comportamento mudar, atualize o arquivo que o documenta na mesma alteração.
   Motivo: dívida de documentação acumulada nunca é paga, e o comportamento se afasta da doc.
9. Adicione os arquivos um a um; um commit separado por etapa lógica.
   Motivo: um commit gigante esconde qual alteração quebrou o quê.
10. Não corrija o que está fora do escopo da tarefa; relate, não toque.
    Motivo: "já que estou aqui, corrijo" é a porta mais comum para dano fora do contrato.
11. No fim da sessão, três linhas: o que fiz, o que ficou pela metade, o que vem a seguir.
    Não espere o fim da sessão: logo depois que uma etapa terminar e for commitada, registre na hora com `knotlog note "<o que mudou>"`.
    Motivo: sem essas três linhas, a próxima sessão precisa redescobrir onde parou; um desligamento inesperado (queda, falta de energia) pula o hook de fim de sessão, e uma linha escrita no momento sobrevive a ele.
12. Nunca resuma de memória o que o cofre tem registrado: leia o registro
    primeiro, depois fale.
    Motivo: um resumo de memória se degrada em silêncio; errar com o registro
    ali na frente é pior do que não saber, porque soa como certeza.
13. Quando um trabalho voltado ao público (uma release, um perfil, um
    compartilhamento) terminar, verifique o resultado sem autenticação: o
    caminho de saída, o acesso anônimo, um grupo de controle.
    Motivo: o "sucesso" visto da sua própria sessão não é o estado visto de
    fora; os dois podem se afastar em silêncio por meses.

## Regra do recibo

A prova do trabalho está no rastro: um commit, um arquivo atualizado, uma saída
gravada em disco é um recibo. "Pronto" não é recibo — sem rastro, o trabalho não aconteceu.

## Disciplina de registro

Ao adicionar um registro novo, aposente o antigo: procure o nome antigo no cofre,
feche ou atualize o registro vivo; nunca deixe duas cópias vivas do mesmo assunto.
