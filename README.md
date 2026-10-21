# Relatórios de acessos e permissões no Windows Server

Scripts PowerShell para investigar acessos a arquivos compartilhados, exportar eventos para CSV e inventariar permissões SMB/NTFS em servidores Windows com domínio.

Os scripts consultam dados; não alteram permissões nem habilitam auditoria automaticamente. Para identificar divergências de negócio, é necessário definir quais grupos deveriam acessar cada pasta.

## Estrutura do repositório

```text
.
├── scripts/
│   ├── acessos/
│   │   ├── Relatorio-AcessoPasta.ps1
│   │   └── Relatorio-AcessoPasta-v8.ps1
│   └── permissoes/
│       └── Relatorio-PermissoesPasta-v2.ps1
├── examples/
│   └── ListaAutorizados-exemplo.csv
├── legacy/
│   └── permissoes/
│       └── Relatorio-PermissoesPasta.ps1
├── docs/
│   ├── PARAMETROS.md
│   ├── AUDITORIA-WINDOWS.md
│   ├── SOLUCAO-DE-PROBLEMAS.md
│   └── ALTERACOES-RELATORIOS.txt
├── tests/
│   └── Test-Relatorios.ps1
├── .github/workflows/validar.yml
├── CONTRIBUTING.md
└── README.md
```

**Execute os exemplos a partir da raiz do checkout.** Os scripts ficam em
`scripts/`, os modelos em `examples/` e a versão anterior de permissões em
`legacy/`. Os scripts continuam independentes e podem ser copiados para outro
local, desde que o comando de execução aponte para o arquivo correto.

### Atualização de instalações existentes

Os arquivos `.ps1` não ficam mais na raiz. Atualize comandos, atalhos e tarefas
agendadas para os caminhos da tabela abaixo; por exemplo,
`.\Relatorio-AcessoPasta.ps1` passou a ser
`.\scripts\acessos\Relatorio-AcessoPasta.ps1`. Se o script foi copiado para
outro diretório fora do checkout, essa cópia não é atualizada pelo Git.
Os parâmetros e a lógica dos relatórios foram preservados nesta reorganização.

## Qual arquivo utilizar?

| Arquivo | Uso |
| --- | --- |
| [Relatorio-AcessoPasta.ps1](scripts/acessos/Relatorio-AcessoPasta.ps1) | Versão original com correção recente de filtros de rede: aceita trecho, caminho local e UNC; traduz UNC para caminho local no evento 4663 quando consegue consultar o inventário SMB. |
| [Relatorio-AcessoPasta-v8.ps1](scripts/acessos/Relatorio-AcessoPasta-v8.ps1) | Revisão com autorização por SID, regras de caminho completo e CSV de cobertura. Indicada quando é necessário classificar acessos com uma lista de autorizados. |
| [Relatorio-PermissoesPasta-v2.ps1](scripts/permissoes/Relatorio-PermissoesPasta-v2.ps1) | Versão recomendada do inventário de ACEs SMB/NTFS, com cobertura de erros. |
| [Relatorio-PermissoesPasta.ps1](legacy/permissoes/Relatorio-PermissoesPasta.ps1) | Versão anterior, preservada para referência; possui falha conhecida de conversão de lista no PowerShell 7.4. Prefira a v2. |
| [ListaAutorizados-exemplo.csv](examples/ListaAutorizados-exemplo.csv) | Modelo fictício para adaptar à política de acesso da empresa. |
| [ALTERACOES-RELATORIOS.txt](docs/ALTERACOES-RELATORIOS.txt) | Histórico detalhado das alterações e limitações. |

As versões de acessos ainda não foram unificadas: a correção UNC mais recente está no **original**. A v8 normaliza `\\*\Share`, mas não possui o mesmo tratamento de nome curto/FQDN, alias e tradução UNC para 4663. No v8, prefira o caminho exibido no CSV; para 4663, use caminho local.

## Requisitos

- Windows Server com PowerShell e os componentes Windows usados pelos scripts. Para o original, utilize Windows PowerShell 5.1 ou posterior; a v8 e o inventário v2 declaram mínimo 5.1.
- Conta com acesso ao log de Segurança e, para inventário, às ACLs e aos compartilhamentos. Para o primeiro teste, execute o PowerShell como administrador no servidor de arquivos.
- Auditoria habilitada **antes** dos acessos que deseja investigar. Consulte [configuração da auditoria](docs/AUDITORIA-WINDOWS.md).
- Para consultas remotas: conectividade e permissões do log de eventos. Inventário SMB remoto utiliza CIM; leitura de ACL utiliza o caminho UNC.
- ActiveDirectory/RSAT somente para `-ListaAutorizados` e `-EnriquecerAD`.
- Interface gráfica somente para `-GridView`.

**Validação:** sintaxe e testes automatizados de funções com dados simulados no PowerShell 7 em Linux. Windows PowerShell 5.1, AD, SMB e logs reais não fazem parte da validação automatizada. Faça um piloto em Windows antes de usar os resultados para decisões de acesso.

## Baixar e preparar

No GitHub, use **Code → Download ZIP**, extraia os arquivos e abra o PowerShell na pasta extraída. Ou, se tiver Git:

```powershell
git clone https://github.com/baradolisk/relatorio_ws.git
Set-Location .\relatorio_ws
```

Após conferir a origem e o conteúdo dos arquivos baixados, se a política permitir scripts locais:

```powershell
Get-ChildItem -Path .\scripts -Filter *.ps1 -Recurse | Unblock-File
Get-ExecutionPolicy -List
```

Não substitua uma política corporativa. Se uma GPO exigir `AllSigned`, os arquivos precisam de assinatura de código confiável. Veja [solução de problemas](docs/SOLUCAO-DE-PROBLEMAS.md).

## Primeiro relatório

No servidor de arquivos, abra um arquivo compartilhado a partir de outra estação e consulte uma janela curta:

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 `
    -Inicio (Get-Date).AddMinutes(-15) `
    -Fim (Get-Date) `
    -EventoId 5145 `
    -CsvSaida "C:\Relatorios\acessos-{data}.csv" `
    -CsvResumo "C:\Relatorios\resumo-{data}.csv"
```

Sem `-Pasta`, consulta todas as pastas presentes nos eventos; sem `-Computador`, consulta somente o computador local. Por padrão, contas terminadas em `$` e compartilhamentos administrativos são excluídos. Acrescente `-IncluirContasComputador` e `-IncluirCompartilhamentosEspeciais` para incluí-los. A busca não descobre automaticamente todos os servidores do domínio.

CSV usa separador `;` e datas formatadas. O token `{data}` é substituído no nome do arquivo. Proteja a pasta dos relatórios: contém nomes de usuários, IPs e caminhos.

### Filtrar pasta ou compartilhamento

```powershell
# Trecho: também pode encontrar RH-antigo, por exemplo.
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Pasta "RH" -Dias 1

# Caminho local: inclui eventos correspondentes sob a raiz informada.
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Pasta "E:\FileServer" -Dias 1

# UNC: use o NOME DO COMPARTILHAMENTO, não o nome da pasta no disco.
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Computador "SRV-ARQ1" -Pasta "\\SRV-ARQ1\z\RH" -Dias 1
```

No exemplo, `z` seria o compartilhamento de `E:\FileServer`. Confirme os nomes reais no servidor:

```powershell
Get-SmbShare | Select-Object Name, Path
```

O original conserva busca por trecho, inclusive para caminhos; não use `-Pasta` como controle de autorização ou garantia de correspondência estrita. Para regras de negócio com limites de diretório, use a lista de autorizados da v8.

### Período, usuário e todos os tipos de evento

Exemplo com datas fictícias: ajuste para a janela desejada. `-Dias` não pode ser combinado com `-Inicio`/`-Fim`. O nome vai em `-Usuario`; `-UsuarioExato` apenas ativa a otimização e diferencia maiúsculas/minúsculas no log.

```powershell
$parametros = @{
    Computador   = "SRV-ARQ1"
    Inicio       = [datetime]::new(2026, 10, 15)
    Fim          = Get-Date
    Usuario      = "usuario.teste"
    UsuarioExato = $true
    Silencioso   = $true
}

foreach ($evento in 5145, 5140, 4663) {
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 @parametros `
        -EventoId $evento `
        -CsvSaida "C:\Relatorios\detalhado-$evento-{data}.csv" `
        -CsvResumo "C:\Relatorios\resumo-$evento-{data}.csv"
}
```

Cada execução aceita **um** tipo de evento. Os arquivos separados não constituem correlação automática entre eventos.

### Autorização por grupos (v8)

Copie `examples/ListaAutorizados-exemplo.csv` para um arquivo próprio e substitua caminhos/grupos pelos reais, aprovados pelo responsável pela pasta. Na v8, `Pasta` deve ser caminho completo, sem curingas. O grupo pode ser qualificado pelo domínio; confira resolução/conectividade do domínio ou use `-ServidorAD`.

```powershell
.\scripts\acessos\Relatorio-AcessoPasta-v8.ps1 `
    -Computador "SRV-ARQ1" `
    -Dias 1 `
    -ListaAutorizados "C:\Configuracao\autorizados.csv" `
    -ServidorAD "dc1.empresa.local" `
    -CsvSaida "C:\Relatorios\acessos-{data}.csv"
```

A regra mais específica prevalece; grupos da mesma regra são alternativas. Resultados: `Autorizado`, `NAO AUTORIZADO`, `Sem regra` ou `Indeterminado`. Falha de consulta de grupo não deve ser tratada como prova de acesso indevido. A associação ao AD reflete o momento da coleta, não a data histórica do evento. `CsvSaida` também gera um arquivo `.cobertura.csv` na v8.

O original mantém uma implementação anterior de autorização por nome e regras por trecho, com os problemas descritos no TXT. **Prefira a v8 para essa classificação.**

### Inventário de permissões

```powershell
.\scripts\permissoes\Relatorio-PermissoesPasta-v2.ps1 `
    -Computador "SRV-ARQ1","SRV-ARQ2" `
    -Profundidade 2 `
    -CsvSaida "C:\Relatorios\permissoes-{data}.csv"
```

O inventário mostra ACEs, não calcula permissões efetivas combinando grupos, compartilhamento, NTFS e negações. A profundidade padrão é 1 e o máximo é 10. Não inventaria arquivos individualmente nem compartilhamentos administrativos. Confira o CSV de cobertura antes de concluir que não existem permissões amplas.

## Interpretar os resultados

| Evento | Evidência e requisito |
| --- | --- |
| 5145 | Verificação de acesso SMB a um objeto. Requer Detailed File Share. Êxito não comprova sozinho leitura do conteúdo. |
| 5140 | Acesso/conexão ao compartilhamento; não detalha cada arquivo. Requer File Share. |
| 4663 | Uso de direitos auditados no objeto; analisar AccessMask. Requer File System e SACL correspondente. |

Sem eventos não significa sem acessos: auditoria desativada, retenção, filtros e erros de leitura podem deixar lacunas. Aumentar o log ou habilitar auditoria não recupera eventos anteriores.

- Para evidência, prefira CSV detalhado **sem `-Agrupar`**. O agrupamento reduz linhas e não preserva cada evento individualmente.
- Os scripts ainda mantêm registros em memória; comece com períodos curtos, especialmente no 5145.
- `ConcedidoPor` indica ACE identificada no AccessReason, não a pessoa que configurou a ACL.
- O original ainda contém mensagens antigas fortes demais sobre êxito e autorização; interprete os eventos conforme esta tabela.
- Os relatórios consultam o log **ativo**. Arquivos `.evtx` arquivados não são pesquisados automaticamente.

## Documentação e desenvolvimento

- [Todos os parâmetros](docs/PARAMETROS.md)
- [Auditoria, tamanho e arquivamento do log](docs/AUDITORIA-WINDOWS.md)
- [Solução de problemas](docs/SOLUCAO-DE-PROBLEMAS.md)
- [Como contribuir e validar](CONTRIBUTING.md)

A configuração de auditoria, GPO, retenção e agendamento deve ser definida pelo administrador do ambiente. Os comandos de configuração são explícitos na documentação; executar os relatórios não os aplica.
