# Relatório de acessos a arquivos

Consulte acessos e exclusões no Windows Server e exporte os resultados para CSV.

## Começar pelo menu

1. Baixe o [script](Relatorio-AcessoPasta.ps1) ou use **Code → Download ZIP**.
2. Abra o PowerShell como administrador na pasta do arquivo.
3. Confira a [auditoria necessária](docs/AUDITORIA-WINDOWS.md) e execute:

```powershell
.\Relatorio-AcessoPasta.ps1 -Menu
```

O menu começa com o último dia, todas as pastas/usuários e CSVs em `C:\Relatorios`, na unidade do Windows. Altere o que precisar. **E** executa; **Q** sai; **Enter** mantém; **`-`** limpa um filtro ou desativa um CSV.

Se o arquivo estiver bloqueado, veja [como liberar](docs/SOLUCAO-DE-PROBLEMAS.md#script-bloqueado).

## Qual evento escolher?

| Evento | Uso |
| --- | --- |
| **5145** — padrão | Verificações de acesso pela rede SMB; não comprova leitura do conteúdo |
| **4663** | Direitos utilizados no objeto: leitura, gravação/criação, atributos e DELETE |
| **4660** | Exclusões; consulta automaticamente os eventos de apoio para identificar o caminho |
| **5140** | Conexões ao compartilhamento, sem detalhe de cada arquivo |

Na opção **2** do menu, informe um ou mais IDs ou opções separados por vírgula
(ex.: `5145,4663,4660` ou `1,2,4`). **Enter** mantém a seleção.
Todos os eventos selecionados entram no mesmo CSV, identificados pela coluna
`EventoId`. O resumo soma os eventos selecionados; eventos diferentes da mesma
operação podem representar mais de uma evidência, não operações únicas.

Opções disponíveis: **1 = 5145**, **2 = 4663**, **3 = 5140**, **4 = 4660**.

## Executar por comando

```powershell
# Acessos à pasta RH no último dia
.\Relatorio-AcessoPasta.ps1 -Pasta "RH" -Dias 1 -CsvSaida "C:\Relatorios\RH-{data}.csv"

# Exclusões de um usuário na última hora
.\Relatorio-AcessoPasta.ps1 `
    -EventoId 4660 `
    -Usuario "usuario.teste" `
    -UsuarioExato `
    -Inicio (Get-Date).AddHours(-1) `
    -Fim (Get-Date) `
    -CsvSaida "C:\Relatorios\exclusoes-{data}.csv" `
    -Silencioso
```

**Todas as pastas:** omita `-Pasta`. **Todos os usuários:** omita `-Usuario`. UsuarioExato exige a mesma grafia do log, incluindo maiúsculas/minúsculas. Para outro servidor, acrescente `-Computador "SRV-ARQ1"`.

Por padrão, contas terminadas em `$` e compartilhamentos administrativos são excluídos. Para incluí-los, use `-IncluirContasComputador` e `-IncluirCompartilhamentosEspeciais`.

Para consultar vários eventos por comando:

```powershell
.\Relatorio-AcessoPasta.ps1 -EventoId 5145,4663,4660 -Dias 1 `
    -CsvSaida "C:\Relatorios\eventos-{data}.csv"
```

A **opção 11** compara os acessos com um CSV `Pasta;Grupo` e exige
ActiveDirectory/RSAT e acesso ao domínio. Veja [pré-requisitos e configuração](docs/LISTA-AUTORIZADOS.md).

## Arquivos gerados

| Arquivo | Conteúdo |
| --- | --- |
| `-CsvSaida` | Detalhado: usuário, caminho, horário, ação e evidência |
| `-CsvResumo` | Resumo por usuário e pasta |
| `<CsvSaida>.execucao.csv` | Contagens, período efetivamente lido, limite e estado da consulta |

`{data}` acrescenta data/hora ao nome. Os CSVs usam `;` como separador. Proteja a pasta de saída: contém dados de usuários e do ambiente.

## Interpretar sem confundir

- **Zero durante o progresso não é o resultado final.** Confira o horário processado e a quantidade do evento escolhido, separados dos eventos de apoio.
- **Gravação ou criação** não distingue com segurança “novo” de “editado”.
- **4660 confirma a exclusão**; o caminho é associado a um 4656 válido ou a um 4663 com DELETE próximo. Sem evidência suficiente, fica vazio.
- O modo 4660 lê cinco minutos anteriores para apoio, sem exportar exclusões anteriores ao período pedido. Isso pode aumentar a leitura.
- O script consulta o log ativo, não arquivos `.evtx` arquivados. Auditoria não recupera eventos anteriores à habilitação.

## Guias

[Exemplos](docs/EXEMPLOS.md) · [Parâmetros](docs/PARAMETROS.md) · [Configurar auditoria e logs](docs/AUDITORIA-WINDOWS.md) · [Resolver problemas](docs/SOLUCAO-DE-PROBLEMAS.md)

Requisitos: Windows Server, PowerShell 5.1 ou posterior e acesso ao log de Segurança. ActiveDirectory/RSAT é opcional para consultas de grupos/cadastro; interface gráfica é opcional para GridView. O relatório apenas consulta dados: não muda auditoria nem permissões. Testes automatizados usam PowerShell 7 e fontes simuladas; valide a configuração no seu servidor.

**Atualizando uma instalação antiga?** O único relatório agora é `Relatorio-AcessoPasta.ps1`, na raiz. Atualize os caminhos nos comandos e nas tarefas agendadas. Versões alternativas foram removidas; o histórico permanece nos commits do Git.

[Alterações](CHANGELOG.md) · [Contribuir](CONTRIBUTING.md)
