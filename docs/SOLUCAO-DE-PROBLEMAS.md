# Resolver problemas

Para abrir o relatório, use somente:

```powershell
.\Relatorio-AcessoPasta.ps1 -Menu
```

Os outros comandos deste guia são ferramentas do Windows para diagnóstico ou
liberação do arquivo; não são formas alternativas de executar o relatório.

## Antes de investigar

Anote a mensagem completa, o servidor escolhido, o período e o evento consultado.
Confira se o erro ocorreu ao abrir o menu, ao acessar o log ou ao salvar o CSV.
São etapas diferentes e podem exigir correções diferentes. O
[glossário](GLOSSARIO.md) explica as siglas das mensagens e dos guias.

Faça uma mudança por vez e repita uma consulta curta. Assim você consegue
identificar qual ajuste resolveu a situação. Uma mensagem de “acesso negado”
não deve ser interpretada como ausência de registros.

## Script bloqueado

**Sintoma:** o PowerShell informa que a execução de scripts está desabilitada,
que o arquivo não está assinado ou que foi bloqueado após o download.

Primeiro, confirme que o arquivo veio da origem esperada. O comando de consulta
mostra as políticas de execução em diferentes níveis; o comando Unblock-File
remove a marca de download apenas do arquivo indicado. Não corrige uma política
corporativa que exija assinatura.

```powershell
Get-ExecutionPolicy -List
Unblock-File -LiteralPath .\Relatorio-AcessoPasta.ps1
```

Se MachinePolicy e UserPolicy forem Undefined e a empresa permitir, libere scripts locais apenas nesta sessão:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Se uma GPO exigir AllSigned, solicite a assinatura do script com certificado confiável. Desbloquear o download não substitui a assinatura.

## Erro com o nome do usuário

Na opção **5 — Usuário**, informe o nome ou um padrão como `*teste*`.
Para um nome sem curingas, responda à pergunta de nome exato. Essa opção exige
a mesma grafia do log, incluindo maiúsculas/minúsculas. Se não encontrar o
usuário, desative nome exato ou use um curinga.

## Nenhum resultado

**Objetivo:** descobrir se faltam eventos no Windows ou se um filtro do menu
está eliminando registros que já existem.

1. Confirme o servidor na opção **1**: deve ser o que guarda os arquivos e grava
   os eventos, não necessariamente o computador de quem fez o acesso.
2. Faça um acesso de teste pela rede a partir de outra estação e anote o horário.
3. Consulte um período curto, com **4 — Pasta** limpo (`-`) e **5 — Usuário** em `*`.
4. Confira [auditoria e tipos de evento](AUDITORIA-WINDOWS.md).

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 5145
    StartTime = (Get-Date).AddMinutes(-15)
} -MaxEvents 5 | Select-Object TimeCreated, Id, Message
```

Sem 5145, confira Detailed File Share. Para 4663, confira também auditoria na pasta (SACL). Leia os erros: acesso negado não significa zero eventos. Confira o servidor e o período; eventos antigos podem ter sido perdidos.

**Como interpretar o teste:** se a consulta direta ao Windows também não
mostra o evento esperado, confira a auditoria e o servidor. Se ela mostra o
evento, volte ao menu e acrescente os filtros um de cada vez: primeiro pasta,
depois usuário. Isso ajuda a descobrir qual campo não corresponde ao registro.

## Caminho local funciona, nome de rede não

Confira os nomes com `Get-SmbShare | Select-Object Name, Path`. Se `z` aponta para `E:\FileServer`, use `\\SERVIDOR\z`.

O relatório corrigido trata nomes curtos e completos do servidor. Para diagnóstico de 4663, prefira caminho local. Nomes alternativos e DFS não são traduzidos automaticamente.

## Demora depois de “Consultando log”

A consulta pode ler muitos eventos antes de filtrar pasta e usuário. Na versão atual, acompanhe o horário em processamento, a quantidade do evento selecionado e os registros de apoio. Zero linhas antes do término não é um resultado final. Se o usuário for específico, ative nome exato na opção **5** usando a mesma grafia do log; isso agora reduz também a leitura do modo 4660.

Para um teste curto pelo menu:

1. Em **3**, escolha período específico e informe os últimos 15 minutos.
2. Em **5**, informe o usuário e ative nome exato se a grafia coincidir com o log.
3. Em **12**, informe `10000` como limite de diagnóstico.
4. Em **8**, mantenha Silencioso ativado e ResolverSids, ResolverIP e EnriquecerAD desativados.
5. Em **9**, informe `C:\Relatorios\diagnostico-{data}.csv`.
6. Execute com **E** e confira os avisos e o arquivo de diagnóstico.

O limite vale antes dos filtros locais; em 4660 inclui também os cinco minutos anteriores lidos para apoio. Se for atingido, o aviso e o arquivo `.execucao.csv` indicam que a busca pode estar parcial. Remova o limite (zero) ou reduza o período para uma coleta completa.

No menu, escolha o limite na opção 12. Silencioso já vem ativado para evitar tabelas enormes. ResolverSids, ResolverIP e EnriquecerAD podem depender da rede/domínio; mantenha desativados no primeiro teste. A tradução de SID agora é opcional e o identificador continua disponível.

Os registros ainda ficam em memória. Progresso é atualizado quando chegam eventos; uma espera pelo Windows, rede, AD ou DNS pode não atualizar a tela. Se necessário, use Ctrl+C. O script não impõe um prazo máximo de execução. Se ficar apenas em “Buscando eventos”, teste Get-WinEvent localmente com uma janela curta e envie a última mensagem e o arquivo de diagnóstico, removendo dados sensíveis.

## Falha remota ou relatório incompleto

- Teste primeiro no servidor local, com acesso ao log de Segurança.
- Log remoto depende de permissões e RPC/firewall; a listagem de compartilhamentos usada por algumas opções requer CIM. Não desative o firewall inteiro.
- Confira os avisos e o arquivo `.execucao.csv` gerado junto do relatório.
- Confira a data do CSV: quando não há registros, o detalhado pode não ser criado e um arquivo antigo continuar na pasta.
- Indeterminado significa que faltam dados para concluir a autorização.

## Arquivos arquivados não aparecem

Os relatórios consultam apenas o log ativo. Veja [arquivamento](AUDITORIA-WINDOWS.md#arquivar-ao-atingir-o-limite).

## O CSV não foi criado ou parece ser de outra execução

Confira os destinos nas opções **9** e **10**. Se o campo estiver desativado,
informe um caminho para habilitar a exportação. A conta que executa o programa
precisa conseguir criar arquivos nessa pasta.

Use `{data}` no nome, como `acessos-{data}.csv`, para separar execuções. Ao
terminar, confira a mensagem de exportação e a data do arquivo no Explorador.
Uma busca sem registros pode deixar um CSV antigo no local; abrir esse arquivo
não mostra necessariamente o resultado da consulta mais recente.

Se o Excel abrir tudo em uma coluna, importe o arquivo como texto/CSV e escolha
o delimitador ponto e vírgula. Se houver acentos incorretos, selecione UTF-8 na
importação. Não altere os dados originais antes de guardar uma cópia da análise.

## A estimativa do log parece alta ou não aparece

Na opção **L**, dias totais e dias até encher são aproximações calculadas a
partir do tamanho e do intervalo disponíveis. Um arquivo com espaço reservado
antecipadamente pode parecer maior que o conteúdo útil e distorcer a conta.
Uma janela com poucas horas de eventos também varia muito ao longo do dia.

Campos vazios podem indicar falta de dados para estimar, como um log sem eventos
ou sem intervalo entre o primeiro e o último. Isso não é uma previsão de zero
dias. Em log circular cheio, zero dias até encher significa que o arquivo já
atingiu o limite; a gravação pode continuar substituindo os eventos antigos.

Para analisar a quantidade de eventos, responda S à contagem por dia. Ela lê o
histórico disponível e pode demorar. Compare dias de atividade semelhante e
considere horários de pico antes de definir um novo limite de armazenamento.
