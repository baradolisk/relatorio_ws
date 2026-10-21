#requires -Version 5.1
<#
.SYNOPSIS
    Versão revisada v2. -CsvCobertura registra falhas; com -CsvSaida, gera
    cobertura automaticamente. Não calcula permissões efetivas.
    Relatório de PERMISSÕES (compartilhamento + NTFS) das pastas compartilhadas.

.DESCRIPTION
    Complementa o Relatorio-AcessoPasta.ps1. Enquanto aquele mostra QUEM
    ACESSOU, este mostra QUEM PODE acessar e destaca permissões amplas demais
    (Everyone, Authenticated Users, Domain Users, BUILTIN\Users, NETWORK).
    Se um acesso indevido deu êxito, quase sempre a causa está aqui.

    Para cada compartilhamento não administrativo, lista:
      - permissões do compartilhamento (Get-SmbShareAccess);
      - permissões NTFS da raiz e das subpastas até -Profundidade níveis,
        indicando se é herdada, se a herança está desabilitada na pasta e se
        a permissão permite gravar/excluir/alterar permissões.

    A detecção de "amplo" é feita por SID (independe do idioma do Windows).
    Execute como Administrador. Somente leitura: nada é alterado.

.PARAMETER Computador
    Servidores de arquivos (ex.: "SRV1","SRV2"). Padrão: computador local.

.PARAMETER Compartilhamento
    Filtro (com curingas) pelo nome do compartilhamento. Padrão: *

.PARAMETER Profundidade
    Quantos níveis de subpastas ler abaixo da raiz (0 = só a raiz). Padrão: 1.
    Valores altos em servidores grandes podem demorar bastante.

.PARAMETER SomenteAmplas
    Mostra/exporta apenas as permissões amplas.

.PARAMETER CsvSaida
    Exporta o relatório completo em CSV (";" e UTF-8). Aceita o token {data}.

.EXAMPLE
    .\scripts\permissoes\Relatorio-PermissoesPasta-v2.ps1 -Profundidade 2 -CsvSaida "C:\Relatorios\permissoes-{data}.csv"

.EXAMPLE
    .\scripts\permissoes\Relatorio-PermissoesPasta-v2.ps1 -Computador "SRV-ARQ1","SRV-ARQ2" -SomenteAmplas
#>

[CmdletBinding()]
param (
    [string]$CsvCobertura,

    [string[]]$Computador = @($env:COMPUTERNAME),

    [string]$Compartilhamento = '*',

    [ValidateRange(0, 10)]
    [int]$Profundidade = 1,

    [switch]$SomenteAmplas,

    [string]$CsvSaida
)

function Test-ServidorLocal {
    param ([string]$Nome)
    $locais = @('.', 'localhost', '127.0.0.1', $env:COMPUTERNAME)
    if ($env:USERDNSDOMAIN) { $locais += ($env:COMPUTERNAME + '.' + $env:USERDNSDOMAIN) }
    return ($locais -contains $Nome)
}

function Protect-CsvCell {
    param ([object]$Valor)
    $texto = [string]$Valor
    if ($texto -match '^[=+\-@\t\r]') { return "'" + $texto }
    return $texto
}

# SID "amplo": Everyone, Authenticated Users, BUILTIN\Users, NETWORK, Domain Users
function Test-SidAmplo {
    param ([string]$Sid)
    return (
        ($Sid -in @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-2')) -or
        ($Sid -match '^S-1-5-21-\d+-\d+-\d+-513$')
    )
}

function Get-SidDaIdentidade {
    param ($Identidade)
    try {
        if ($Identidade -is [System.Security.Principal.SecurityIdentifier]) { return $Identidade.Value }
        if ($Identidade -isnot [System.Security.Principal.NTAccount]) {
            $Identidade = [System.Security.Principal.NTAccount][string]$Identidade
        }
        return $Identidade.Translate([System.Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        Add-FalhaCobertura $servidor 'ResolucaoSID' ([string]$Identidade) $_.Exception.Message
        Write-Warning "Identidade não resolvida: $Identidade"
        return ''
    }
}

# Direitos que permitem alterar conteúdo: gravar, anexar, excluir, alterar
# permissões ou assumir a propriedade.
function Test-DireitoEscrita {
    param ([int]$Direitos)
    return (($Direitos -band (0x2 -bor 0x4 -bor 0x10000 -bor 0x40000 -bor 0x80000)) -ne 0)
}

$carimboExecucao = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not [string]::IsNullOrWhiteSpace($CsvSaida)) {
    $CsvSaida = $CsvSaida -replace '\{data\}', $carimboExecucao
}

$cobertura = New-Object 'System.Collections.Generic.List[object]'
if ($CsvSaida -and -not $CsvCobertura) { $CsvCobertura = $CsvSaida + '.cobertura.csv' }
if ($CsvCobertura) { $CsvCobertura = $CsvCobertura -replace '\{data\}', $carimboExecucao }
function Add-FalhaCobertura {
    param ([string]$Servidor, [string]$Etapa, [string]$Alvo, [string]$Mensagem)
    $cobertura.Add([pscustomobject]@{
        Servidor = Protect-CsvCell $Servidor; Etapa = $Etapa
        Alvo = Protect-CsvCell $Alvo; Mensagem = Protect-CsvCell $Mensagem
    })
}
$linhas = New-Object 'System.Collections.Generic.List[object]'

foreach ($servidor in $Computador) {

    Write-Host "Lendo compartilhamentos de $servidor..." -ForegroundColor Cyan

    $local = Test-ServidorLocal $servidor
    $cim = $null

    try {

        if ($local) {
            $shares = @(Get-SmbShare -Special:$false -ErrorAction Stop)
        }
        else {
            $cim = New-CimSession -ComputerName $servidor -ErrorAction Stop
            $shares = @(Get-SmbShare -CimSession $cim -Special:$false -ErrorAction Stop)
        }

        $shares = @($shares | Where-Object { $_.Name -like $Compartilhamento })

        foreach ($sh in $shares) {

            Write-Host "  \\$servidor\$($sh.Name)" -ForegroundColor DarkGray

            # ---- Permissões do compartilhamento
            try {

                if ($local) { $acessosShare = @(Get-SmbShareAccess -Name $sh.Name -ErrorAction Stop) }
                else { $acessosShare = @(Get-SmbShareAccess -Name $sh.Name -CimSession $cim -ErrorAction Stop) }

                foreach ($a in $acessosShare) {

                    $sid = Get-SidDaIdentidade ([string]$a.AccountName)
                    $direito = [string]$a.AccessRight

                    $linhas.Add([PSCustomObject]@{
                        Servidor            = $servidor
                        Compartilhamento    = $sh.Name
                        Camada              = 'Compartilhamento'
                        Pasta               = "\\$servidor\$($sh.Name)"
                        Identidade          = [string]$a.AccountName
                        Sid                 = $sid
                        Tipo                = [string]$a.AccessControlType
                        Direitos            = $direito
                        Herdada             = ''
                        HerancaDesabilitada = ''
                        PodeAlterar         = if ($a.AccessControlType -eq 'Allow' -and $direito -in @('Full', 'Change')) { 'Sim' } else { 'Nao' }
                        Ampla               = if ($sid -and (Test-SidAmplo $sid) -and [string]$a.AccessControlType -eq 'Allow') { 'Sim' } else { 'Nao' }
                    })
                }
            }
            catch {
                Add-FalhaCobertura $servidor 'Compartilhamento' $sh.Name $_.Exception.Message
                Write-Warning "[$servidor] Permissões do compartilhamento '$($sh.Name)': $($_.Exception.Message)"
            }

            # ---- Permissões NTFS (raiz + subpastas até -Profundidade)
            if ($local) { $raiz = $sh.Path } else { $raiz = "\\$servidor\$($sh.Name)" }

            $errosEnumeracao = @()
            $pastas = @($raiz)

            if ($Profundidade -gt 0) {
                $pastas += @(
                    Get-ChildItem -LiteralPath $raiz -Directory -Recurse -Depth ($Profundidade - 1) -Force -ErrorAction SilentlyContinue -ErrorVariable errosEnumeracao |
                        ForEach-Object { $_.FullName }
                )
            }

            foreach ($falha in $errosEnumeracao) {
                Add-FalhaCobertura $servidor 'Enumeracao' ([string]$falha.TargetObject) $falha.Exception.Message
                Write-Warning "Enumeração incompleta em $raiz : $($falha.Exception.Message)"
            }
            foreach ($pasta in $pastas) {

                try {
                    $acl = Get-Acl -LiteralPath $pasta -ErrorAction Stop
                }
                catch {
                    Add-FalhaCobertura $servidor 'ACL' $pasta $_.Exception.Message
                    Write-Warning "Sem acesso ao ACL de ${pasta}: $($_.Exception.Message)"
                    continue
                }

                foreach ($ace in $acl.Access) {

                    $sid = Get-SidDaIdentidade $ace.IdentityReference
                    $tipo = [string]$ace.AccessControlType

                    $linhas.Add([PSCustomObject]@{
                        Servidor            = $servidor
                        Compartilhamento    = $sh.Name
                        Camada              = 'NTFS'
                        Pasta               = $pasta
                        Identidade          = [string]$ace.IdentityReference
                        Sid                 = $sid
                        Tipo                = $tipo
                        Direitos            = [string]$ace.FileSystemRights
                        Herdada             = if ($ace.IsInherited) { 'Sim' } else { 'Nao' }
                        HerancaDesabilitada = if ($acl.AreAccessRulesProtected) { 'Sim' } else { 'Nao' }
                        PodeAlterar         = if ($tipo -eq 'Allow' -and (Test-DireitoEscrita ([int]$ace.FileSystemRights))) { 'Sim' } else { 'Nao' }
                        Ampla               = if ($sid -and (Test-SidAmplo $sid) -and $tipo -eq 'Allow') { 'Sim' } else { 'Nao' }
                    })
                }
            }
        }
    }
    catch {
        Add-FalhaCobertura $servidor 'Servidor' $servidor $_.Exception.Message
        Write-Warning "[$servidor] Falha: $($_.Exception.Message)"
    }
    finally {
        if ($cim) { Remove-CimSession $cim -ErrorAction SilentlyContinue }
    }
}

if ($CsvCobertura) {
    $dir = Split-Path -Parent $CsvCobertura
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # Uma linha de conclusão mesmo quando não houve erros; não implica acesso efetivo calculado.
    $cobertura.Add([pscustomobject]@{Servidor='';Etapa='Conclusao';Alvo='';Mensagem="Falhas: $($cobertura.Count); profundidade: $Profundidade; inventário de ACEs, não permissão efetiva."})
    $cobertura | Export-Csv -LiteralPath $CsvCobertura -Delimiter ';' -NoTypeInformation -Encoding UTF8
}
if ($linhas.Count -eq 0) {
    Write-Warning 'Nenhuma permissão encontrada (verifique servidor, filtro e se está executando como Administrador).'
    return
}

$relatorio = $linhas.ToArray()

if ($SomenteAmplas) {
    $relatorio = @($relatorio | Where-Object { $_.Ampla -eq 'Sim' })
}

$amplas = @($linhas | Where-Object { $_.Ampla -eq 'Sim' })

Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ' PERMISSÕES AMPLAS (Everyone, Authenticated Users, Domain Users, BUILTIN\Users, NETWORK)' -ForegroundColor Yellow
Write-Host '============================================================' -ForegroundColor DarkGray

if ($amplas.Count -eq 0) {
    Write-Host 'Nenhuma permissão ampla encontrada.' -ForegroundColor Green
}
else {
    $amplas |
        Select-Object Servidor, Camada, Pasta, Identidade, Direitos, Herdada, PodeAlterar |
        Format-Table -AutoSize -Wrap |
        Out-Host

    $comEscrita = @($amplas | Where-Object { $_.PodeAlterar -eq 'Sim' })

    if ($comEscrita.Count -gt 0) {
        Write-Warning "$($comEscrita.Count) permissão(ões) ampla(s) permitem ALTERAR conteúdo (coluna PodeAlterar = Sim)."
    }
}

Write-Host ''
Write-Host "$($linhas.Count) permissão(ões) lidas; $($amplas.Count) ampla(s)." -ForegroundColor Green

if (-not [string]::IsNullOrWhiteSpace($CsvSaida)) {

    try {
        $dir = Split-Path -Path $CsvSaida -Parent
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }

        $relatorio |
            ForEach-Object {
                [PSCustomObject]@{
                    Servidor            = Protect-CsvCell $_.Servidor
                    Compartilhamento    = Protect-CsvCell $_.Compartilhamento
                    Camada              = $_.Camada
                    Pasta               = Protect-CsvCell $_.Pasta
                    Identidade          = Protect-CsvCell $_.Identidade
                    Sid                 = $_.Sid
                    Tipo                = $_.Tipo
                    Direitos            = Protect-CsvCell $_.Direitos
                    Herdada             = $_.Herdada
                    HerancaDesabilitada = $_.HerancaDesabilitada
                    PodeAlterar         = $_.PodeAlterar
                    Ampla               = $_.Ampla
                }
            } |
            Export-Csv -Path $CsvSaida -NoTypeInformation -Encoding UTF8 -Delimiter ';'

        Write-Host "Arquivo: $CsvSaida ($($relatorio.Count) linha(s))" -ForegroundColor Green
    }
    catch {
        Write-Error "Falha ao exportar CSV: $($_.Exception.Message)"
    }
}
