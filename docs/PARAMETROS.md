# Parâmetros

Os exemplos de execução pressupõem a raiz do repositório como diretório atual.

Opções de ativação (`switch`) são usadas sem valor, por exemplo `-Silencioso`.
Em uma hashtable de splatting: `Silencioso = $true`. O nome do usuário vai em
`-Usuario "usuario"`, nunca em `-UsuarioExato "usuario"`.

## Opções do relatório

| Parâmetro | Uso / padrão |
| --- | --- |
| `MaxEventos` | máximo de eventos lidos por servidor, antes dos filtros locais. Zero (padrão) não limita. Atingir o limite pode deixar o resultado parcial. |
| `ResolverSids` | traduz SIDs para nomes usando o domínio. Desativado por padrão para evitar esperas; SID continua no relatório. |
| `Menu` | abre as opções na tela. Omita em tarefas agendadas. |
| `Pasta` | Trecho ou caminho local/UNC. Opcional; sem ele, todas as pastas presentes nos eventos. Busca por trecho pode incluir nomes parecidos. |
| `Dias` | Dias anteriores, 1 a 3650; padrão 1. Não combinar com Inicio/Fim. |
| `Inicio` | Início de janela específica; obrigatório quando se usa o conjunto de parâmetros de período. |
| `Fim` | Fim da janela; com Inicio, padrão até o momento da execução. |
| `EventoId` | Um dos valores 5145, 5140, 4663 ou 4660; padrão 5145. 4660 inclui eventos de suporte para correlacionar o caminho. |
| `Usuario` | Nome ou padrão com curingas; aceita DOMINIO\usuario; padrão `*`. |
| `UsuarioExato` | Ativa filtro otimizado por nome exato no log, sensível à caixa, quando o nome permite. Não recebe texto. |
| `Computador` | Um ou mais servidores: `"SRV1","SRV2"`; padrão computador local. |
| `IgnorarAtributos` | Descarta máscaras consideradas ruído; pode remover atividade relevante à investigação. |
| `Agrupar` | Consolida eventos semelhantes no mesmo minuto; não preserva cada evento no CSV. |
| `Resultado` | Todos, Exito ou Falha; padrão Todos. |
| `IncluirContasComputador` | Inclui contas com nome terminado em `$`. |
| `CsvSaida` | CSV detalhado; aceita `{data}` no nome. |
| `ExcluirUsuarios` | Lista de padrões de usuários/contas a excluir. |
| `IncluirCompartilhamentosEspeciais` | Inclui IPC$, ADMIN$, print$ e compartilhamentos de unidade como C$. |
| `ListarCompartilhamentos` | Consulta inventário dos servidores informados; não descobre servidores do domínio. |
| `ListaAutorizados` | CSV Pasta;Grupo; requer AD/RSAT. Comparação auxiliar por nome e trecho; não comprova autorização efetiva. |
| `EnriquecerAD` | Acrescenta departamento/cargo; requer AD/RSAT. |
| `ResolverIP` | DNS reverso do IP; pode ser lento ou não refletir o nome real da estação. |
| `CsvResumo` | CSV agregado por usuário e pasta; aceita `{data}`. |
| `Silencioso` | Oculta tabelas, não todos os avisos ou mensagens. |
| `GridView` | Mostra objetos em Out-GridView; requer interface gráfica. |
| `PassThru` | Retorna objetos ao pipeline. |

Exemplo de objetos, sem exportação obrigatória:

```powershell
$registros = .\Relatorio-AcessoPasta.ps1 -Dias 1 -Silencioso -PassThru
$registros | Where-Object Resultado -eq 'Falha'
```

## Ajuda integrada

```powershell
Get-Help .\Relatorio-AcessoPasta.ps1 -Full
Get-Command .\Relatorio-AcessoPasta.ps1 -Syntax
```

São aceitos também parâmetros comuns do PowerShell, como Verbose e ErrorAction.
