#requires -Version 5.1
# Testes com fontes simuladas: não consulta serviços Windows, AD ou SMB reais.
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$script:verificacoes = 0

function Assert-Resultado {
    param ([bool]$Condicao, [string]$Descricao)
    if (-not $Condicao) { throw "FALHOU: $Descricao" }
    $script:verificacoes++
}

function Import-FuncoesTeste {
    param ([string]$Arquivo)
    $tokens = $null; $erros = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Arquivo, [ref]$tokens, [ref]$erros)
    if ($erros.Count) { throw "Sintaxe: $($erros[0].Message)" }
    $funcoes = $ast.FindAll({
        param($no)
        $no -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)
    # Emitir somente declarações de função para importar no escopo do teste.
    return ($funcoes | ForEach-Object { $_.Extent.Text }) -join "`n"
}

foreach ($arquivo in Get-ChildItem -Path $raiz -Filter *.ps1 -Recurse -File) {
    $tokens = $null; $erros = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($arquivo.FullName, [ref]$tokens, [ref]$erros)
    Assert-Resultado ($erros.Count -eq 0) "Sintaxe de $($arquivo.Name)"
}

# Cada conjunto usa escopo próprio para não misturar funções das versões.
& {
    Invoke-Expression (Import-FuncoesTeste (Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta.ps1'))
    Assert-Resultado ((ConvertTo-ShareServidor '\\*\z' 'SRV.empresa.local') -eq '\\SRV.empresa.local\z') 'ShareName com servidor curinga'
    Assert-Resultado (Test-FiltroRede '\\SRV\z\RH' '\\SRV.empresa.local\z' 'RH\a.txt' 'SRV.empresa.local' 'SRV') 'UNC curto e FQDN'
    Assert-Resultado (-not (Test-FiltroRede '\\OUTRO\z' '\\SRV\z' 'a.txt' 'SRV' 'SRV')) 'Servidor diferente'
    Assert-Resultado (-not (Test-FiltroRede '\\SRV\z\RH' '\\SRV\z' 'RH-antigo\a.txt' 'SRV' 'SRV')) 'Limite de diretório no comparador UNC'
    Assert-Resultado ((ConvertTo-AccessMask '0x1') -eq 1) 'Máscara hexadecimal'
    Assert-Resultado ((Protect-CsvCell '=1+1') -eq "'=1+1") 'Proteção de fórmula em CSV'
}

& {
    Invoke-Expression (Import-FuncoesTeste (Join-Path $raiz 'scripts/permissoes/Relatorio-PermissoesPasta-v2.ps1'))
    Assert-Resultado (Test-SidAmplo 'S-1-1-0') 'Everyone por SID'
    Assert-Resultado (-not (Test-SidAmplo 'S-1-5-21-1-2-3-1001')) 'Usuário específico não é grupo amplo'
    Assert-Resultado (Test-DireitoEscrita 2) 'Direito de escrita'
    Assert-Resultado (-not (Test-DireitoEscrita 1)) 'Leitura não é escrita'
}

# Exercitar o menu com entradas simuladas; nenhuma consulta ao Windows.
& {
    $relatorio = Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta.ps1'
    Invoke-Expression (Import-FuncoesTeste $relatorio)
    $global:TesteRelatoriosEntradasMenu = New-Object 'System.Collections.Generic.Queue[string]'
    $global:TesteRelatoriosMensagensMenu = New-Object 'System.Collections.Generic.List[string]'
    function Read-Host {
        param ([string]$Prompt)
        if (-not $global:TesteRelatoriosEntradasMenu.Count) { throw "Entrada simulada esgotada: $Prompt" }
        return $global:TesteRelatoriosEntradasMenu.Dequeue()
    }
    function Clear-Host { }
    function Write-Host {
        param ([Parameter(Position=0, ValueFromRemainingArguments=$true)][object[]]$Object, $ForegroundColor)
        $global:TesteRelatoriosMensagensMenu.Add([string]$Object)
    }
    function Get-WinEvent { throw 'O menu não deve consultar eventos ao sair.' }

    $global:TesteRelatoriosEntradasMenu.Enqueue('Q')
    & $relatorio -Menu -Pasta 'RH' -Computador 'SRV-TESTE'
    Assert-Resultado ($global:TesteRelatoriosEntradasMenu.Count -eq 0) 'Menu integrado encerra sem consultar logs'
    Assert-Resultado (@($global:TesteRelatoriosMensagensMenu | Where-Object { $_ -like '*RH*' }).Count -gt 0) 'Menu mantém filtro inicial'

    $temporario = Join-Path ([IO.Path]::GetTempPath()) ('menu-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $temporario
    $alvo = Join-Path $temporario "relatório d'empresa.ps1"
    $destino = Join-Path $temporario 'capturado.json'
    # O alvo simulado registra somente os argumentos recebidos.
    $fonte = @'
param($Computador, $EventoId, $Dias, $Inicio, $Fim, $Pasta, $Usuario,
      [switch]$UsuarioExato, $Resultado, $ExcluirUsuarios, $CsvSaida, $CsvResumo,
      $ListaAutorizados, [switch]$PassThru, [switch]$Silencioso)
$PSBoundParameters | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $env:RELATORIO_TESTE_CAPTURA -Encoding UTF8
if ($PassThru) { [pscustomobject]@{TestePassThru="OK"} }
'@
    $variavelAnterior = $env:RELATORIO_TESTE_CAPTURA
    try {
        Set-Content -LiteralPath $alvo -Value $fonte -Encoding UTF8
        $env:RELATORIO_TESTE_CAPTURA = $destino
        foreach ($r in @('E','S','','Q')) { $global:TesteRelatoriosEntradasMenu.Enqueue($r) }
        $ini = [datetime]::new(2026,10,15,8,30,45)
        $objetosMenu = @(Show-MenuRelatorioAcesso -ScriptRelatorio $alvo -ParametrosIniciais @{
            Computador=@('SRV1','SRV2'); Inicio=$ini; Pasta='RH'; Usuario='joao'
            UsuarioExato=$true; PassThru=$true; Silencioso=$true
        })
        Assert-Resultado ($objetosMenu.Count -eq 1 -and $objetosMenu[0].TestePassThru -eq 'OK') 'PassThru no menu preserva objetos para o pipeline'
        $captura = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
        Assert-Resultado ($captura.Computador.Count -eq 2) 'Menu preserva vários servidores'
        Assert-Resultado ($captura.Pasta -eq 'RH' -and $captura.Usuario -eq 'joao') 'Menu encaminha filtros'
        Assert-Resultado ($null -eq $captura.Dias -and $null -ne $captura.Inicio) 'Menu não mistura Dias e Inicio'
        Assert-Resultado ($captura.UsuarioExato.IsPresent -and $captura.PassThru.IsPresent) 'Menu encaminha switches'
        Assert-Resultado ($null -eq $captura.Menu) 'Execução do relatório não reabre o menu'
        $comando = @($global:TesteRelatoriosMensagensMenu | Where-Object { $_.StartsWith("& '") })[-1]
        Assert-Resultado ($comando.Contains("d''empresa.ps1")) 'Comando copiável escapa apóstrofos e usa caminho completo'
        Assert-Resultado ($comando.Contains('[datetime]::new(2026,10,15,8,30,45,0)')) 'Comando copiável preserva data sem depender de idioma'
        # Executar somente o comando gerado para o alvo de teste com dados conhecidos.
        $null = & ([scriptblock]::Create($comando))
        $copiado = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
        Assert-Resultado (([datetime]$copiado.Inicio) -eq $ini) 'Comando exibido é executável com a mesma data'

        Remove-Item -LiteralPath $destino
        foreach ($r in @('E','N','Q')) { $global:TesteRelatoriosEntradasMenu.Enqueue($r) }
        Show-MenuRelatorioAcesso -ScriptRelatorio $alvo -ParametrosIniciais @{Computador=@('SRV')}
        Assert-Resultado (-not (Test-Path -LiteralPath $destino)) 'Cancelar não executa o relatório'

        # Limpar pasta e substituir a janela de dias por um período sem fim.
        foreach ($r in @('4','-','3','2','15/10/2026 08:00','-','E','S','','Q')) {
            $global:TesteRelatoriosEntradasMenu.Enqueue($r)
        }
        Show-MenuRelatorioAcesso -ScriptRelatorio $alvo -ParametrosIniciais @{
            Computador=@('SRV'); Pasta='RH'; Dias=5
        }
        $captura = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
        Assert-Resultado ($null -eq $captura.Pasta) 'Hífen remove o filtro de pasta'
        Assert-Resultado ($null -ne $captura.Inicio -and $null -eq $captura.Fim -and $null -eq $captura.Dias) 'Período aberto não inclui fim ou dias'
        # Executar sem editar nenhuma opção deve fornecer padrões úteis.
        foreach ($r in @('E','','','Q')) { $global:TesteRelatoriosEntradasMenu.Enqueue($r) }
        Show-MenuRelatorioAcesso -ScriptRelatorio $alvo
        $padrao = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
        Assert-Resultado ($padrao.Dias -eq 1 -and $padrao.EventoId -eq 5145) 'Menu inicia com um dia e evento 5145'
        Assert-Resultado ($padrao.Computador.Count -ge 1 -and $padrao.Computador[0]) 'Menu preenche o computador local'
        Assert-Resultado (-not $padrao.Pasta -and -not $padrao.ListaAutorizados -and -not $padrao.ExcluirUsuarios) 'Padrões não exigem filtros ou arquivos próprios'
        Assert-Resultado ((Split-Path -Leaf $padrao.CsvSaida) -eq 'acessos-{data}.csv') 'CSV detalhado tem caminho padrão'
        Assert-Resultado ((Split-Path -Leaf $padrao.CsvResumo) -eq 'resumo-{data}.csv') 'CSV resumo tem caminho padrão'
        Assert-Resultado ($null -eq $padrao.Inicio -and $null -eq $padrao.Fim) 'Data sugerida não muda o modo de dias'

        # Trocar para período aceita Enter em início e fim, sem obrigar digitação.
        $antesPeriodo = (Get-Date).AddDays(-3).AddMinutes(-1)
        foreach ($r in @('3','2','','','E','S','','Q')) { $global:TesteRelatoriosEntradasMenu.Enqueue($r) }
        Show-MenuRelatorioAcesso -ScriptRelatorio $alvo -ParametrosIniciais @{Dias=3}
        $padrao = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
        Assert-Resultado (([datetime]$padrao.Inicio) -ge $antesPeriodo -and ([datetime]$padrao.Inicio) -le (Get-Date).AddDays(-3).AddMinutes(1)) 'Data inicial sugerida acompanha Dias'
        Assert-Resultado ($null -eq $padrao.Fim -and $null -eq $padrao.Dias) 'Fim padrão é até agora sem misturar Dias'

        # Permitir desativar arquivos e preservar opção de usuário exato com Enter.
        foreach ($r in @('9','-','10','-','5','','','E','S','','Q')) { $global:TesteRelatoriosEntradasMenu.Enqueue($r) }
        Show-MenuRelatorioAcesso -ScriptRelatorio $alvo -ParametrosIniciais @{Usuario='joao'; UsuarioExato=$true}
        $padrao = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
        Assert-Resultado (-not $padrao.CsvSaida -and -not $padrao.CsvResumo) 'Usuário pode desativar os CSVs padrão'
        Assert-Resultado ($padrao.Usuario -eq 'joao' -and $padrao.UsuarioExato.IsPresent) 'Enter preserva usuário e opção de nome exato'

        # A escolha aceita tanto ID quanto número da opção; inválidos não executam silenciosamente.
        foreach ($escolha in @(
            @{Entrada='4663'; Esperado=4663}, @{Entrada='5140'; Esperado=5140},
            @{Entrada='5145'; Esperado=5145}, @{Entrada='1'; Esperado=5145},
            @{Entrada='2'; Esperado=4663}, @{Entrada='3'; Esperado=5140},
            @{Entrada='4660'; Esperado=4660}, @{Entrada='4'; Esperado=4660}
        )) {
            foreach ($r in @('2',$escolha.Entrada,'E','S','','Q')) { $global:TesteRelatoriosEntradasMenu.Enqueue($r) }
            Show-MenuRelatorioAcesso -ScriptRelatorio $alvo
            $capturaEvento = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
            Assert-Resultado ($capturaEvento.EventoId -eq $escolha.Esperado) "Menu encaminha evento escolhido: $($escolha.Entrada)"
        }
        $global:TesteRelatoriosMensagensMenu.Clear()
        foreach ($r in @('2','9999','4663','2','','E','S','','Q')) { $global:TesteRelatoriosEntradasMenu.Enqueue($r) }
        Show-MenuRelatorioAcesso -ScriptRelatorio $alvo
        $capturaEvento = Get-Content -LiteralPath $destino -Raw | ConvertFrom-Json
        Assert-Resultado ($capturaEvento.EventoId -eq 4663) 'Após inválido, aceita correção e Enter preserva a seleção'
        Assert-Resultado (@($global:TesteRelatoriosMensagensMenu | Where-Object { $_ -like 'Evento inválido*' }).Count -eq 1) 'Evento inválido mostra aviso e repete a pergunta'

        # O uso antigo por parâmetros não deve abrir o menu.
        function Get-WinEvent {
            [CmdletBinding()]
            param ($ListLog, $LogName, $MaxEvents, [switch]$Oldest, $FilterXPath, $ComputerName)
            if ($ListLog) { return [pscustomobject]@{MaximumSizeInBytes=2147483648} }
            if ($Oldest) { return [pscustomobject]@{TimeCreated=(Get-Date).AddDays(-10)} }
            $evento = [pscustomobject]@{
                Id=5145; RecordId=1; MachineName='SRV'; TimeCreated=(Get-Date).AddMinutes(-1)
                Keywords=0x20000000000000
            }
            $evento | Add-Member ScriptMethod ToXml {
                '<Event><EventData><Data Name="SubjectUserName">joao</Data><Data Name="SubjectDomainName">EMPRESA</Data><Data Name="ShareName">\\*\z</Data><Data Name="ShareLocalPath">\??\E:\FileServer</Data><Data Name="RelativeTargetName">RH\a.txt</Data><Data Name="AccessMask">0x1</Data></EventData></Event>'
            }
            return $evento
        }
        $registros = @(& $relatorio -Computador 'SRV' -Pasta 'RH' -Dias 1 -Silencioso -PassThru)
        Assert-Resultado ($registros.Count -eq 1 -and $registros[0].Usuario -eq 'EMPRESA\joao') 'Execução normal continua sem perguntas'

    }
    finally {
        $env:RELATORIO_TESTE_CAPTURA = $variavelAnterior
        Remove-Item -LiteralPath $temporario -Recurse -Force
        Remove-Variable -Name TesteRelatoriosEntradasMenu,TesteRelatoriosMensagensMenu -Scope Global -ErrorAction SilentlyContinue
    }
}

# Diagnóstico de volume: simular o serviço de eventos, sem consultar Windows.
& {
    $relatorio = Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta.ps1'
    if (-not ('EventoTesteDesempenho' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
public class EventoTesteDesempenho : IDisposable {
    public static int Descartados;
    public int Id { get { return 5145; } }
    public int RecordId { get; set; }
    public string MachineName { get { return "SRV"; } }
    public DateTime TimeCreated { get { return DateTime.Now.AddMinutes(-1); } }
    public long Keywords { get { return 9007199254740992L; } }
    public string ToXml() { return "<Event><EventData><Data Name=\"SubjectUserName\">Admrh01</Data><Data Name=\"SubjectDomainName\">EMPRESA</Data><Data Name=\"ShareName\">\\\\*\\z</Data><Data Name=\"ShareLocalPath\">\\??\\E:\\FileServer</Data><Data Name=\"RelativeTargetName\">RH\\a.txt</Data><Data Name=\"AccessMask\">0x1</Data><Data Name=\"AccessReason\">(A;;0x1;;;S-1-5-21-1-2-3-1001)</Data></EventData></Event>"; }
    public void Dispose() { Descartados++; }
}
'@
    }
    function Get-WinEvent {
        [CmdletBinding()]
        param($ListLog,$LogName,$MaxEvents,[switch]$Oldest,$FilterXPath,$ComputerName)
        if($ListLog){return [pscustomobject]@{MaximumSizeInBytes=2147483648}}
        if($Oldest){return [pscustomobject]@{TimeCreated=(Get-Date).AddDays(-10)}}
        $global:TesteFiltroConsultaDesempenho = $FilterXPath
        $quantidade = 12
        if ($MaxEvents -gt 0) { $quantidade = [math]::Min(12, $MaxEvents) }
        for ($i=0;$i -lt $quantidade;$i++) {
            $obj = New-Object EventoTesteDesempenho
            $obj.RecordId = $i + 1
            $obj
        }
    }
    $temporario = Join-Path ([IO.Path]::GetTempPath()) ('consulta-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $temporario
    try {
        [EventoTesteDesempenho]::Descartados = 0
        $csv = Join-Path $temporario 'limitado.csv'
        $avisos = @()
        $linhas = @(& $relatorio -Computador SRV -Usuario Admrh01 -UsuarioExato -Dias 5 -MaxEventos 5 -CsvSaida $csv -Silencioso -PassThru -WarningVariable avisos 3>$null 6>$null)
        Assert-Resultado ($linhas.Count -eq 5) 'Limite é encaminhado ao serviço de eventos'
        Assert-Resultado ([EventoTesteDesempenho]::Descartados -eq 5) 'Cada registro de evento é liberado após conversão'
        Assert-Resultado (@($avisos | Where-Object { $_ -like '*Resultado pode ser parcial*' }).Count -eq 1) 'Limite atingido produz aviso de parcialidade'
        $diag = Import-Csv -LiteralPath ($csv + '.execucao.csv') -Delimiter ';'
        Assert-Resultado ($diag.EventosLidos -eq 5 -and $diag.Estado -like 'Limite atingido*') 'Diagnóstico registra limite, contagem e estado'
        Assert-Resultado ($global:TesteFiltroConsultaDesempenho.Contains("Data[@Name='SubjectUserName']='Admrh01'")) 'Usuário exato é filtrado na consulta ao log'
        Assert-Resultado ($global:TesteFiltroConsultaDesempenho.Contains('@SystemTime<=')) 'Consulta por Dias também fixa o fim da janela'
        Assert-Resultado ($linhas[0].ConcedidoPor -eq 'S-1-5-21-1-2-3-1001') 'Sem consulta ao domínio por padrão, SID é preservado'

        $linhas = @(& $relatorio -Computador SRV -Pasta 'inexistente' -MaxEventos 5 -CsvSaida (Join-Path $temporario 'vazio.csv') -Silencioso -PassThru 3>$null 6>$null)
        Assert-Resultado ($linhas.Count -eq 0 -and (Test-Path (Join-Path $temporario 'vazio.csv.execucao.csv'))) 'Limite antes do filtro não é apresentado como busca completa sem resultados'
        $avisos = @()
        $linhas = @(& $relatorio -Computador SRV -MaxEventos 0 -Silencioso -PassThru -WarningVariable avisos 3>$null 6>$null)
        Assert-Resultado ($linhas.Count -eq 12) 'Zero não corta a consulta'
        Assert-Resultado (@($avisos | Where-Object { $_ -like '*Limite de*' }).Count -eq 0) 'Consulta sem limite não recebe alerta de corte'
    }
    finally {
        Remove-Item -LiteralPath $temporario -Recurse -Force
        Remove-Variable -Name TesteFiltroConsultaDesempenho -Scope Global -ErrorAction SilentlyContinue
    }
}

# Ações e correlação de exclusão: não inferir novo/editado ou caminho sem evidência.
& {
    $relatorio = Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta.ps1'
    Invoke-Expression (Import-FuncoesTeste $relatorio)
    foreach ($caso in @(
        @{Id=4663;Mask='0x80';Acao='Consulta de metadados'},
        @{Id=4663;Mask='0x20000';Acao='Consulta de metadados'},
        @{Id=4663;Mask='0x2';Acao='Gravação ou criação'},
        @{Id=4663;Mask='0x4';Acao='Anexação ou criação de subpasta'},
        @{Id=4663;Mask='0x10000';Acao='Direito de exclusão'},
        @{Id=5140;Mask='';Acao='Conexão ao compartilhamento'}
    )) {
        $r = Get-AcaoEvento -Id $caso.Id -Mask $caso.Mask -Resultado 'Êxito'
        Assert-Resultado ($r.Acao -eq $caso.Acao) "Classificar $($caso.Id)/$($caso.Mask)"
    }
    Assert-Resultado ((Get-AcaoEvento 5145 '0x2' 'Êxito').Acao -eq 'Verificação SMB: Gravação ou criação') '5145 não afirma operação efetiva'
    Assert-Resultado ((Get-AcaoEvento 4663 '0x3' 'Êxito').Acao -like '*Gravação ou criação*Leitura ou listagem*') 'Preservar múltiplas ações'
    Assert-Resultado ((Get-AcaoEvento 4663 '0x2' 'Falha').Acao -like 'Falha:*') 'Falha não é operação confirmada'
    Assert-Resultado ((Get-AcaoEvento 4663 'invalido' 'Êxito').Acao -eq 'Não identificada') 'Não inventar ação sem máscara válida'
    Assert-Resultado ((Get-AcaoEvento 4660 '' 'Êxito' $true).Acao -eq 'Exclusão confirmada') '4660 confirma exclusão'

    function Reset-CorrelacaoTeste {
        $script:handlesExclusao=@{}; $script:ultimoRecordCorrelacao=0L
        $script:passosCorrelacao=0; $script:descartesCorrelacao=0; $script:exclusoesSemCaminho=0
    }
    function New-EventoCorrelacao {
        param([int]$Id,[int]$Record,[string]$Nome='E:\FileServer\RH\a.txt',
              [string]$Handle='0x10',[string]$ProcessId='0x20',[string]$Sid='S-1-5-21-1-2-3-1001',
              [int]$Segundos=$Record,[string]$Servidor='SRV',[string]$SessaoId='0x30',
              [string]$Mask='0x10000',[long]$Keywords=0x20000000000000)
        $dados = @{
            SubjectUserName='Admrh01';SubjectDomainName='EMPRESA';SubjectUserSid=$Sid
            SubjectLogonId=$SessaoId;ProcessId=$ProcessId;HandleId=$Handle;ObjectType='File'
            AccessMask=$Mask;ProcessName='C:\Windows\explorer.exe'
        }
        if($Id -in @(4656,4663)){$dados.ObjectName=$Nome}
        $xml='<Event><EventData>'
        foreach($k in $dados.Keys){$xml+='<Data Name="'+$k+'">'+[Security.SecurityElement]::Escape([string]$dados[$k])+'</Data>'}
        $xml+='</EventData></Event>'
        $e=[pscustomobject]@{Id=$Id;RecordId=$Record;MachineName=$Servidor;TimeCreated=([datetime]::new(2026,10,22)).AddSeconds($Segundos);Keywords=$Keywords;Xml=$xml}
        $e | Add-Member ScriptMethod ToXml {return $this.Xml}
        return $e
    }
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 2)
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 3)
    Assert-Resultado ($r.Caminho -eq 'E:\FileServer\RH\a.txt' -and $r.RecordIdAbertura -eq 1) 'Correlacionar ciclo completo ao caminho e RecordId'
    Assert-Resultado ($script:handlesExclusao.Count -eq 0) 'Excluir contexto após 4660'
    foreach($interrupcao in @(4658,4608,4609,1102)){
        Reset-CorrelacaoTeste
        $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
        $null=Update-CorrelacaoExclusao (New-EventoCorrelacao $interrupcao 2)
        $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 3)
        Assert-Resultado (-not $r.Caminho) "Não reutilizar contexto após evento $interrupcao"
    }
    foreach($diferenca in @(@{ProcessId='0x21'},@{Sid='S-1-5-21-9-8-7-1001'},@{Servidor='OUTRO'},@{Handle='0x11'},@{SessaoId='0x31'},@{Segundos=400})){
        Reset-CorrelacaoTeste
        $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
        $r=Update-CorrelacaoExclusao (New-EventoCorrelacao -Id 4660 -Record 2 @diferenca)
        Assert-Resultado (-not $r.Caminho) 'Não correlacionar outra identidade/processo/servidor/handle ou janela expirada'
    }
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4658 2)
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 3 -Nome 'E:\FileServer\RH\b.txt')
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 4)
    Assert-Resultado ($r.Caminho -eq 'E:\FileServer\RH\b.txt') 'Handle reutilizado aponta somente para a nova abertura'

    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 2 -Nome 'E:\FileServer\OUTRO.txt')
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 3)
    Assert-Resultado (-not $r.Caminho) 'Caminho conflitante invalida correlação'
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 2)
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 1)
    Assert-Resultado (-not $r.Caminho) 'Ordem invertida não confirma caminho'
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 2 -Handle '16' -ProcessId '32' -SessaoId '48')
    Assert-Resultado ($r.Caminho -eq 'E:\FileServer\RH\a.txt') 'Normalizar IDs hexadecimais e decimais'
    Reset-CorrelacaoTeste
    for($i=0;$i -lt 10000;$i++){$script:handlesExclusao[[string]$i]=@{Inicio=([datetime]::new(2026,10,22));Caminho='contexto antigo'}}
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
    Assert-Resultado ($script:handlesExclusao.Count -eq 1 -and $script:descartesCorrelacao -eq 1) 'Limitar memória sem associar contexto descartado'

    # Alternativa 4663 DELETE sem abertura 4656 (cenário observado no servidor).
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 1)
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 2)
    Assert-Resultado ($r.Caminho -eq 'E:\FileServer\RH\a.txt' -and $r.EventoCorrelacao -eq 4663) '4663 DELETE fornece caminho sem 4656'
    Assert-Resultado (-not $r.RecordIdAbertura -and $r.RecordIdAcesso -eq 1 -and $r.RecordIdCorrelacao -eq 1) 'Evidência alternativa não inventa registro de abertura'
    Assert-Resultado ((Get-AcaoEvento -Id 4660 -Resultado 'Êxito' -CaminhoCorrelacionado $true -EventoCorrelacao 4663).Evidencia -like '*4663 com DELETE*') 'Explicar fonte alternativa no CSV'
    foreach($semDelete in @('0x80','0x20000','0x40','0x2')){
        Reset-CorrelacaoTeste
        $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 1 -Mask $semDelete)
        $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 2)
        Assert-Resultado (-not $r.Caminho) 'Metadados, gravação e DELETE_CHILD não fornecem caminho de exclusão'
    }
    foreach($diferenca in @(@{ProcessId='0x21'},@{Sid='S-1-5-21-9-8-7-1001'},@{Servidor='OUTRO'},@{Handle='0x11'},@{SessaoId='0x31'},@{Segundos=32})){
        Reset-CorrelacaoTeste
        $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 1)
        $r=Update-CorrelacaoExclusao (New-EventoCorrelacao -Id 4660 -Record 2 @diferenca)
        Assert-Resultado (-not $r.Caminho) 'Alternativa respeita identidade, handle e janela de 30 segundos'
    }
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 1)
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 2 -Segundos 31)
    Assert-Resultado ([bool]$r.Caminho) 'Aceitar limite de 30 segundos'
    foreach($reset in @(4658,4608,4609,1102)){
        Reset-CorrelacaoTeste
        $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 1)
        $null=Update-CorrelacaoExclusao (New-EventoCorrelacao $reset 2)
        $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 3)
        Assert-Resultado (-not $r.Caminho) 'Fechamento e reinícios também invalidam a alternativa'
    }
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 1 -Keywords 0x10000000000000)
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 2)
    Assert-Resultado (-not $r.Caminho) 'DELETE com falha não fornece evidência alternativa'
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 1)
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 2 -Nome 'E:\OUTRO.txt')
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 3)
    Assert-Resultado (-not $r.Caminho) 'Caminho conflitante não é substituído silenciosamente'
    Reset-CorrelacaoTeste
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4656 1)
    $null=Update-CorrelacaoExclusao (New-EventoCorrelacao 4663 2)
    $r=Update-CorrelacaoExclusao (New-EventoCorrelacao 4660 3)
    Assert-Resultado ($r.EventoCorrelacao -eq 4656 -and $r.RecordIdAbertura -eq 1 -and $r.RecordIdAcesso -eq 2) 'Preservar prioridade de 4656 sem perder evidência DELETE'

    function Get-WinEvent {
        [CmdletBinding()]
        param($ListLog,$LogName,$MaxEvents,[switch]$Oldest,$FilterXPath,$ComputerName)
        if($ListLog){return [pscustomobject]@{MaximumSizeInBytes=2147483648}}
        if($Oldest -and -not $FilterXPath){return [pscustomobject]@{TimeCreated=(Get-Date).AddDays(-10)}}
        Assert-Resultado ([bool]$Oldest) 'Consulta de exclusões exige ordem crescente'
        Assert-Resultado ($FilterXPath.Contains('EventID=4656') -and $FilterXPath.Contains('EventID=4658')) 'Consulta inclui abertura e fechamento de handle'
        $global:TesteXPathExclusaoAtual = $FilterXPath
        # Assert-Resultado não emite objetos ao pipeline.
        New-EventoCorrelacao 4656 1
        New-EventoCorrelacao 4663 2
        New-EventoCorrelacao 4660 3
        New-EventoCorrelacao 4658 4
        New-EventoCorrelacao 4660 5
        New-EventoCorrelacao 4663 26485571 -Nome 'E:\FileServer\TI\TESTES\Nova pasta' -Handle '0x6744' -ProcessId '0x4' -SessaoId '0xC2A58611' -Segundos 52838
        New-EventoCorrelacao 4660 26485572 -Handle '0x6744' -ProcessId '0x4' -SessaoId '0xc2a58611' -Segundos 52838
        New-EventoCorrelacao 4663 26485602 -Nome 'E:\FileServer\TI\TESTES\Nova pasta' -Handle '0x4038' -ProcessId '0x4' -SessaoId '0xC2A58611' -Segundos 52846
        New-EventoCorrelacao 4660 26485603 -Handle '0x4038' -ProcessId '0x4' -SessaoId '0xc2a58611' -Segundos 52846
    }
    $temporario=Join-Path ([IO.Path]::GetTempPath()) ('acoes-'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $temporario
    try{
        $csv=Join-Path $temporario 'exclusoes.csv'
        $r=@(& $relatorio -EventoId 4660 -Computador SRV -Usuario Admrh01 -UsuarioExato -CsvSaida $csv -Silencioso -PassThru 3>$null 6>$null)
        Assert-Resultado ($r.Count -eq 4 -and $r[0].EventoId -eq 4660) 'Retornar apenas exclusões, não eventos de suporte'
        Assert-Resultado (@($r | Where-Object Acao -eq 'Exclusão confirmada').Count -eq 3) 'Somente exclusão com caminho correlacionado recebe a classificação completa'
        Assert-Resultado (@($r | Where-Object Acao -like '*caminho não identificado').Count -eq 1) 'Preservar exclusão sem caminho quando não há filtro de pasta'
        $exportado=@(Import-Csv -LiteralPath $csv -Delimiter ';')
        Assert-Resultado ($exportado.Count -eq 4 -and 'Evidencia' -in $exportado[0].PSObject.Properties.Name -and 'RecordIdAbertura' -in $exportado[0].PSObject.Properties.Name) 'CSV inclui ação, evidência e registro de abertura'
        $alternativas=@($exportado | Where-Object EventoCorrelacao -eq '4663')
        Assert-Resultado ($alternativas.Count -eq 2 -and $alternativas[0].Objeto -eq 'E:\FileServer\TI\TESTES\Nova pasta') 'Exportar caminho dos dois pares do diagnóstico'
        Assert-Resultado (@($alternativas | Where-Object RecordIdAbertura).Count -eq 0 -and @($alternativas | Where-Object RecordIdAcesso -eq '26485602').Count -eq 1) 'CSV diferencia registro de acesso e abertura'
        $diag=Import-Csv -LiteralPath ($csv+'.execucao.csv') -Delimiter ';'
        Assert-Resultado ($diag.ExclusoesSemCaminho -eq 1) 'Diagnóstico contabiliza exclusões sem caminho'
        Assert-Resultado ($diag.EventosAlvoLidos -eq 4 -and $diag.EventosApoioLidos -eq 5) 'Separar exclusões e eventos de apoio no diagnóstico'
        Assert-Resultado ($diag.EventosAlvoDescartados -eq 0 -and $diag.FalhasConversao -eq 0) 'Diagnóstico distingue descarte de conversão'
        Assert-Resultado ([bool]$diag.UltimoHorarioProcessado) 'Informar até qual horário a leitura avançou'
        Assert-Resultado ($diag.FiltroUsuarioNoLog -eq 'True') 'UsuarioExato otimiza também a consulta 4660'
        # Datas são comparadas pelo serviço Windows, não pelo XPath 1.0 do XmlDocument.
        $seletorSemTempo = $global:TesteXPathExclusaoAtual -replace ' and TimeCreated\[[^\]]+\]', ''
        $horarioTeste = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        foreach($tipoTeste in @(4656,4658,4663,4660)){
            [xml]$xmlTeste = "<Event><System><EventID>$tipoTeste</EventID><TimeCreated SystemTime='$horarioTeste'/></System><EventData><Data Name='SubjectUserName'>Admrh01</Data></EventData></Event>"
            Assert-Resultado ($null -ne $xmlTeste.SelectSingleNode($seletorSemTempo)) 'Filtro mantém eventos do usuário necessários à correlação'
        }
        [xml]$xmlOutro = "<Event><System><EventID>4663</EventID><TimeCreated SystemTime='$horarioTeste'/></System><EventData><Data Name='SubjectUserName'>outro</Data></EventData></Event>"
        Assert-Resultado ($null -eq $xmlOutro.SelectSingleNode($seletorSemTempo)) 'Filtro exclui apoio de outro usuário'
        foreach($tipoTeste in @(4608,4609,1102)){
            [xml]$xmlReset = "<Event><System><EventID>$tipoTeste</EventID><TimeCreated SystemTime='$horarioTeste'/></System></Event>"
            Assert-Resultado ($null -ne $xmlReset.SelectSingleNode($seletorSemTempo)) 'Filtro mantém reinício e limpeza sem SubjectUserName'
        }

        $r=@(& $relatorio -EventoId 4660 -Computador SRV -Pasta 'RH' -Silencioso -PassThru 3>$null 6>$null)
        Assert-Resultado ($r.Count -eq 1 -and $r[0].Objeto -eq 'E:\FileServer\RH\a.txt') 'Filtro de pasta não atribui caminho a exclusão desconhecida'
    } finally {Remove-Item -LiteralPath $temporario -Recurse -Force; Remove-Variable -Name TesteXPathExclusaoAtual -Scope Global -ErrorAction SilentlyContinue}
}

# Leitura antecipada para correlação, sem expandir o período do relatório.
& {
$relatorio=Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta.ps1'
$inicioFolgaTeste=[datetime]::new(2026,10,22,14,40,0)
$fimFolgaTeste=$inicioFolgaTeste.AddMinutes(1)
function Novo-Evento {
 param($Id,$Record,$Offset,$Handle)
 $e=[pscustomobject]@{Id=$Id;RecordId=$Record;TimeCreated=$inicioFolgaTeste.AddSeconds($Offset);MachineName='SRV';Keywords=0x20000000000000;HandleTeste=$Handle}
 $e|Add-Member ScriptMethod ToXml {
  $caminho='';if($this.Id -in @(4656,4663)){$caminho='<Data Name="ObjectName">E:\Dados\a.txt</Data>'}
  return '<Event><EventData><Data Name="SubjectUserName">teste</Data><Data Name="SubjectUserSid">S-1-5-21-1-2-3-1001</Data><Data Name="SubjectDomainName">EMPRESA</Data><Data Name="SubjectLogonId">0x30</Data><Data Name="ProcessId">0x20</Data><Data Name="HandleId">'+$this.HandleTeste+'</Data><Data Name="ObjectType">File</Data><Data Name="AccessMask">0x10000</Data>'+$caminho+'</EventData></Event>'
 };$e
}
$global:FolgaTesteEventos=@(
 (Novo-Evento 4656 1 -20 '0x10'),(Novo-Evento 4663 2 -5 '0x11'),
 (Novo-Evento 4660 3 -2 '0x11'),(Novo-Evento 4660 4 -1 '0x99'),
 (Novo-Evento 4660 5 1 '0x10'),(Novo-Evento 4660 6 2 '0x11'),(Novo-Evento 4660 7 3 '0x12')
)
function Get-WinEvent {
 [CmdletBinding()]param($ListLog,$LogName,$MaxEvents,[switch]$Oldest,$FilterXPath,$ComputerName)
 if($ListLog){return [pscustomobject]@{MaximumSizeInBytes=2147483648}}
 if($Oldest -and -not $FilterXPath){return [pscustomobject]@{TimeCreated=([datetime]::new(2026,10,21))}}
 if($FilterXPath -notmatch "@SystemTime>='([^']+)'"){throw 'Sem início'}
 $de=[datetime]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
 if($FilterXPath -notmatch "@SystemTime<='([^']+)'"){throw 'Sem fim'}
 $ate=[datetime]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
 $eventos=@($global:FolgaTesteEventos | Where-Object {$_.TimeCreated.ToUniversalTime() -ge $de -and $_.TimeCreated.ToUniversalTime() -le $ate})
 if($MaxEvents -gt 0){$eventos | Select-Object -First $MaxEvents}else{$eventos}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('folga-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try{
 $csv=Join-Path $temp 'saida.csv'
 $r=@(& $relatorio -Computador SRV -EventoId 4660 -Inicio $inicioFolgaTeste -Fim $fimFolgaTeste -CsvSaida $csv -Silencioso -PassThru 3>$null 6>$null)
 Assert-Resultado ($r.Count -eq 3) 'Folga não amplia o período das exclusões relatadas'
 Assert-Resultado (@($r | Where-Object {$_.RecordId -lt 5}).Count -eq 0) 'Não exportar exclusões anteriores ao início'
 Assert-Resultado (($r | Where-Object RecordId -eq 5).Objeto -eq 'E:\Dados\a.txt') 'Correlacionar abertura anterior ao início solicitado'
 Assert-Resultado (-not ($r | Where-Object RecordId -eq 6).Objeto) 'DELETE anterior consumido não é reutilizado'
 $d=Import-Csv -LiteralPath ($csv+'.execucao.csv') -Delimiter ';'
 Assert-Resultado ($d.EventosAlvoLidos -eq 3 -and $d.EventosApoioLidos -eq 4 -and $d.EventosAlvoDescartados -eq 0 -and $d.ExclusoesSemCaminho -eq 2) 'Contagens não incluem exclusões anteriores como alvos'
 Assert-Resultado (([datetime]$d.InicioConsulta) -eq $inicioFolgaTeste.AddMinutes(-5)) 'Diagnóstico informa início real da leitura'
 Assert-Resultado ($d.ExclusoesAnterioresComoApoio -eq 2) 'Diagnóstico contabiliza exclusões anteriores usadas como apoio'

}finally{Remove-Item -LiteralPath $temp -Recurse -Force;Remove-Variable FolgaTesteEventos -Scope Global}

}

Write-Output "PASSOU: $script:verificacoes verificações de sintaxe e funções isoladas com dados simulados."
Write-Output 'Não valida integração Windows/AD/SMB, cobertura real de auditoria ou Windows PowerShell 5.1.'
