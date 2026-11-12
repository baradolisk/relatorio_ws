# Configurar auditoria e logs

A auditoria é o que faz o Windows guardar eventos sobre as ações realizadas.
O relatório apenas consulta esse histórico. Se a auditoria não estava habilitada
quando o acesso aconteceu, executar o script depois não recupera esse acesso.

Faça a preparação no servidor que guarda os arquivos, usando uma conta com
permissão administrativa. Em empresas com domínio, peça ao responsável pelo
Windows para conferir as políticas de grupo (GPO): elas podem substituir uma
configuração feita somente no servidor. Consulte o [glossário](GLOSSARIO.md)
para os termos técnicos usados aqui.

Antes de mudar algo, identifique qual evento você precisa: 5145 para verificações
pela rede, 5140 para conexões ao compartilhamento, 4663 para direitos utilizados
em arquivos e 4660 para exclusões. Habilitar mais categorias pode aumentar o
volume do log; escolha as que atendem à sua necessidade.

Para executar o relatório após preparar a auditoria, abra o menu:

```powershell
.\Relatorio-AcessoPasta.ps1 -Menu
```

Os comandos abaixo são de administração e diagnóstico do Windows. Eles preparam
o servidor; não substituem a abertura do relatório pelo menu. Para consultar
tamanho e duração do log no script, escolha **L — Detalhes dos logs**.

## Registrar acessos pela rede — evento 5145

### 1. Verifique se a categoria já está habilitada

O comando abaixo apenas consulta a configuração. A sequência entre chaves é o
identificador da categoria, usado para funcionar em diferentes idiomas do Windows.
Observe se a saída informa auditoria de êxito e/ou falha.


```powershell
auditpol /get /subcategory:"{0CCE9244-69AE-11D9-BED3-505054503030}"
```

### 2. Habilite o registro necessário

O comando seguinte altera a auditoria para registrar êxitos e falhas da categoria.
Use-o quando essa alteração estiver de acordo com a política da empresa. Se a
configuração for administrada pelo domínio, faça o ajuste na GPO correspondente.

```powershell
auditpol /set /subcategory:"{0CCE9244-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable
```

Na GPO: **Configuração do Computador → Políticas → Configurações do Windows → Configurações de Segurança → Configuração Avançada de Política de Auditoria → Políticas de Auditoria → Acesso a Objetos → Auditar Compartilhamento de Arquivos Detalhado**.

### 3. Gere um acesso de teste

Em outra estação, use uma conta de teste e abra um arquivo sem dados sensíveis
pelo compartilhamento. Anote o usuário, o horário e o servidor. Acessar pela rede
é importante: abrir o arquivo diretamente pelo disco do servidor não reproduz
necessariamente uma verificação de compartilhamento.

Por exemplo, abra um arquivo por `\\SERVIDOR\Compartilhamento` em outra estação e consulte:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 5145
    StartTime = (Get-Date).AddMinutes(-15)
} -MaxEvents 5 | Select-Object TimeCreated, Id, Message
```

### 4. Confira o resultado no menu

Abra o relatório com `-Menu`. Na opção **1**, informe o servidor testado; na
**2**, escolha `5145`; na **3**, escolha um período que inclua o teste. Na
primeira tentativa, deixe a pasta sem filtro na opção **4** e use `*` na **5**.
Execute com **E**. Depois que confirmar o evento, acrescente filtros de pasta
e usuário para uma busca mais específica.

Se o comando de diagnóstico e o relatório não encontrarem o evento, volte à
configuração de auditoria, confirme o servidor e consulte o guia de problemas.
A auditoria começa após habilitada; não cria registros retroativos.

## Outros eventos

| Evento | Configuração necessária |
| --- | --- |
| 5140 | Auditar Compartilhamento de Arquivos (File Share); registra conexão ao compartilhamento |
| 4663 | Auditar Sistema de Arquivos (File System) e SACL na pasta/arquivo para os usuários e direitos desejados |
| 4660 | File System e SACL de exclusão; para associar caminho, o relatório precisa também de 4656 e usa 4658 quando disponível |

### Configurar auditoria na pasta para 4663 e 4660

Além de habilitar a categoria File System, configure quais ações da pasta devem
ser auditadas. Essa lista é a SACL; ela registra ações e não concede acesso.

1. Use uma pasta de teste para verificar a configuração antes de ampliá-la.
2. Abra **Propriedades → Segurança → Avançado → Auditoria** na pasta desejada.
3. Adicione ou confira a entrada da conta ou grupo que será acompanhado.
4. Defina o alcance da regra: pasta, subpastas e/ou arquivos. Confira as regras
   herdadas, pois elas podem já cobrir parte do que você precisa.
5. Para testar gravação e exclusão, selecione os direitos correspondentes, como
   criar arquivos/gravar dados, criar pastas/anexar dados, excluir e excluir
   subpastas/arquivos. Os nomes podem variar conforme a versão do Windows.
6. Gere uma ação controlada e consulte `4663` e `4660` pela opção **2** do menu.
   Confira as colunas Acao e Evidencia no CSV.

Para registrar fechamentos 4658, configure também a categoria Handle Manipulation
conforme a política da empresa. Habilitar apenas a política, sem uma SACL
adequada, não é suficiente para registrar as ações pretendidas.

## Aumentar o log para 2 GB

Primeiro, abra **L — Detalhes dos logs** no menu e consulte `Security` no servidor.
Compare o limite com o período que ainda está disponível. Se o histórico for
menor que o necessário, um limite maior pode ajudar, mas o espaço no disco e o
volume de eventos também precisam ser considerados.

O comando abaixo define o limite como 2 GB. Ele não deve ser usado para reduzir
um log que já tenha limite maior sem antes avaliar o impacto na retenção.
Depois, a consulta exibe o limite e o total de registros para você confirmar.

```powershell
wevtutil sl Security /ms:2147483648

Get-WinEvent -ListLog Security |
    Select-Object LogName, @{Name='MaximoMB';Expression={$_.MaximumSizeInBytes / 1MB}}, RecordCount
```

Não limpa o log nem recupera registros perdidos. A duração do histórico depende do volume de eventos. Confira espaço em disco e, se a configuração reverter, a GPO.

## Arquivar ao atingir o limite

No modo circular, o log cheio substitui eventos antigos. Se a empresa precisa
guardar esses eventos em arquivos separados, o Windows pode arquivar o log ao
atingir o limite e continuar a gravação em outro arquivo.

Antes de ativar, defina onde os arquivos serão guardados, quem pode acessá-los,
por quanto tempo serão mantidos e como o espaço será monitorado. O comando
abaixo altera a retenção e ativa o arquivamento automático com limite de 2 GB.
O segundo comando consulta a configuração para conferir o resultado:

```powershell
wevtutil sl Security /ms:2147483648 /rt:true /ab:true
wevtutil gl Security
```

Confira `retention: true`, `autoBackup: true` e `maxSize: 2147483648`. No caminho padrão, liste os arquivos:

```powershell
Get-ChildItem "$env:SystemRoot\System32\winevt\Logs" -Filter 'Archive-Security-*.evtx'
```

Se o log foi movido, confira `logFileName` em `wevtutil gl Security`.

**Monitore o espaço:** arquivos arquivados se acumulam e falta de espaço pode comprometer a coleta. Guarde-os em pasta restrita e defina uma rotina de retenção. Não mova nem apague o arquivo ativo `Security.evtx`.

Os relatórios ainda não leem arquivos arquivados. Abra-os no Visualizador de Eventos ou consulte separadamente com `Get-WinEvent -Path`.

Para voltar à sobrescrita dos eventos antigos quando o log encher, sem arquivamento automático:

```powershell
wevtutil sl Security /rt:false /ab:false
```

Essa opção pode descartar histórico antigo. Escolha conforme a retenção exigida pela empresa.
