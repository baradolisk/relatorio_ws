# Exemplos de uso

Execute a partir da pasta principal do repositório. Ajuste servidores, usuários e datas.

## Menu interativo

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Menu

# Abrir com valores preenchidos
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Menu -Pasta "RH" -Dias 5
```

Valores iniciais do menu:

| Opção | Padrão |
| --- | --- |
| Servidor | Computador local |
| Evento | 5145 |
| Período | Último dia; ao escolher período específico, início sugerido e fim até agora |
| Pasta / usuário / resultado | Todas / todos / todos |
| Nome exato / exclusão de usuários | Desativado / nenhuma exclusão |
| CSV detalhado | `C:\Relatorios\acessos-{data}.csv` |
| CSV resumo | `C:\Relatorios\resumo-{data}.csv` |
| Lista de autorizados | Desativada; exige seu CSV de regras |
| Opções adicionais | Silencioso ativado; demais desativadas. Altere na opção 8 |
| Limite de diagnóstico | Zero: sem limite. Altere na opção 12 |

Os CSVs usam a unidade do Windows quando diferente de C:. Digite `-` no campo para desativar um arquivo. Os padrões valem **só no menu**; valores informados junto de `-Menu` têm prioridade. Na linha de comando sem menu, os padrões anteriores permanecem.

Na escolha de evento, digite `5145`, `4663`, `5140` ou `4660`; também são aceitas as opções `1`, `2`, `3` e `4`, respectivamente. Enter mantém o evento atual.

As opções são as do relatório original. Enter mantém o valor; `-` limpa um filtro ou caminho. Em período específico, deixe o fim vazio para consultar até agora, ou use `-` para apagar um fim já preenchido. Enter aceita a data inicial sugerida. O comando mostrado usa o caminho completo do arquivo; revise-o antes de agendar e omita `-Menu`.

O progresso separa eventos do tipo selecionado e eventos de apoio, mostrando também o horário que está sendo processado. A execução mostra progresso e salva `<CsvSaida>.execucao.csv` com contagem, duração e estado por servidor. ResolverSids fica desativado: ConcedidoPor pode conter o SID em vez do nome; habilite se precisar da tradução.

A execução não altera permissões nem habilita auditoria. O menu não integra o inventário de permissões.

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

Não combine Dias com Inicio/Fim. UsuarioExato exige a mesma grafia do log, incluindo maiúsculas e minúsculas. Os três tipos geram arquivos separados; esses CSVs não são cruzados entre si.

## Ações nos arquivos

Use o original atualizado com evento 4663 para mostrar direitos utilizados no objeto:

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 `
    -Pasta "E:\FileServer\TI\TESTES" `
    -Inicio (Get-Date).AddMinutes(-30) `
    -Fim (Get-Date) `
    -EventoId 4663 `
    -CsvSaida "C:\Relatorios\acoes-{data}.csv" `
    -Silencioso
```

Para exclusões, repita com `-EventoId 4660`. No menu, é a opção de evento **4**.

| Coluna | Conteúdo |
| --- | --- |
| Acao | Classificação baseada nos direitos e no tipo de evento |
| Evidencia | Explica o que o evento permite concluir |
| RecordIdAbertura | Registro 4656, quando usado; fica vazio na alternativa sem abertura |
| EventoCorrelacao | 4656 ou 4663: origem do caminho associado à exclusão |
| RecordIdCorrelacao | Registro que forneceu o caminho |
| RecordIdAcesso | Registro 4663 com DELETE, quando disponível |

`0x80` e `0x20000` são consulta de metadados. Gravação é **Gravação ou criação**: não distingue arquivo novo de arquivo editado. O uso do direito DELETE em 4663 não é apresentado como exclusão confirmada; isso exige 4660.

**Correlação de exclusão:** o 4660 não traz o nome do objeto. O script consulta também 4656, 4658, 4663 e eventos de reinício/limpeza, em ordem cronológica, usando servidor, SID, sessão, processo e handle. Prioriza abertura 4656 dentro da janela consultada e até cinco minutos antes da exclusão. Sem abertura válida, aceita 4663 com DELETE (`0x10000`, inclusive em máscaras combinadas), êxito e nome do objeto, até 30 segundos antes do 4660. As evidências precisam coincidir em servidor, SID, sessão, processo e handle; o CSV informa a fonte utilizada. Um fechamento, nova abertura, caminho conflitante, reinício ou contexto inválido impede aproveitar o caminho antigo.

Sem correlação, a exclusão aparece com caminho vazio e aviso. Com filtro de pasta, essas linhas não aparecem porque não é possível atribuí-las à pasta; a contagem fica no `.execucao.csv`. O cache tem limite de 10.000 handles; se precisar reiniciá-lo, avisa e registra a limitação.

Com UsuarioExato, o usuário também é filtrado diretamente no log em modo 4660, preservando eventos de reinício e limpeza. Sem essa opção, o filtro de usuário continua após a leitura. A grafia deve coincidir com o log, incluindo maiúsculas e minúsculas. MaxEventos também conta os eventos de suporte e lê os primeiros em ordem cronológica; atingir o limite pode produzir resultado parcial. Prefira janelas curtas.

A leitura do CSV não substitui a auditoria: habilite File System e as entradas de SACL para criar/gravar/excluir. Para registrar fechamentos 4658, configure também **Handle Manipulation / Manipulação de Identificadores**, conforme a política da empresa. Metadados, gravação, DELETE_CHILD sozinho e DELETE com falha não alimentam a alternativa. O 4663 sozinho não confirma exclusão: é necessário o 4660 posterior. Logs ausentes, contexto inconsistente ou evidências fora do período/limite podem deixar o caminho vazio. O script não altera a política nem a SACL.

## Lista de grupos autorizados

`-ListaAutorizados` aceita um CSV `Pasta;Grupo` e requer ActiveDirectory/RSAT. Adapte o [modelo](../examples/ListaAutorizados-exemplo.csv) às regras aprovadas pela empresa.

A implementação disponível é auxiliar: usa nome de usuário e trecho do caminho. Nomes iguais em domínios diferentes, pastas com nomes parecidos e consultas parciais de grupos podem produzir classificações incorretas. Confira as permissões e a identidade antes de concluir que um acesso é autorizado ou indevido. Os grupos consultados são os atuais, não os históricos.

## Entender o relatório

| Evento | O que mostra |
| --- | --- |
| 5145 | Verificação de acesso pela rede SMB; não comprova leitura do conteúdo |
| 5140 | Acesso ao compartilhamento, sem detalhar cada arquivo |
| 4663 | Uso de direito auditado no objeto; exige política File System e auditoria na pasta (SACL) |
| 4660 | Exclusão registrada; nome do objeto depende da correlação |

Para preservar cada evento, gere o detalhado sem Agrupar. ConcedidoPor mostra a regra de permissão identificada, não quem configurou a pasta. Sem eventos não significa ausência de acessos.

O inventário de permissões mostra regras individuais (ACEs), não a permissão efetiva de cada funcionário. Examina pastas até a profundidade escolhida, não arquivos individuais ou compartilhamentos administrativos.

Proteja os CSVs: eles contêm usuários, IPs e caminhos. Eles usam separador `;`. Arquivos antigos podem permanecer quando uma consulta não encontra registros; confira data e avisos da execução.
