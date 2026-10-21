# Parâmetros

Os exemplos de execução pressupõem a raiz do repositório como diretório atual.

Opções de ativação (`switch`) são usadas sem valor, por exemplo `-Silencioso`.
Em uma hashtable de splatting: `Silencioso = $true`. O nome do usuário vai em
`-Usuario "usuario"`, nunca em `-UsuarioExato "usuario"`.

## Relatorio-AcessoPasta.ps1 (original corrigido)

| Parâmetro | Uso / padrão |
| --- | --- |
| `Pasta` | Trecho ou caminho local/UNC. Opcional; sem ele, todas as pastas presentes nos eventos. Busca por trecho pode incluir nomes parecidos. |
| `Dias` | Dias anteriores, 1 a 3650; padrão 1. Não combinar com Inicio/Fim. |
| `Inicio` | Início de janela específica; obrigatório quando se usa o conjunto de parâmetros de período. |
| `Fim` | Fim da janela; com Inicio, padrão até o momento da execução. |
| `EventoId` | Um dos valores 5145, 5140 ou 4663; padrão 5145. |
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
| `ListaAutorizados` | CSV Pasta;Grupo; requer AD/RSAT. Implementação antiga por nome/trecho: para classificação, prefira v8. |
| `EnriquecerAD` | Acrescenta departamento/cargo; requer AD/RSAT. |
| `ResolverIP` | DNS reverso do IP; pode ser lento ou não refletir o nome real da estação. |
| `CsvResumo` | CSV agregado por usuário e pasta; aceita `{data}`. |
| `Silencioso` | Oculta tabelas, não todos os avisos ou mensagens. |
| `GridView` | Mostra objetos em Out-GridView; requer interface gráfica. |
| `PassThru` | Retorna objetos ao pipeline. |

Exemplo de objetos, sem exportação obrigatória:

```powershell
$registros = .\scripts\acessos\Relatorio-AcessoPasta.ps1 -Dias 1 -Silencioso -PassThru
$registros | Where-Object Resultado -eq 'Falha'
```

## Relatorio-AcessoPasta-v8.ps1

Possui os parâmetros acima e acrescenta:

| Parâmetro | Uso |
| --- | --- |
| `ServidorAD` | Servidor/controlador/domínio para consulta inicial ao AD. |
| `CsvCobertura` | Caminho de cobertura por servidor; se omitido com CsvSaida, usa `<CsvSaida>.cobertura.csv`. |

Na v8, a lista de autorizados exige caminhos completos; correspondência de raiz
ou descendente, sem curingas. Consulta grupos por SID e trata falhas como
Indeterminado. Veja limitações de nomes UNC e 4663 no README.

## Inventário de permissões

| Parâmetro | Uso / padrão |
| --- | --- |
| `Computador` | Um ou mais servidores; padrão local. |
| `Compartilhamento` | Filtro com curingas pelo nome do share; padrão `*`. |
| `Profundidade` | Níveis de subpastas abaixo da raiz, 0 a 10; padrão 1. Zero examina apenas a raiz. |
| `SomenteAmplas` | Restringe o relatório a ACEs identificadas como amplas. |
| `CsvSaida` | CSV de permissões; aceita `{data}`. |
| `CsvCobertura` | Somente v2: falhas e conclusão da coleta; automático com CsvSaida se omitido. |

Ambos inventariam compartilhamentos não administrativos. Não há parâmetro para
inventariar arquivos individuais ou incluir shares administrativos nesses scripts.

## Ajuda integrada

```powershell
Get-Help .\scripts\acessos\Relatorio-AcessoPasta.ps1 -Full
Get-Command .\scripts\acessos\Relatorio-AcessoPasta.ps1 -Syntax
```

São aceitos também parâmetros comuns do PowerShell, como Verbose e ErrorAction.
