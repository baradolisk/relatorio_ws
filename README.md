# Relatórios de arquivos compartilhados

Veja quem acessou pastas no Windows Server e exporte os resultados para CSV.

## Começar

1. Baixe em **Code → Download ZIP** e extraia os arquivos.
2. No servidor de arquivos, abra o PowerShell como administrador na pasta extraída.
3. Confira se a [auditoria está habilitada](docs/AUDITORIA-WINDOWS.md).
4. Execute:

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 `
    -Pasta "RH" `
    -Dias 1 `
    -CsvSaida "C:\Relatorios\RH-{data}.csv"
```

Troque `RH` pela pasta desejada. O CSV será salvo em `C:\Relatorios` com a data no nome.
**Para todas as pastas, remova `-Pasta "RH"`.** Por padrão, a consulta é no servidor local e ignora contas terminadas em `$` e compartilhamentos administrativos.

Se o Windows bloquear o arquivo, consulte [como desbloquear](docs/SOLUCAO-DE-PROBLEMAS.md#script-bloqueado).

## Prefere escolher as opções na tela?

```powershell
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Menu
```

O menu já vem com o último dia, todas as pastas/usuários e dois CSVs em `C:\Relatorios` (na unidade do Windows). Altere somente o que precisar. **E** executa; **Q** sai.
Enter mantém o valor; `-` limpa um filtro ou caminho. O menu mostra o comando equivalente antes de executar. Por padrão, gera os CSVs sem tabelas extensas no console. A opção 12 permite limitar eventos para diagnóstico (o resultado pode ser parcial).

O menu está no relatório original. Para tarefas agendadas, continue usando os parâmetros sem `-Menu`.

## Qual script usar?

| Quero… | Script |
| --- | --- |
| Consultar acessos por nome ou caminho de pasta | [Relatório de acessos](scripts/acessos/Relatorio-AcessoPasta.ps1) |
| Comparar acessos com grupos autorizados | [Relatório de acessos v8](scripts/acessos/Relatorio-AcessoPasta-v8.ps1) |
| Listar permissões das pastas compartilhadas | [Relatório de permissões v2](scripts/permissoes/Relatorio-PermissoesPasta-v2.ps1) |

Na v8, use caminhos completos nas regras. Para filtrar por rede, use o nome que aparece no CSV; para o evento 4663, use caminho local. O original tem o tratamento de nomes de rede mais completo; prefira a v8 para classificar autorização por grupos.

## Exemplos rápidos

```powershell
# Toda a raiz local
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Pasta "E:\FileServer" -Dias 1

# Um compartilhamento em outro servidor
.\scripts\acessos\Relatorio-AcessoPasta.ps1 -Computador "SRV-ARQ1" -Pasta "\\SRV-ARQ1\z" -Dias 1

# Permissões das pastas, até dois níveis abaixo da raiz
.\scripts\permissoes\Relatorio-PermissoesPasta-v2.ps1 -Profundidade 2 -CsvSaida "C:\Relatorios\permissoes-{data}.csv"
```

`z` é um exemplo de nome de compartilhamento. Confira os nomes reais com `Get-SmbShare | Select-Object Name, Path`.

## Ver o que o usuário fez

No relatório original, o CSV detalhado inclui **Acao**, **Evidencia** e **RecordIdAbertura**. O resumo inclui **Acoes** e **Evidencias**.

- **4663:** leitura, gravação/criação, atributos e direitos de exclusão.
- **4660:** exclusão confirmada; o caminho depende de correlação com eventos de abertura do objeto.
- **5145:** verificação de acesso, não confirmação da operação.

O log não separa com segurança “novo” de “editado”. Veja [como consultar ações](docs/EXEMPLOS.md#ações-nos-arquivos).
A versão anterior está preservada em [legacy/acessos](legacy/acessos/Relatorio-AcessoPasta-antes-acoes.ps1).

## Antes de analisar

- É necessário ter acesso ao log de Segurança. Auditoria só registra eventos depois de habilitada.
- O evento padrão, **5145**, verifica acesso pela rede; êxito não comprova leitura do conteúdo.
- Os scripts leem o log ativo, não os arquivos `.evtx` arquivados.
- Comece com períodos curtos. A consulta pode demorar em servidores movimentados.
- Os testes automatizados usam PowerShell 7 e dados simulados. Valide em Windows antes de usar os resultados para decisões de acesso. Referência de compatibilidade: PowerShell 5.1 ou posterior.

## Onde encontrar

| Pasta | Conteúdo |
| --- | --- |
| `scripts/` | Relatórios de acessos e permissões |
| `examples/` | [Modelo de grupos autorizados](examples/ListaAutorizados-exemplo.csv) |
| `docs/` | Guias e [histórico de alterações](docs/ALTERACOES-RELATORIOS.txt) |
| `tests/` | Validação automatizada |
| `legacy/` | Versões anteriores de acessos e permissões |

**Atualizou de uma versão antiga?** Os scripts saíram da raiz. Ajuste os caminhos nos comandos e nas tarefas agendadas.

## Precisa de mais opções?

[Exemplos de uso](docs/EXEMPLOS.md) · [Parâmetros](docs/PARAMETROS.md) · [Configurar auditoria e logs](docs/AUDITORIA-WINDOWS.md) · [Resolver problemas](docs/SOLUCAO-DE-PROBLEMAS.md) · [Contribuir](CONTRIBUTING.md)
