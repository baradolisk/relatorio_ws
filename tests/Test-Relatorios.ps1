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
    Invoke-Expression (Import-FuncoesTeste (Join-Path $raiz 'scripts/acessos/Relatorio-AcessoPasta-v8.ps1'))
    $sidPermitido = 'S-1-5-21-1-2-3-1001'
    $membros = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [void]$membros.Add($sidPermitido)
    $membrosPorGrupo = @{G1=$membros}
    $regrasAutorizacao = @(
        [pscustomobject]@{Pasta='\\SRV\z\RH'; Grupo='G1'},
        [pscustomobject]@{Pasta='\\SRV\z\RH'; Grupo='G2'}
    )
    $registro = [pscustomobject]@{
        Usuario='EMPRESA\joao'; UsuarioSid=$sidPermitido
        Objeto='\\SRV\z\RH\a.txt'; CaminhoLocal=''
    }
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Autorizado') 'SID confirmado em um grupo'
    $registro.UsuarioSid = 'S-1-5-21-4-5-6-1001'
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Indeterminado') 'Outro SID e grupo indisponível'
    $membrosPorGrupo.G2 = $membros
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'NAO AUTORIZADO') 'Mesmo nome não autoriza outro SID'
    $registro.UsuarioSid = ''
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Indeterminado') 'SID ausente'
    $registro.Objeto = '\\SRV\z\RH-antigo\a.txt'
    Assert-Resultado ((Get-StatusAutorizacao $registro) -eq 'Sem regra') 'Regra não alcança nome parecido'
    Assert-Resultado ((ConvertTo-CaminhoRegra 'E:/FileServer/RH/') -eq 'E:\FileServer\RH') 'Normalizar caminho completo'
    $rejeitado = $false
    try { $null = ConvertTo-CaminhoRegra 'RH' } catch { $rejeitado = $true }
    Assert-Resultado $rejeitado 'Rejeitar regra por trecho'
    Assert-Resultado ((Get-PastaResumo -Compartilhamento '\\SRV\z' -CaminhoRelativo 'LEIAME') -eq '\\SRV\z') 'Não deduzir tipo pela extensão'
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
            @{Entrada='2'; Esperado=4663}, @{Entrada='3'; Esperado=5140}
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

Write-Output "PASSOU: $script:verificacoes verificações de sintaxe e funções isoladas com dados simulados."
Write-Output 'Não valida integração Windows/AD/SMB, cobertura real de auditoria ou Windows PowerShell 5.1.'
