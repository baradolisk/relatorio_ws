# Exemplos de uso

Execute a partir da pasta principal do repositório. Ajuste servidores, usuários e datas.

## Menu interativo

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Menu

# Abrir com valores preenchidos
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Menu -Pasta "RH" -Dias 5
```

As opções são as do relatório original. Enter mantém o valor; `-` limpa um filtro ou caminho. Em período específico, deixe o fim vazio para consultar até agora, ou use `-` para apagar um fim já preenchido. Uma nova data inicial é obrigatória. O comando mostrado usa o caminho completo do arquivo; revise-o antes de agendar e omita `-Menu`.

A execução não altera permissões nem habilita auditoria. O menu não integra o inventário de permissões e não substitui a classificação por SID da v8.

## Todas as pastas e contas

Sem Pasta, consulta todas as pastas presentes nos eventos. As duas opções abaixo incluem também contas de computador e compartilhamentos administrativos:

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 `
    -Dias 1 `
    -IncluirContasComputador `
    -IncluirCompartilhamentosEspeciais `
    -CsvSaida "C:\Relatorios\acessos-{data}.csv" `
    -CsvResumo "C:\Relatorios\resumo-{data}.csv"
```

Para vários servidores, acrescente `-Computador "SRV1","SRV2"`. Não há descoberta automática de servidores do domínio.

## Usuário, período e três eventos

```powershell
$opcoes = @{
    Inicio       = [datetime]::new(2026, 10, 15)
    Fim          = Get-Date
    Usuario      = "usuario.teste"
    UsuarioExato = $true
    Silencioso   = $true
}

foreach ($evento in 5145, 5140, 4663) {
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 @opcoes `
        -EventoId $evento `
        -CsvSaida "C:\Relatorios\detalhado-$evento-{data}.csv" `
        -CsvResumo "C:\Relatorios\resumo-$evento-{data}.csv"
}
```

Não combine Dias com Inicio/Fim. UsuarioExato exige a mesma grafia do log, incluindo maiúsculas e minúsculas. Cada evento gera arquivos separados; o script não os correlaciona automaticamente.

## Comparar com grupos autorizados

Copie o [modelo CSV](../examples/ListaAutorizados-exemplo.csv) e preencha caminhos e grupos aprovados pela empresa. Use caminhos completos, sem curingas.

```powershell
.\scripts\acessos\Relatorio-AcessoPasta-v8.ps1 `
    -Computador "SRV-ARQ1" `
    -Dias 1 `
    -ListaAutorizados "C:\Configuracao\autorizados.csv" `
    -ServidorAD "dc1.empresa.local" `
    -CsvSaida "C:\Relatorios\acessos-{data}.csv"
```

Requer ActiveDirectory/RSAT. A regra mais específica prevalece; grupos na mesma regra são alternativas. Uma regra local, como `E:\FileServer\RH`, vale para esse caminho em todos os servidores consultados. Para identificar um servidor específico em eventos SMB, prefira o caminho de rede exibido no CSV.

| Resultado | Significado |
| --- | --- |
| Autorizado | SID encontrado em um grupo permitido |
| NAO AUTORIZADO | Nenhum grupo permitido confirmou o SID, com consultas completas |
| Sem regra | Nenhuma regra corresponde ao caminho |
| Indeterminado | Faltam dados para concluir, por exemplo grupo indisponível ou SID ausente |

Os grupos refletem a situação atual, não a data histórica do evento. Confira também o arquivo `.cobertura.csv`. A classificação anterior do script original usa nome e trecho de caminho; prefira a v8 para essa análise.

## Entender o relatório

| Evento | O que mostra |
| --- | --- |
| 5145 | Verificação de acesso pela rede SMB; não comprova leitura do conteúdo |
| 5140 | Acesso ao compartilhamento, sem detalhar cada arquivo |
| 4663 | Uso de direito auditado no objeto; exige política File System e auditoria na pasta (SACL) |

Para preservar cada evento, gere o detalhado sem Agrupar. ConcedidoPor mostra a regra de permissão identificada, não quem configurou a pasta. Sem eventos não significa ausência de acessos.

O inventário de permissões mostra regras individuais (ACEs), não a permissão efetiva de cada funcionário. Examina pastas até a profundidade escolhida, não arquivos individuais ou compartilhamentos administrativos.

Proteja os CSVs: eles contêm usuários, IPs e caminhos. Eles usam separador `;`. Arquivos antigos podem permanecer quando uma consulta não encontra registros; confira data e avisos da execução.
