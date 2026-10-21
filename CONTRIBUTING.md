# Contribuir

Abra uma issue descrevendo o problema, versão do script, versão do PowerShell,
comando usado e resultado esperado. Remova nomes reais, IPs, caminhos, SIDs e
qualquer dado sensível antes de anexar amostras. Não envie logs de Segurança
completos, relatórios de produção ou credenciais ao repositório.

Para propor alterações, crie uma branch, mantenha compatibilidade com Windows
PowerShell 5.1 e envie um pull request com descrição e validação. Preserve UTF-8
com BOM nos scripts destinados ao 5.1. Não altere ACLs, GPO ou auditoria como
parte implícita da execução dos relatórios.

## Validação local

Na raiz do checkout, com PowerShell:

```powershell
pwsh -NoProfile -File .\tests\Test-Relatorios.ps1
```

O teste valida sintaxe e funções isoladas com dados simulados. Não executa os
relatórios contra logs, AD ou SMB de produção; não muda auditoria nem ACLs.
A integração contínua executa o mesmo comando em Linux com PowerShell 7.
Isso não comprova execução em Windows Server ou Windows PowerShell 5.1.

Para mudanças na coleta, valide também em Windows de teste: usuário permitido,
usuário fora da regra, tentativa bloqueada, grupo indisponível e leitura negada.
Confira quantidade de eventos, filtros, CSV e cobertura; registre versão do
PowerShell e quais testes usaram fontes reais ou simuladas. Zero eventos não
é um teste funcional aprovado.

Evite misturar as versões durante uma correção: declare no PR se a alteração
é do original, v8 ou inventário v2. Veja as diferenças no README. Caso mude
parâmetros ou interpretação dos resultados, atualize a documentação e os testes.
