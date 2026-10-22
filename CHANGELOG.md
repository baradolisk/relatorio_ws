# Alterações

## Organização atual

- Um único relatório: `Relatorio-AcessoPasta.ps1`, na raiz.
- Removidos inventários de permissões, cópias antigas e a pasta legacy.
- Guias, exemplos e testes alinhados ao arquivo atual.
- A lógica de consulta foi preservada nesta limpeza. Versões anteriores continuam no histórico do Git.

## Recursos disponíveis

- Menu com valores iniciais editáveis e execução por parâmetros.
- Eventos 5145, 4663, 4660 e 5140; filtros por período, pasta, usuário e servidor.
- CSV detalhado com ação/evidência, resumo e diagnóstico de execução.
- Exclusões correlacionadas com 4656 ou 4663 DELETE próximo; leitura de cinco minutos anteriores para apoio.
- Filtro de usuário exato no log, progresso por horário, limite opcional e aviso de parcialidade.

Veja requisitos e limites no [README](README.md) e nos guias em `docs/`.
