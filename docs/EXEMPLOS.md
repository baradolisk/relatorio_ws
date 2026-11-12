# Exemplos pelo menu

Todos os exemplos começam abrindo o PowerShell como administrador na pasta do script:

```powershell
.\Relatorio-AcessoPasta.ps1 -Menu
```

Use nomes e caminhos do seu ambiente no lugar dos exemplos: `SRV1`, `RH` e
`usuario.teste` não são valores que o programa descobre automaticamente.
Os horários se referem à consulta executada; confira o relógio e o fuso do
ambiente ao comparar eventos. Consulte o [glossário](GLOSSARIO.md) quando precisar.

Veja a [referência das opções](PARAMETROS.md). **Enter** mantém o valor,
**`-`** limpa um filtro ou desativa um CSV, **E** executa e **Q** sai.

## Acessos à pasta RH no último dia

1. Em **1**, informe o servidor de arquivos.
2. Em **2**, selecione `5145` para verificações pela rede SMB.
3. Em **3**, escolha últimos N dias e informe `1`.
4. Em **4**, informe `RH` ou o caminho completo da pasta.
5. Em **5**, use `*` para todos os usuários.
6. Em **9** e **10**, confira os destinos dos CSVs.
7. Digite **E** e confirme. Após a execução, pressione Enter para voltar.

**Resultado esperado:** o CSV detalhado terá os eventos de verificação pela
rede que passaram pelos filtros de servidor, período e pasta. Um 5145 pode
mostrar uma verificação sem comprovar leitura do documento. Se não aparecerem
linhas, confira os avisos e a auditoria antes de concluir que ninguém acessou.

**Como conferir o arquivo:** use o caminho informado na opção 9. No Excel,
se os dados aparecerem em uma única coluna, importe o arquivo como texto/CSV e
selecione o separador ponto e vírgula (`;`). Confira a data de criação do arquivo
para não abrir o resultado de uma execução anterior.

## Todas as pastas e contas em vários servidores

1. Em **1**, informe `SRV1,SRV2`.
2. Em **4**, digite `-` para remover o filtro de pasta.
3. Em **5**, informe `*` para todos os usuários.
4. Em **8**, marque `IncluirContasComputador` e
   `IncluirCompartilhamentosEspeciais` pelos números exibidos; Enter volta.
5. Ajuste **3**, **9** e **10**, depois execute com **E**.

**Por que marcar essas opções:** contas de computador e compartilhamentos
administrativos são normalmente omitidos para reduzir o volume. Incluí-los
ajuda em consultas mais amplas, mas também traz registros de serviços e tarefas
automáticas. Isso pode aumentar bastante o tamanho do resultado.

**O que conferir:** procure a coluna Servidor no detalhado e leia os avisos por
computador. Se um servidor falhar, o resultado dos demais não comprova que a
consulta cobriu todos eles.

## Um usuário, um período e vários eventos no mesmo relatório

1. Em **2**, informe `5145,5140,4663,4660`.
2. Em **3**, escolha período específico e preencha início e fim.
3. Em **5**, informe `usuario.teste`. Ative nome exato somente se a grafia
   coincidir com o log, incluindo maiúsculas/minúsculas.
4. Em **9** e **10**, informe os nomes dos arquivos; `{data}` acrescenta data/hora.
5. Execute com **E**. O CSV detalhado reúne os eventos e identifica cada um
   pela coluna `EventoId`; o resumo considera o conjunto selecionado.

Eventos diferentes da mesma operação são evidências distintas; a soma não
representa necessariamente operações únicas. O 4660 lê seus eventos de apoio
automaticamente, sem exportá-los a menos que também sejam selecionados.

**Quando usar esse processo:** uma investigação sobre uma pessoa ou intervalo
específico. Comece com uma janela curta para conferir se o usuário e os eventos
estão corretos. Depois amplie o período, se necessário. Se ativar nome exato e
não encontrar nada, revise a grafia ou teste um padrão na opção 5.

## Tamanho e duração do log

Escolha **L — Detalhes dos logs**, no início do menu. Informe servidor e nome
do log (`Security` por padrão). Confira tamanho, limite, espaço restante,
registros, datas, médias e estimativas. Responda `S` para contar eventos por dia.
Essa contagem lê todo o log e pode demorar. Enter retorna ao menu principal.
As estimativas pressupõem volume constante; pré-alocação pode distorcê-las.
Em log circular cheio, eventos novos substituem os antigos.

**Exemplo de leitura:** se o evento mais antigo tem quatro dias e o mais
recente é de agora, o intervalo disponível é de aproximadamente quatro dias.
Isso não garante atividade em cada dia. Se o tamanho estiver no limite e o modo
for Circular, os eventos novos continuam chegando enquanto os antigos são
substituídos.

A média de registros por dia é uma divisão do total pelo intervalo. Para saber
quantos eventos existem em uma data específica, solicite a contagem por dia.
Ela usa o histórico ainda disponível, não recupera eventos apagados e pode
mudar enquanto novas ocorrências são gravadas ou antigas são substituídas.

## Ações e exclusões em arquivos

Em **2**, escolha `4663` para direitos utilizados no objeto ou `4660` para
exclusões. Em **3**, defina uma janela curta; em **4**, informe por exemplo
`E:\FileServer\TI\TESTES`. Confira o CSV em **9** e execute com **E**.

| Coluna | Conteúdo |
| --- | --- |
| Acao | Classificação baseada nos direitos e no tipo de evento |
| Evidencia | Explica o que o evento permite concluir |
| RecordIdAbertura | Registro 4656, quando usado; fica vazio na alternativa sem abertura |
| EventoCorrelacao | 4656 ou 4663: origem do caminho associado à exclusão |
| RecordIdCorrelacao | Registro que forneceu o caminho |
| RecordIdAcesso | Registro 4663 com DELETE, quando disponível |

`0x80` e `0x20000` são consulta de metadados. Gravação é **Gravação ou criação**: não distingue arquivo novo de arquivo editado. O uso do direito DELETE em 4663 não é apresentado como exclusão confirmada; isso exige 4660.

### Como o relatório encontra o nome de um arquivo excluído

O evento 4660 registra a exclusão, mas não informa o nome do arquivo. Para
preencher esse nome, o script procura outras evidências próximas:

1. Lê eventos de abertura, acesso e fechamento, além de reinícios e limpeza do log.
2. Verifica se eles combinam em servidor, conta, sessão, processo e identificador
   do objeto aberto. Esses termos estão explicados no [glossário](GLOSSARIO.md).
3. Procura primeiro uma abertura 4656 válida nos cinco minutos anteriores à exclusão.
4. Se não houver abertura válida, procura um acesso 4663 com direito DELETE,
   resultado de êxito e caminho do objeto nos 30 segundos anteriores ao 4660.
5. Se as evidências não forem suficientes, deixa o caminho vazio. O script não
   escolhe um nome apenas porque os horários são parecidos.

Para buscar apoio de uma exclusão logo no começo do período, a leitura começa
cinco minutos antes. Esses eventos anteriores não viram linhas do período
solicitado. Um fechamento, nova abertura, caminho conflitante ou reinício pode
invalidar a associação anterior.

Sem correlação, a exclusão aparece com caminho vazio e aviso. Com filtro de pasta, essas linhas não aparecem porque não é possível atribuí-las à pasta; a contagem fica no `.execucao.csv`. O cache tem limite de 10.000 handles; se precisar reiniciá-lo, avisa e registra a limitação.

Com nome exato ativado na opção **5**, o usuário também é filtrado diretamente no log em modo 4660, preservando eventos de reinício e limpeza. Sem essa opção, o filtro de usuário continua após a leitura. A grafia deve coincidir com o log, incluindo maiúsculas e minúsculas. O `.execucao.csv` informa `InicioConsulta` (leitura real) e `ExclusoesAnterioresComoApoio`. No modo 4660, o limite da opção **12** conta também o apoio anterior ao período; a leitura é cronológica e atingir o limite pode produzir resultado parcial. Prefira janelas curtas.

A leitura do CSV não substitui a auditoria: habilite File System e as entradas de SACL para criar/gravar/excluir. Para registrar fechamentos 4658, configure também **Handle Manipulation / Manipulação de Identificadores**, conforme a política da empresa. Metadados, gravação, DELETE_CHILD sozinho e DELETE com falha não alimentam a alternativa. O 4663 sozinho não confirma exclusão: é necessário o 4660 posterior. Logs ausentes, contexto inconsistente ou evidências fora do período/limite podem deixar o caminho vazio. O script não altera a política nem a SACL.

## Lista de grupos autorizados

Em **11**, informe o caminho do CSV `Pasta;Grupo`. A consulta requer
ActiveDirectory/RSAT e acesso ao domínio. Adapte o
[modelo](../examples/ListaAutorizados-exemplo.csv) e siga o
[guia da opção 11](LISTA-AUTORIZADOS.md).

## Entender o relatório

| Evento | O que mostra |
| --- | --- |
| 5145 | Verificação SMB; não comprova leitura do conteúdo |
| 5140 | Conexão ao compartilhamento, sem detalhar cada arquivo |
| 4663 | Uso de direito auditado no objeto; exige File System e SACL |
| 4660 | Exclusão registrada; caminho depende da correlação |

Na opção **8**, mantenha Agrupar desativado para preservar cada evento.
ConcedidoPor identifica uma regra de permissão, não quem configurou a pasta.
Sem eventos não significa ausência de acessos. A execução não altera permissões
nem habilita auditoria.

O progresso separa eventos selecionados e apoio, com o horário processado.
O arquivo `<arquivo-detalhado>.execucao.csv` registra contagens e estado por
servidor. Proteja os CSVs: contêm usuários, IPs e caminhos. Confira a data e
os avisos: um CSV antigo pode permanecer quando a consulta não encontra registros.
