# Como contribuir

Abra uma issue com o script usado, versão do PowerShell, comando, erro e resultado esperado. Remova usuários, IPs e caminhos reais das amostras. Não publique credenciais ou logs de produção.

Para propor uma correção:

1. Crie uma branch e altere a versão correta: original, v8 ou permissões v2.
2. Mantenha compatibilidade com PowerShell 5.1 e UTF-8 com BOM nos scripts.
3. Atualize exemplos, documentação e testes afetados.
4. Execute na raiz:

```powershell
pwsh -NoProfile -File .\tests\Test-Relatorios.ps1
```

5. Abra um pull request descrevendo a mudança e o que foi testado.

Os testes usam funções isoladas e dados simulados no PowerShell 7. Mudanças na coleta também precisam de teste em Windows, com log, AD e SMB reais. Zero eventos não comprova funcionamento.

Mantenha relatórios em `scripts/`, modelos em `examples/`, guias em `docs/` e testes em `tests/`. Versões anteriores ficam em `legacy/`. Ao mover arquivos, ajuste caminhos e informe a migração. A execução dos relatórios deve continuar apenas consultando dados, sem alterar auditoria ou permissões.
