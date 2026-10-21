# Versões anteriores

`permissoes/Relatorio-PermissoesPasta.ps1` é a versão anterior do inventário,
preservada para referência. Possui falha conhecida na conversão de lista no
PowerShell 7.4. Para novas execuções, use
[`scripts/permissoes/Relatorio-PermissoesPasta-v2.ps1`](../scripts/permissoes/Relatorio-PermissoesPasta-v2.ps1).

A versão corrigida do relatório original de acessos permanece em `scripts/acessos/`:
ela possui correções UNC que ainda não foram integralmente portadas à v8.
Consulte a [comparação das versões](../README.md#qual-arquivo-utilizar).
