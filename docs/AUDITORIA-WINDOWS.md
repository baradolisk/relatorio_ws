# Configurar auditoria e logs

Execute no servidor de arquivos, como administrador. Em domínio, mantenha a configuração na GPO dos servidores para evitar que uma mudança local seja sobrescrita.

## Registrar acessos pela rede — evento 5145

Confira a configuração:

```powershell
auditpol /get /subcategory:"{0CCE9244-69AE-11D9-BED3-505054503030}"
```

Para habilitar êxito e falha:

```powershell
auditpol /set /subcategory:"{0CCE9244-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable
```

Na GPO: **Configuração do Computador → Políticas → Configurações do Windows → Configurações de Segurança → Configuração Avançada de Política de Auditoria → Políticas de Auditoria → Acesso a Objetos → Auditar Compartilhamento de Arquivos Detalhado**.

Depois, abra um arquivo por `\\SERVIDOR\Compartilhamento` em outra estação e consulte:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 5145
    StartTime = (Get-Date).AddMinutes(-15)
} -MaxEvents 5 | Select-Object TimeCreated, Id, Message
```

A auditoria começa após habilitada; não cria registros retroativos.

## Outros eventos

| Evento | Configuração necessária |
| --- | --- |
| 5140 | Auditar Compartilhamento de Arquivos (File Share); registra conexão ao compartilhamento |
| 4663 | Auditar Sistema de Arquivos (File System) e SACL na pasta/arquivo para os usuários e direitos desejados |
| 4660 | File System e SACL de exclusão; para associar caminho, o relatório precisa também de 4656 e usa 4658 quando disponível |

Para a SACL, abra **Propriedades da pasta → Segurança → Avançado → Auditoria**. Confira herança e escopo num teste controlado. Habilitar só a política não basta. Para o teste de criação/edição/exclusão, audite criar arquivos/gravar dados, criar pastas/anexar dados, excluir e excluir subpastas/arquivos. Para os fechamentos 4658, configure também Handle Manipulation conforme a política da empresa.

## Aumentar o log para 2 GB

```powershell
wevtutil sl Security /ms:2147483648

Get-WinEvent -ListLog Security |
    Select-Object LogName, @{Name='MaximoMB';Expression={$_.MaximumSizeInBytes / 1MB}}, RecordCount
```

Não limpa o log nem recupera registros perdidos. A duração do histórico depende do volume de eventos. Confira espaço em disco e, se a configuração reverter, a GPO.

## Arquivar ao atingir o limite

O Windows pode salvar o log cheio e iniciar outro automaticamente:

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
