# Contribuir

Reporte o comando, versão do PowerShell, período, mensagem de erro e resultado esperado. Remova nomes, IPs e caminhos reais das amostras. Não publique credenciais nem logs de produção.

Para alterar:

1. Crie uma branch. Há apenas um relatório: `Relatorio-AcessoPasta.ps1`.
2. Preserve compatibilidade com PowerShell 5.1 e UTF-8 com BOM.
3. Atualize os guias e os testes afetados.
4. Execute na raiz:

```powershell
pwsh -NoProfile -File .\tests\Test-Relatorios.ps1
```

5. Envie um pull request com a mudança e a validação feita.

Os testes usam fontes simuladas no PowerShell 7. Alterações de coleta também precisam de teste em Windows, com log e permissões reais. Zero eventos não comprova funcionamento.

Mantenha o script na raiz, guias em `docs/`, modelos em `examples/` e testes em `tests/`. Use o histórico do Git, sem criar cópias de versões no repositório. A execução do relatório deve continuar somente consultando dados.
