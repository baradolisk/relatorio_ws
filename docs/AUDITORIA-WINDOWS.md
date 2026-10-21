# Auditoria e retenção no Windows

Execute comandos de configuração apenas no servidor de arquivos correto,
como administrador, após aprovar o impacto de volume. Em domínio, configure
pela GPO aplicada aos servidores; mudanças locais podem ser sobrescritas.
Os exemplos abaixo alteram somente as opções explicitadas quando executados.

## Identificar os compartilhamentos

```powershell
Get-SmbShare | Select-Object Name, Path
```

Se `z` aponta para `E:\FileServer`, o caminho de rede é `\\SERVIDOR\z`,
não necessariamente `\\SERVIDOR\FileServer`.

## Conferir e habilitar o evento 5145

Verificar Detailed File Share (GUID independente do idioma):

```powershell
auditpol /get /subcategory:"{0CCE9244-69AE-11D9-BED3-505054503030}"
```

Habilitar êxito e falha:

```powershell
auditpol /set /subcategory:"{0CCE9244-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable
```

Na GPO: Configuração do Computador → Políticas → Configurações do Windows →
Configurações de Segurança → Configuração Avançada de Política de Auditoria →
Políticas de Auditoria → Acesso a Objetos → Auditar Compartilhamento de Arquivos
Detalhado. Habilite êxito e falha conforme sua política de auditoria.

Teste abrindo um arquivo por UNC, a partir de outra estação, e consulte:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 5145
    StartTime = (Get-Date).AddMinutes(-15)
} -MaxEvents 5 | Select-Object TimeCreated, Id, Message
```

Um acesso local em `E:\FileServer` não substitui um teste via SMB. Eventos
anteriores à habilitação não são criados retroativamente.

## Eventos 5140 e 4663

- 5140 depende de **Auditar Compartilhamento de Arquivos (File Share)** e
  registra acesso ao compartilhamento, não cada operação em cada arquivo.
- 4663 depende de **Auditar Sistema de Arquivos (File System)** e de uma SACL
  na pasta/arquivo para os sujeitos e direitos desejados. Configure pela aba
  Segurança → Avançado → Auditoria e valide herança/escopo em um piloto.
  Apenas habilitar a política não basta.
- Não trate êxito em 5145 como prova isolada de leitura: o evento representa
  verificação de acesso SMB. Para 4663, interprete o direito em AccessMask.

## Aumentar o log de Segurança para 2 GB

O comando altera o tamanho máximo; não limpa o log nem recupera registros:

```powershell
wevtutil sl Security /ms:2147483648

Get-WinEvent -ListLog Security |
    Select-Object LogName, @{Name='MaximoMB';Expression={$_.MaximumSizeInBytes / 1MB}}, RecordCount
```

Acompanhe o evento mais antigo:

```powershell
Get-WinEvent -LogName Security -Oldest -MaxEvents 1 |
    Select-Object TimeCreated, Id
```

Volume e espaço disponível determinam a retenção. Dois GB não garantem um
número específico de dias. Verifique a GPO se o tamanho voltar ao anterior.

## Arquivamento automático quando atingir o limite

O Windows oferece esse recurso sem script em execução contínua:

```powershell
wevtutil sl Security /ms:2147483648 /rt:true /ab:true
wevtutil gl Security
```

Confira `retention: true`, `autoBackup: true` e `maxSize: 2147483648`.
No caminho padrão, os arquivos são criados em:

```powershell
Get-ChildItem "$env:SystemRoot\System32\winevt\Logs" -Filter 'Archive-Security-*.evtx'
```

Se o log foi realocado, confira `logFileName` na saída de `wevtutil gl Security`.
Proteja os arquivos e monitore espaço/erros de arquivamento: sem espaço, a coleta
pode ser comprometida. Defina retenção, backup e destino restrito antes de usar
em produção; não coloque os logs em compartilhamento aberto aos funcionários.

**O relatório atual não lê automaticamente os arquivos arquivados.** É preciso
consultá-los separadamente no Visualizador de Eventos ou com Get-WinEvent -Path.
A integração dessa leitura com os relatórios ainda não foi implementada. Não
mova nem apague o arquivo ativo Security.evtx; planeje a movimentação apenas dos
arquivos de arquivo, sem interferir com o serviço de eventos.

Para desativar o arquivamento e voltar ao modo de sobrescrever eventos antigos
quando cheio (isso permite perder histórico antigo sem arquivo), o comando é:

```powershell
wevtutil sl Security /rt:false /ab:false
```

## Verificação antes de analisar os relatórios

Confirme servidor, relógio/fuso, período, tipo de evento, auditoria, SACL quando
necessária, acesso ao log e limites dos filtros. Confira avisos e cobertura.
Mantenha o CSV original sem agrupamento e um registro da configuração de coleta.
