<#
.SYNOPSIS
    Consulta acessos a pastas e exporta relatórios CSV.

.DESCRIPTION
    Execute no Windows com acesso aos dados consultados. Exemplos partem da raiz do repositório.
    5145: verificação SMB; não comprova leitura do conteúdo.
    5140: conexão ao compartilhamento. 4663: direito auditado no objeto; exige SACL.
    Sem registros não significa ausência de acessos. Consulta apenas o log ativo.

.PARAMETER Menu
    Abre o menu interativo. Omita em tarefas agendadas.

.PARAMETER Pasta
    Nome, trecho ou caminho da pasta. Omita para pesquisar todas.

.PARAMETER Dias
    Dias anteriores a consultar. Padrão: 1. Não combine com Inicio/Fim.

.PARAMETER Inicio
    Data e hora inicial de um período específico.

.PARAMETER Fim
    Data e hora final. Com Inicio, o padrão é até agora.

.PARAMETER EventoId
    Um evento por execução: 5145 (padrão), 5140 ou 4663.

.PARAMETER Usuario
    Nome ou padrão do usuário. Exemplo: "joao*". Padrão: todos.

.PARAMETER UsuarioExato
    Otimiza a busca pelo nome exato; diferencia maiúsculas/minúsculas. Não recebe texto.

.PARAMETER Computador
    Servidores a consultar. Padrão: computador local.

.PARAMETER IgnorarAtributos
    Descarta eventos que contêm apenas direitos considerados ruído.

.PARAMETER Agrupar
    Reúne eventos semelhantes no mesmo minuto. Use sem esta opção para preservar cada evento.

.PARAMETER Resultado
    Todos (padrão), Exito ou Falha.

.PARAMETER IncluirContasComputador
    Inclui contas com nome terminado em $, ignoradas por padrão.

.PARAMETER CsvSaida
    Arquivo CSV detalhado. Aceita {data} no nome.

.PARAMETER ExcluirUsuarios
    Contas a ignorar. Exemplo: "svc-*","backup".

.PARAMETER IncluirCompartilhamentosEspeciais
    Inclui compartilhamentos como C$, E$ e ADMIN$.

.PARAMETER ListarCompartilhamentos
    Lista os compartilhamentos dos servidores informados.

.PARAMETER ListaAutorizados
    CSV Pasta;Grupo. Requer ActiveDirectory/RSAT. Para classificação, prefira a v8.

.PARAMETER EnriquecerAD
    Acrescenta departamento e cargo. Requer ActiveDirectory/RSAT.

.PARAMETER ResolverIP
    Busca o nome DNS da estação pelo IP. Pode tornar a consulta lenta.

.PARAMETER CsvResumo
    Arquivo CSV de resumo por usuário e pasta. Aceita {data}.

.PARAMETER Silencioso
    Oculta tabelas; avisos e mensagens de execução continuam.

.PARAMETER GridView
    Abre os resultados em janela. Requer Out-GridView e interface gráfica.

.PARAMETER PassThru
    Retorna os registros como objetos PowerShell.

.EXAMPLE
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 -Menu

.EXAMPLE
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 -Pasta "RH" -Dias 1

.EXAMPLE
    .\scripts\acessos\Relatorio-AcessoPasta.ps1 -CsvSaida "C:\Relatorios\acessos-{data}.csv"

.NOTES
    Veja README.md, docs/PARAMETROS.md e docs/EXEMPLOS.md para mais opções.
    PowerShell 5.1 e Windows Server real ainda precisam de validação no seu ambiente.
    Para classificação por grupos, prefira a v8; esta versão usa nome e trecho.
    Caminho de rede usa o nome do compartilhamento: Get-SmbShare mostra Name e Path.
#>

[CmdletBinding(DefaultParameterSetName = 'Dias')]
param (

    [string]$Pasta = '',

    [Parameter(ParameterSetName = 'Dias')]
    [ValidateRange(1, 3650)]
    [int]$Dias = 1,

    [Parameter(Mandatory = $true, ParameterSetName = 'Periodo')]
    [datetime]$Inicio,

    [Parameter(ParameterSetName = 'Periodo')]
    [datetime]$Fim,

    [ValidateSet(4663, 5145, 5140)]
    [int]$EventoId = 5145,

    [ValidateNotNullOrEmpty()]
    [string]$Usuario = '*',

    [switch]$UsuarioExato,

    [ValidateNotNullOrEmpty()]
    [string[]]$Computador = @($env:COMPUTERNAME),

    [switch]$IgnorarAtributos,

    [switch]$Agrupar,

    [ValidateSet('Todos', 'Exito', 'Falha')]
    [string]$Resultado = 'Todos',

    [switch]$IncluirContasComputador,

    [string]$CsvSaida,

    [string[]]$ExcluirUsuarios = @(),

    [switch]$IncluirCompartilhamentosEspeciais,

    [switch]$ListarCompartilhamentos,

    [string]$ListaAutorizados,

    [switch]$EnriquecerAD,

    [switch]$ResolverIP,

    [string]$CsvResumo,

    [switch]$Silencioso,

    [switch]$GridView,

    [switch]$PassThru,

    [switch]$Menu
)

# ATENÇÃO: nomes de variáveis no PowerShell não diferenciam maiúsculas de
# minúsculas. O parâmetro $Resultado (string com ValidateSet) NÃO pode ser
# reutilizado para a lista de registros; por isso a lista se chama $registros.


# ============================================================
# Funções auxiliares
# ============================================================

function ConvertTo-AccessMask {

    param (
        [string]$Mask
    )

    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return $null
    }

    $valor = $Mask.Trim()

    # Remove prefixo 0x caso exista
    if ($valor -match '^0x') {
        $valor = $valor.Substring(2)
    }

    try {
        return [Convert]::ToInt64($valor, 16)
    }
    catch {
        return $null
    }
}


function Get-TipoAcesso {

    param (
        [string]$Mask
    )

    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return ''
    }

    $m = ConvertTo-AccessMask $Mask

    if ($null -eq $m) {
        return $Mask
    }

    $tipos = @()

    # Direitos específicos de arquivos e diretórios
    if ($m -band 0x1)      { $tipos += 'Leitura/Listagem' }
    if ($m -band 0x2)      { $tipos += 'Gravação/Criação' }
    if ($m -band 0x4)      { $tipos += 'Anexar dados/Criar subpasta' }
    if ($m -band 0x8)      { $tipos += 'Ler atributos estendidos' }
    if ($m -band 0x10)     { $tipos += 'Gravar atributos estendidos' }
    if ($m -band 0x20)     { $tipos += 'Executar/Atravessar pasta' }
    if ($m -band 0x40)     { $tipos += 'Excluir arquivo/subpasta filho' }
    if ($m -band 0x80)     { $tipos += 'Ler atributos' }
    if ($m -band 0x100)    { $tipos += 'Gravar atributos' }

    # Direitos padrão do Windows
    if ($m -band 0x10000)  { $tipos += 'Excluir' }
    if ($m -band 0x20000)  { $tipos += 'Ler permissões' }
    if ($m -band 0x40000)  { $tipos += 'Alterar permissões' }
    if ($m -band 0x80000)  { $tipos += 'Alterar proprietário' }
    if ($m -band 0x100000) { $tipos += 'Sincronizar' }

    if ($tipos.Count -eq 0) {
        return "Outro ($Mask)"
    }

    return ($tipos -join ', ')
}


# Retorna $true somente quando TODOS os bits da máscara são "ruído" conhecido
# (ler atributos estendidos, atravessar pasta, ler atributos, ler permissões,
# sincronizar). Qualquer bit desconhecido faz o evento ser MANTIDO: em auditoria
# é melhor mostrar demais do que esconder algo em silêncio.
function Test-AcessoRuido {

    param (
        [string]$Mask
    )

    $m = ConvertTo-AccessMask $Mask

    if ($null -eq $m) {
        return $false
    }

    $ruido = 0x8 -bor 0x20 -bor 0x80 -bor 0x20000 -bor 0x100000

    return (($m -band (-bnot $ruido)) -eq 0)
}


function ConvertTo-XPathTime {

    param (
        [datetime]$Data
    )

    return $Data.ToUniversalTime().ToString(
        "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}


# Evita que textos iniciados por = + - @ (ou tab/CR) sejam executados como
# fórmula ao abrir o CSV no Excel.
function Protect-CsvCell {

    param (
        [object]$Valor
    )

    $texto = [string]$Valor

    if ($texto -match '^[=+\-@\t\r]') {
        return "'" + $texto
    }

    return $texto
}


# Retorna $true quando o nome informado é o próprio computador (leitura local,
# sem RPC).
function Test-ServidorLocal {

    param (
        [string]$Nome
    )

    $locais = @('.', 'localhost', '127.0.0.1', $env:COMPUTERNAME)

    if ($env:USERDNSDOMAIN) {
        $locais += ($env:COMPUTERNAME + '.' + $env:USERDNSDOMAIN)
    }

    return ($locais -contains $Nome)
}


# Normaliza IPv4 mapeado em IPv6 (::ffff:10.0.0.5 -> 10.0.0.5).
function ConvertTo-IpNormalizado {

    param (
        [string]$Ip
    )

    if ([string]::IsNullOrWhiteSpace($Ip)) {
        return ''
    }

    $valor = $Ip.Trim()

    if ($valor -match '^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') {
        return $Matches[1]
    }

    return $valor
}


# Traduz um SID (ou apelido SDDL, como WD/AU/BU) para nome, com cache.
function Resolve-SidConta {

    param (
        [string]$Sid
    )

    if ($script:cacheSid.ContainsKey($Sid)) {
        return $script:cacheSid[$Sid]
    }

    $nome = $Sid

    if ($Sid -like 'S-1-*') {

        try {
            $nome = ([System.Security.Principal.SecurityIdentifier]::new($Sid)).Translate(
                [System.Security.Principal.NTAccount]).Value
        }
        catch {
            $nome = $Sid
        }
    }
    elseif ($script:aliasesSddl.ContainsKey($Sid)) {

        $nome = $script:aliasesSddl[$Sid]
    }

    $script:cacheSid[$Sid] = $nome

    return $nome
}


# Lê o AccessReason do evento 5145 (ACEs em SDDL) e devolve quem liberou o
# acesso. "Ampla" = liberação por Everyone, Authenticated Users, Domain Users,
# BUILTIN\Users ou NETWORK (detecção por SID, independente do idioma).
function Get-ConcessaoAcesso {

    param (
        [string]$AccessReason
    )

    $saida = @{ Contas = ''; Ampla = $false }

    if ([string]::IsNullOrWhiteSpace($AccessReason)) {
        return $saida
    }

    $contas = New-Object 'System.Collections.Generic.List[string]'

    $regexAce = [regex]'\((?<tipo>[A-Za-z]+);(?<flags>[A-Za-z]*);(?<dir>[0-9A-Za-z]*);[^;)]*;[^;)]*;(?<sid>[^;)]+)\)'

    foreach ($m in $regexAce.Matches($AccessReason)) {

        # Só interessam ACEs de permissão (A); negações (D) não "liberam"
        if ($m.Groups['tipo'].Value -ne 'A') {
            continue
        }

        $sid = $m.Groups['sid'].Value
        $conta = Resolve-SidConta $sid

        if (-not $contas.Contains($conta)) {
            $contas.Add($conta)
        }

        if (
            ($sid -in @('WD', 'AU', 'BU', 'DU', 'NU')) -or
            ($sid -in @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-2')) -or
            ($sid -match '^S-1-5-21-\d+-\d+-\d+-513$')
        ) {
            $saida.Ampla = $true
        }
    }

    $saida.Contas = ($contas -join '; ')

    return $saida
}


# Pasta usada nos resumos: compartilhamento + subpasta de 1º nível (5145/5140)
# ou os 3 primeiros níveis do caminho local (4663).
function Get-PastaResumo {

    param (
        [string]$Compartilhamento,
        [string]$CaminhoRelativo,
        [string]$CaminhoLocal
    )

    if (-not [string]::IsNullOrWhiteSpace($Compartilhamento)) {

        $base = $Compartilhamento.TrimEnd('\')

        $seg = @(([string]$CaminhoRelativo -split '\\') | Where-Object { $_ -ne '' })

        # Com 1 só nível, um nome com ponto é tratado como arquivo na raiz
        if ($seg.Count -ge 2 -or ($seg.Count -eq 1 -and $seg[0] -notmatch '\.')) {
            return $base + '\' + $seg[0]
        }

        return $base
    }

    if (-not [string]::IsNullOrWhiteSpace($CaminhoLocal)) {

        $seg = @($CaminhoLocal -split '\\' | Where-Object { $_ -ne '' })

        return (($seg | Select-Object -First 3) -join '\')
    }

    return ''
}


# Compara o acesso com a lista de autorizados (regra mais específica vence).
function Get-StatusAutorizacao {

    param (
        $Registro
    )

    $sam = ([string]$Registro.Usuario) -replace '^.*\\', ''

    $melhor = 0
    $grupos = @()

    foreach ($regra in $regrasAutorizacao) {

        $combina =
            (-not [string]::IsNullOrWhiteSpace($Registro.Objeto) -and $Registro.Objeto -like $regra.Padrao) -or
            (-not [string]::IsNullOrWhiteSpace($Registro.CaminhoLocal) -and $Registro.CaminhoLocal -like $regra.Padrao)

        if (-not $combina) {
            continue
        }

        $tamanho = $regra.Pasta.Length

        if ($tamanho -gt $melhor) {
            $melhor = $tamanho
            $grupos = @($regra.Grupo)
        }
        elseif ($tamanho -eq $melhor) {
            $grupos += $regra.Grupo
        }
    }

    if ($melhor -eq 0) {
        return 'Sem regra'
    }

    $lidos = 0

    foreach ($grupo in $grupos) {

        if ($membrosPorGrupo.ContainsKey($grupo)) {

            $lidos++

            if ($membrosPorGrupo[$grupo].Contains($sam)) {
                return 'Autorizado'
            }
        }
    }

    if ($lidos -eq 0) {
        return 'Indeterminado'
    }

    return 'NAO AUTORIZADO'
}


# Informa tamanho do log de Segurança, evento mais antigo e (no servidor
# local) a configuração da auditoria. Nunca interrompe o relatório.
function Test-LogSeguranca {

    param (
        [string]$Servidor,
        [datetime]$Inicio
    )

    $local = Test-ServidorLocal $Servidor

    $cn = @{}

    if (-not $local) {
        $cn.ComputerName = $Servidor
    }

    try {

        $log = Get-WinEvent -ListLog 'Security' -ErrorAction Stop @cn
        $mb = [math]::Round($log.MaximumSizeInBytes / 1MB)

        $primeiro = Get-WinEvent -LogName 'Security' -MaxEvents 1 -Oldest -ErrorAction Stop @cn

        Write-Host ("  Log de Segurança: máximo de {0} MB; evento mais antigo em {1}" -f
            $mb, $primeiro.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')) -ForegroundColor DarkGray

        if ($primeiro.TimeCreated -gt $Inicio) {

            Write-Warning (
                "[$Servidor] O log de Segurança começa em " +
                $primeiro.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss') +
                ", depois do início do período: eventos mais antigos já foram sobrescritos. " +
                "Aumente o tamanho do log (GPO) ou encaminhe/exporte os eventos."
            )
        }
        elseif ($EventoId -ne 4663 -and $mb -lt 1024) {

            Write-Host "  Dica: o evento $EventoId gera muito volume; considere aumentar o log de Segurança (hoje $mb MB)." -ForegroundColor DarkYellow
        }
    }
    catch {

        Write-Verbose "[$Servidor] Não foi possível verificar o log de Segurança: $($_.Exception.Message)"
    }

    if ($local) {

        # GUIDs das subcategorias (independem do idioma do Windows)
        switch ($EventoId) {
            4663 { $guid = '{0CCE921D-69AE-11D9-BED3-505054503030}' }
            5145 { $guid = '{0CCE9244-69AE-11D9-BED3-505054503030}' }
            5140 { $guid = '{0CCE9224-69AE-11D9-BED3-505054503030}' }
        }

        try {

            $linha = & auditpol.exe /get "/subcategory:$guid" /r 2>$null |
                Where-Object { $_ -match '\{0CCE' } |
                Select-Object -First 1

            if ($linha) {

                $config = ($linha -split ',')[4]

                Write-Host "  Auditoria da subcategoria do evento ${EventoId}: $config" -ForegroundColor DarkGray
            }
        }
        catch {

            Write-Verbose "Não foi possível consultar o auditpol: $($_.Exception.Message)"
        }
    }
}


# Lista os compartilhamentos não administrativos de um servidor.
function Get-CompartilhamentosServidor {

    param (
        [string]$Servidor
    )

    try {

        if (Test-ServidorLocal $Servidor) {

            $shares = Get-SmbShare -Special:$false -ErrorAction Stop
        }
        else {

            $cim = New-CimSession -ComputerName $Servidor -ErrorAction Stop

            try {
                $shares = Get-SmbShare -CimSession $cim -Special:$false -ErrorAction Stop
            }
            finally {
                Remove-CimSession $cim -ErrorAction SilentlyContinue
            }
        }

        return @($shares | Select-Object Name, Path, Description)
    }
    catch {

        Write-Warning "[$Servidor] Não foi possível listar os compartilhamentos: $($_.Exception.Message)"

        return @()
    }
}


# O Windows registra ShareName como \\*\Share, sem o nome real do servidor.
function ConvertTo-ShareServidor {
    param ([string]$Share, [string]$Servidor)
    if ($Share.StartsWith('\\*\') -and $Servidor) {
        return '\\' + $Servidor + $Share.Substring(3)
    }
    return $Share
}

function Test-FiltroRede {
    param ([string]$Filtro, [string]$Share, [string]$Relativo,
           [string]$ServidorEvento, [string]$ServidorConsulta)
    if ($Filtro -notmatch '^\\\\([^\\]+)\\(.+)$') { return $false }
    $hostFiltro = $Matches[1]
    $restante = $Matches[2].TrimEnd('\')
    $servidorValido = $false
    foreach ($nome in @($ServidorEvento, $ServidorConsulta)) {
        if (-not $nome) { continue }
        if ($hostFiltro -ieq $nome -or
            (($hostFiltro -notlike '*.*' -or $nome -notlike '*.*') -and
             ($hostFiltro.Split('.')[0] -ieq $nome.Split('.')[0]))) {
            $servidorValido = $true
        }
    }
    if (-not $servidorValido -or $Share -notmatch '^\\\\[^\\]+\\(.+)$') { return $false }
    $alvo = $Matches[1].TrimEnd('\')
    if ($Relativo) { $alvo += '\' + $Relativo.TrimStart('\') }
    return ($alvo -ieq $restante -or $alvo.StartsWith($restante + '\', [StringComparison]::OrdinalIgnoreCase))
}

# Converte um evento do log em um registro de acesso.
# Retorna $null quando o evento é filtrado ou não pôde ser processado.
function Convert-EventoAcesso {

    param (
        [Parameter(Mandatory = $true)]
        $Evento
    )

    $script:totalLidos++

    try {

        $xml = [xml]$Evento.ToXml()

        $dado = @{}

        foreach ($d in $xml.Event.EventData.Data) {

            if ($null -ne $d.Name) {
                $dado[$d.Name] = $d.'#text'
            }
        }


        # Valores padrão
        $objeto = ''
        $caminhoLocal = ''
        $ip = ''
        $porta = ''
        $acesso = ''
        $processo = ''
        $processId = ''
        $handleId = ''
        $compartilhamento = ''
        $caminhoRelativo = ''


        switch ($EventoId) {

            # Evento 4663 - acesso efetivo a arquivo/pasta
            4663 {

                $objeto = [string]$dado['ObjectName']
                $caminhoLocal = $objeto
                $acesso = Get-TipoAcesso $dado['AccessMask']
                $processo = [string]$dado['ProcessName']
                $processId = [string]$dado['ProcessId']
                $handleId = [string]$dado['HandleId']
            }

            # Evento 5145 - acesso detalhado via compartilhamento SMB
            5145 {

                $shareName = ConvertTo-ShareServidor ([string]$dado['ShareName']) ([string]$Evento.MachineName)
                $relativeTarget = [string]$dado['RelativeTargetName']
                $compartilhamento = $shareName
                $caminhoRelativo = $relativeTarget

                # ShareLocalPath vem como \??\D:\Dados\Financeiro
                $raiz = ([string]$dado['ShareLocalPath'] -replace '^\\\?\?\\', '').TrimEnd('\')

                if (-not [string]::IsNullOrWhiteSpace($relativeTarget)) {

                    $objeto = $shareName.TrimEnd('\') + '\' + $relativeTarget.TrimStart('\')

                    if (-not [string]::IsNullOrWhiteSpace($raiz)) {
                        $caminhoLocal = $raiz + '\' + $relativeTarget.TrimStart('\')
                    }
                }
                else {

                    $objeto = $shareName
                    $caminhoLocal = $raiz
                }

                $ip = ConvertTo-IpNormalizado ([string]$dado['IpAddress'])
                $porta = [string]$dado['IpPort']
                $acesso = Get-TipoAcesso $dado['AccessMask']
            }

            # Evento 5140 - conexão ao compartilhamento
            5140 {

                $objeto = ConvertTo-ShareServidor ([string]$dado['ShareName']) ([string]$Evento.MachineName)
                $compartilhamento = $objeto
                $caminhoLocal = ([string]$dado['ShareLocalPath'] -replace '^\\\?\?\\', '').TrimEnd('\')
                $ip = ConvertTo-IpNormalizado ([string]$dado['IpAddress'])
                $porta = [string]$dado['IpPort']
                $acesso = 'Conexão ao compartilhamento'
            }
        }


        # Usuário
        $user = [string]$dado['SubjectUserName']
        $domain = [string]$dado['SubjectDomainName']
        $logonId = [string]$dado['SubjectLogonId']

        # Ignora eventos sem usuário
        if ([string]::IsNullOrWhiteSpace($user)) {
            return $null
        }

        # Ignora contas de computador, salvo quando solicitado explicitamente
        if (-not $IncluirContasComputador -and $user -like '*$') {
            return $null
        }

        # Ignora compartilhamentos administrativos (IPC$, ADMIN$, C$...), que
        # geram muito ruído nos eventos 5145/5140
        if (
            -not $IncluirCompartilhamentosEspeciais -and
            $EventoId -ne 4663 -and
            $compartilhamento -match '\\(IPC\$|ADMIN\$|print\$|[A-Za-z]\$)$'
        ) {
            $script:ignoradosEspeciais++
            return $null
        }

        # Contas excluídas explicitamente (-ExcluirUsuarios)
        if ($ExcluirUsuarios.Count -gt 0) {

            $usuarioDominio = $user

            if (-not [string]::IsNullOrWhiteSpace($domain)) {
                $usuarioDominio = "$domain\$user"
            }

            foreach ($padraoExcluir in $ExcluirUsuarios) {

                if ($user -like $padraoExcluir -or $usuarioDominio -like $padraoExcluir) {
                    $script:ignoradosExcluidos++
                    return $null
                }
            }
        }

        # Filtro de usuário (com curingas). Se o filtro contiver "\", compara
        # com DOMINIO\usuario; caso contrário, só com o nome do usuário.
        $nomeParaFiltro = $user

        if ($Usuario -match '\\' -and -not [string]::IsNullOrWhiteSpace($domain)) {
            $nomeParaFiltro = "$domain\$user"
        }

        if ($nomeParaFiltro -notlike $Usuario) {
            return $null
        }

        # Filtro de pasta/arquivo: caminho de rede OU caminho local completo.
        # O nome do processo (4663) não participa do filtro.
        $correspondeObjeto =
            -not [string]::IsNullOrWhiteSpace($objeto) -and
            $objeto -like $padraoPasta

        $correspondeLocal =
            -not [string]::IsNullOrWhiteSpace($caminhoLocal) -and
            $caminhoLocal -like $padraoPasta

        # UNC considera servidor curto/FQDN e o servidor consultado (alias explícito).
        $correspondeRede = Test-FiltroRede -Filtro $Pasta -Share $compartilhamento `
            -Relativo $caminhoRelativo -ServidorEvento $Evento.MachineName -ServidorConsulta $servidor
        # 4663 contém apenas ObjectName local: a tradução depende do inventário SMB.
        $correspondeTraducao = $false
        if ($EventoId -eq 4663 -and $pastaLocalTraduzida) {
            $correspondeTraducao = $caminhoLocal -ieq $pastaLocalTraduzida -or
                $caminhoLocal.StartsWith($pastaLocalTraduzida + '\', [StringComparison]::OrdinalIgnoreCase)
        }
        if (-not $correspondeObjeto -and -not $correspondeLocal -and -not $correspondeRede -and -not $correspondeTraducao) {
            return $null
        }

        # Descarta acessos que são só "ruído" (opcional)
        if ($IgnorarAtributos -and $EventoId -ne 5140 -and (Test-AcessoRuido $dado['AccessMask'])) {
            $script:ignoradosRuido++
            return $null
        }

        # Êxito ou Falha (palavras-chave de auditoria do evento)
        $resultadoAcesso = 'Êxito'

        if ($Evento.Keywords -band 0x10000000000000) {
            $resultadoAcesso = 'Falha'
        }

        # Filtro por resultado (também aplicado na consulta XPath; mantido
        # aqui como garantia)
        if ($Resultado -eq 'Exito' -and $resultadoAcesso -ne 'Êxito') {
            return $null
        }

        if ($Resultado -eq 'Falha' -and $resultadoAcesso -ne 'Falha') {
            return $null
        }

        # domínio\usuário
        if ([string]::IsNullOrWhiteSpace($domain)) {
            $usuarioCompleto = $user
        }
        else {
            $usuarioCompleto = "$domain\$user"
        }

        # AccessList vem com códigos (%%4416...) separados por tabs/quebras de
        # linha; normaliza os espaços para não bagunçar o CSV.
        $listaAcesso = ([string]$dado['AccessList'] -replace '\s+', ' ').Trim()

        # AccessReason (5145): informa qual ACE liberou o acesso. Resolve os
        # SIDs para nomes e sinaliza liberação por grupo amplo.
        $razaoAcesso = ([string]$dado['AccessReason'] -replace '\s+', ' ').Trim()
        $concedidoPor = ''
        $permissaoAmpla = ''

        if ($EventoId -eq 5145 -and -not [string]::IsNullOrWhiteSpace($razaoAcesso)) {

            $concessao = Get-ConcessaoAcesso $razaoAcesso
            $concedidoPor = $concessao.Contas

            if ($concessao.Ampla) {
                $permissaoAmpla = 'Sim'
            }
            else {
                $permissaoAmpla = 'Nao'
            }
        }

        $pastaResumo = Get-PastaResumo `
            -Compartilhamento $compartilhamento `
            -CaminhoRelativo $caminhoRelativo `
            -CaminhoLocal $caminhoLocal


        return [PSCustomObject]@{

            DataHora         = $Evento.TimeCreated
            PrimeiroAcesso   = $Evento.TimeCreated
            UltimoAcesso     = $Evento.TimeCreated
            Servidor         = $Evento.MachineName
            RecordId         = $Evento.RecordId
            Usuario          = $usuarioCompleto
            Resultado        = $resultadoAcesso
            IP               = $ip
            Porta            = $porta
            Acesso           = $acesso
            AccessList       = $listaAcesso
            AccessMask       = [string]$dado['AccessMask']
            Objeto           = $objeto
            Compartilhamento = $compartilhamento
            CaminhoRelativo  = $caminhoRelativo
            CaminhoLocal     = $caminhoLocal
            Processo         = $processo
            ProcessId        = $processId
            HandleId         = $handleId
            LogonId          = $logonId
            EventoId         = $Evento.Id
            Ocorrencias      = 1
            UsuarioSid       = [string]$dado['SubjectUserSid']
            TipoObjeto       = [string]$dado['ObjectType']
            AccessReason     = $razaoAcesso
            ConcedidoPor     = $concedidoPor
            PermissaoAmpla   = $permissaoAmpla
            PastaResumo      = $pastaResumo
            Estacao          = ''
            Departamento     = ''
            Cargo            = ''
            Autorizacao      = ''
        }

    }
    catch {

        $script:falhasParse++

        Write-Verbose (
            "Erro ao processar evento RecordId " +
            "$($Evento.RecordId): $($_.Exception.Message)"
        )

        return $null
    }
}


# Menu opcional; executa este mesmo arquivo com os parâmetros escolhidos.
function Show-MenuRelatorioAcesso {
    param ([string]$ScriptRelatorio, [hashtable]$ParametrosIniciais = @{})
    $ptBR = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')

    # A leitura real exige Windows; o menu pode ser inspecionado sem consultar dados.
    if ($env:OS -eq 'Windows_NT') {
        try {
            $ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $ehAdmin) { Write-Warning 'Abra como administrador se a leitura do log for negada.' }
        } catch { Write-Verbose 'Não foi possível verificar a elevação da sessão.' }
    }

    # ============================================================
    # Configuração atual (valores iniciais = padrões do script original)
    # ============================================================

    $cfg = [ordered]@{
        Computador       = @($env:COMPUTERNAME)
        EventoId         = 5145
        UsaPeriodo       = $false
        Dias             = 1
        Inicio           = $null
        Fim              = $null
        Pasta            = ''
        Usuario          = '*'
        UsuarioExato     = $false
        Resultado        = 'Todos'
        ExcluirUsuarios  = @()
        CsvSaida         = ''
        CsvResumo        = ''
        ListaAutorizados = ''
    }

    $opcoes = [ordered]@{
        IgnorarAtributos                  = @{ Ativo = $false; Desc = 'Descarta acessos de "ruído" (ler atributos/permissões)' }
        Agrupar                           = @{ Ativo = $false; Desc = 'Agrupa eventos repetidos no mesmo minuto' }
        IncluirContasComputador           = @{ Ativo = $false; Desc = 'Inclui contas de computador (terminadas em $)' }
        IncluirCompartilhamentosEspeciais = @{ Ativo = $false; Desc = 'Inclui IPC$, ADMIN$, C$...' }
        ListarCompartilhamentos           = @{ Ativo = $false; Desc = 'Lista compartilhamentos e registros encontrados' }
        EnriquecerAD                      = @{ Ativo = $false; Desc = 'Departamento e cargo do AD' }
        ResolverIP                        = @{ Ativo = $false; Desc = 'Nome da estação (DNS reverso)' }
        Silencioso                        = @{ Ativo = $false; Desc = 'Não imprime resumos no console' }
        GridView                          = @{ Ativo = $false; Desc = 'Abre o resultado em janela' }
        PassThru                          = @{ Ativo = $false; Desc = 'Retorna objetos para o pipeline' }
    }

    # Reutilizar valores explícitos da linha de comando ao abrir o menu.
    foreach ($chave in $ParametrosIniciais.Keys) {
        if ($cfg.Contains($chave)) { $cfg[$chave] = $ParametrosIniciais[$chave] }
        if ($opcoes.Contains($chave)) { $opcoes[$chave].Ativo = [bool]$ParametrosIniciais[$chave] }
    }
    $cfg.Computador = @($cfg.Computador)
    $cfg.ExcluirUsuarios = @($cfg.ExcluirUsuarios)
    $cfg.UsaPeriodo = $ParametrosIniciais.ContainsKey('Inicio')

    $descEvento = @{
        5145 = '5145 - Verificação de acesso SMB [padrão]'
        4663 = '4663 - Uso de direito no objeto (exige SACL)'
        5140 = '5140 - Conexão a um compartilhamento'
    }


    # ============================================================
    # Funções de entrada
    # ============================================================

    function Read-Texto {
        param (
            [string]$Pergunta,
            [string]$Atual = ''
        )

        if ($Atual) { $r = Read-Host "$Pergunta [$Atual]" }
        else        { $r = Read-Host $Pergunta }

        if ([string]::IsNullOrWhiteSpace($r)) { return $Atual }

        $r = $r.Trim().Trim('"')

        if ($r -eq '-') { return '' }   # "-" limpa o valor

        return $r
    }

    function ConvertTo-Lista {
        param ([string]$Texto)

        return @(
            $Texto -split '[,;]' |
            ForEach-Object { $_.Trim().Trim('"') } |
            Where-Object { $_ }
        )
    }

    function Read-Inteiro {
        param (
            [string]$Pergunta,
            [int]$Atual,
            [int]$Min,
            [int]$Max
        )

        while ($true) {

            $r = Read-Texto $Pergunta ([string]$Atual)
            $n = 0

            if ([int]::TryParse($r, [ref]$n) -and $n -ge $Min -and $n -le $Max) {
                return $n
            }

            Write-Host "  Valor inválido. Informe um número entre $Min e $Max." -ForegroundColor Yellow
        }
    }

    function Read-Data {
        param (
            [string]$Pergunta,
            $Atual,
            [bool]$Opcional = $false
        )

        while ($true) {

            $textoAtual = ''
            if ($null -ne $Atual) { $textoAtual = $Atual.ToString('dd/MM/yyyy HH:mm') }

            $r = Read-Texto $Pergunta $textoAtual

            if ([string]::IsNullOrWhiteSpace($r)) {

                if ($Opcional) { return $null }

                Write-Host '  Informe uma data.' -ForegroundColor Yellow
                continue
            }

            $d = [datetime]::MinValue

            if ([datetime]::TryParse($r, $ptBR, [System.Globalization.DateTimeStyles]::None, [ref]$d)) {
                return $d
            }

            Write-Host '  Data inválida. Use dd/MM/yyyy HH:mm (ex.: 19/10/2026 08:00).' -ForegroundColor Yellow
        }
    }


    # ============================================================
    # Edição de cada item do menu
    # ============================================================

    function Edit-Servidores {

        Write-Host ''
        Write-Host 'Um ou mais servidores de arquivos, separados por vírgula (ex.: SRV-ARQ1,SRV-ARQ2).'

        $r = Read-Texto 'Servidor(es)' ($cfg.Computador -join ',')
        $lista = ConvertTo-Lista $r

        if ($lista.Count -gt 0) { $cfg.Computador = $lista }
    }

    function Edit-Evento {

        Write-Host ''
        Write-Host '  1) ' $descEvento[5145]
        Write-Host '  2) ' $descEvento[4663]
        Write-Host '  3) ' $descEvento[5140]

        $r = Read-Host 'Escolha o evento (Enter mantém o atual)'

        switch ($r.Trim()) {
            '1' { $cfg.EventoId = 5145 }
            '2' { $cfg.EventoId = 4663 }
            '3' { $cfg.EventoId = 5140 }
        }
    }

    function Edit-Periodo {

        Write-Host ''
        Write-Host '  1) Últimos N dias'
        Write-Host '  2) Período específico (início e fim)'

        $r = (Read-Host 'Escolha').Trim()

        if ($r -eq '1') {

            $cfg.UsaPeriodo = $false
            $cfg.Dias = Read-Inteiro 'Quantos dias para trás' $cfg.Dias 1 3650
        }
        elseif ($r -eq '2') {

            while ($true) {

                $ini = Read-Data 'Início (dd/MM/yyyy HH:mm)' $cfg.Inicio
                $fim = Read-Data 'Fim (Enter mantém; "-" = até agora)' $cfg.Fim $true

                if ($null -ne $fim -and $fim -le $ini) {
                    Write-Host '  O fim deve ser posterior ao início.' -ForegroundColor Yellow
                    continue
                }

                $cfg.Inicio = $ini
                $cfg.Fim = $fim
                $cfg.UsaPeriodo = $true
                break
            }
        }
    }

    function Edit-Pasta {

        Write-Host ''
        Write-Host 'Trecho do caminho, pasta, arquivo ou compartilhamento a filtrar.'
        Write-Host 'Exemplos: RH | E:\FileServer\RH | \\SRV\z\RH'
        Write-Host 'Enter mantém a pasta atual; "-" pesquisa todas as pastas.'

        $cfg.Pasta = Read-Texto 'Pasta' $cfg.Pasta
    }

    function Edit-Usuario {

        Write-Host ''
        Write-Host 'Aceita curingas (joao, joao*, *silva*) ou DOMINIO\usuario. "*" = todos.'

        $r = Read-Texto 'Usuário' $cfg.Usuario

        if ([string]::IsNullOrWhiteSpace($r)) { $r = '*' }

        $cfg.Usuario = $r

        $cfg.UsuarioExato = $false

        if ($r -notmatch '[\*\?\[\]\\"'']') {

            $exato = Read-Host 'Filtrar direto no log (mais rápido, diferencia maiúsculas/minúsculas)? (S/N) [N]'

            if ($exato -match '^[sSyY]') { $cfg.UsuarioExato = $true }
        }
    }

    function Edit-Resultado {

        Write-Host ''
        Write-Host '  1) Todos'
        Write-Host '  2) Somente êxito'
        Write-Host '  3) Somente falha'

        $r = Read-Host 'Escolha (Enter mantém o atual)'

        switch ($r.Trim()) {
            '1' { $cfg.Resultado = 'Todos' }
            '2' { $cfg.Resultado = 'Exito' }
            '3' { $cfg.Resultado = 'Falha' }
        }
    }

    function Edit-ExcluirUsuarios {

        Write-Host ''
        Write-Host 'Contas de serviço a ignorar, separadas por vírgula (curingas aceitos).'
        Write-Host 'Exemplo: svc-backup,svc-av*   ("-" limpa a lista)'

        $r = Read-Texto 'Excluir usuários' ($cfg.ExcluirUsuarios -join ',')

        $cfg.ExcluirUsuarios = ConvertTo-Lista $r
    }

    function Edit-Opcoes {

        while ($true) {

            $chaves = @($opcoes.Keys)

            Write-Host ''

            for ($i = 0; $i -lt $chaves.Count; $i++) {

                $k = $chaves[$i]

                if ($opcoes[$k].Ativo) { $marca = 'X' } else { $marca = ' ' }

                Write-Host ('  {0,2}) [{1}] {2,-35} {3}' -f ($i + 1), $marca, $k, $opcoes[$k].Desc)
            }

            $r = Read-Host 'Números para marcar/desmarcar (ex.: 1,2) ou Enter para voltar'

            if ([string]::IsNullOrWhiteSpace($r)) { return }

            foreach ($n in (ConvertTo-Lista $r)) {

                if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $chaves.Count) {

                    $k = $chaves[[int]$n - 1]
                    $opcoes[$k].Ativo = -not $opcoes[$k].Ativo
                }
            }
        }
    }

    function Edit-Csv {
        param ([string]$Campo, [string]$Titulo)

        Write-Host ''
        Write-Host 'Caminho do arquivo CSV. Aceita {data} (vira yyyyMMdd-HHmmss).'
        Write-Host 'Exemplo: C:\Relatorios\acessos-{data}.csv   ("-" desativa)'

        $cfg[$Campo] = Read-Texto $Titulo $cfg[$Campo]
    }

    function Edit-ListaAutorizados {

        Write-Host ''
        Write-Host 'CSV (separador ";") com as colunas Pasta;Grupo. Requer RSAT/ActiveDirectory.'

        while ($true) {

            $r = Read-Texto 'Lista de autorizados ("-" desativa)' $cfg.ListaAutorizados

            if ([string]::IsNullOrWhiteSpace($r) -or (Test-Path -LiteralPath $r)) {
                $cfg.ListaAutorizados = $r
                return
            }

            Write-Host '  Arquivo não encontrado.' -ForegroundColor Yellow
        }
    }


    # ============================================================
    # Montagem e execução
    # ============================================================

    function New-Parametros {

        $p = @{}

        $p.Computador = @($cfg.Computador)
        $p.EventoId = [int]$cfg.EventoId

        if ($cfg.UsaPeriodo -and $null -ne $cfg.Inicio) {

            $p.Inicio = $cfg.Inicio

            if ($null -ne $cfg.Fim) { $p.Fim = $cfg.Fim }
        }
        else {
            $p.Dias = [int]$cfg.Dias
        }

        if ($cfg.Pasta)                     { $p.Pasta = $cfg.Pasta }
        if ($cfg.Usuario -and $cfg.Usuario -ne '*') { $p.Usuario = $cfg.Usuario }
        if ($cfg.UsuarioExato)              { $p.UsuarioExato = $true }
        if ($cfg.Resultado -ne 'Todos')     { $p.Resultado = $cfg.Resultado }
        if ($cfg.ExcluirUsuarios.Count -gt 0) { $p.ExcluirUsuarios = @($cfg.ExcluirUsuarios) }
        if ($cfg.CsvSaida)                  { $p.CsvSaida = $cfg.CsvSaida }
        if ($cfg.CsvResumo)                 { $p.CsvResumo = $cfg.CsvResumo }
        if ($cfg.ListaAutorizados)          { $p.ListaAutorizados = $cfg.ListaAutorizados }

        foreach ($k in $opcoes.Keys) {
            if ($opcoes[$k].Ativo) { $p[$k] = $true }
        }

        return $p
    }

    function Format-Valor {
        param ($Valor)

        if ($Valor -is [datetime]) {
            return '[datetime]::new(' + (@($Valor.Year, $Valor.Month, $Valor.Day, $Valor.Hour, $Valor.Minute, $Valor.Second, $Valor.Millisecond) -join ',') + ')'
        }
        if ($Valor -is [int])      { return [string]$Valor }

        if ($Valor -is [array]) {
            return (($Valor | ForEach-Object { Format-Valor $_ }) -join ',')
        }

        return "'" + ([string]$Valor -replace "'", "''") + "'"
    }

    function Format-Comando {
        param ($Parametros)

        $partes = @('& ' + (Format-Valor $ScriptRelatorio))

        foreach ($k in $Parametros.Keys) {

            if ($Parametros[$k] -is [bool]) { $partes += "-$k" }
            else                            { $partes += "-$k " + (Format-Valor $Parametros[$k]) }
        }

        return ($partes -join ' ')
    }

    function Invoke-Relatorio {

        if ($cfg.UsaPeriodo -and $null -eq $cfg.Inicio) {
            Write-Host 'Defina o início do período antes de executar.' -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            return
        }

        $p = New-Parametros

        Write-Host ''
        Write-Host 'Comando equivalente (revise os caminhos antes de agendar):' -ForegroundColor Cyan
        Write-Host (Format-Comando $p) -ForegroundColor Gray
        Write-Host ''

        do { $r = (Read-Host 'Executar agora? (S/N) [S]').Trim() }
        while ($r -notmatch '^(?:[sSnN])?$')
        if ($r -match '^[nN]$') { return }

        try {
            & $ScriptRelatorio @p
        }
        catch {
            Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host ''
        Read-Host 'Pressione Enter para voltar ao menu' | Out-Null
    }


    # ============================================================
    # Menu principal
    # ============================================================

    function Show-Menu {

        Clear-Host

        if ($cfg.UsaPeriodo -and $null -ne $cfg.Inicio) {

            $textoPeriodo = $cfg.Inicio.ToString('dd/MM/yyyy HH:mm') + ' até '

            if ($null -ne $cfg.Fim) { $textoPeriodo += $cfg.Fim.ToString('dd/MM/yyyy HH:mm') }
            else                    { $textoPeriodo += 'agora' }
        }
        else {
            $textoPeriodo = "últimos $($cfg.Dias) dia(s)"
        }

        if ($cfg.Pasta) { $textoPasta = $cfg.Pasta } else { $textoPasta = '(todas)' }

        $textoUsuario = $cfg.Usuario
        if ($cfg.UsuarioExato) { $textoUsuario += ' (exato)' }

        if ($cfg.ExcluirUsuarios.Count -gt 0) { $textoExcluir = $cfg.ExcluirUsuarios -join ', ' } else { $textoExcluir = '(nenhum)' }

        $ativas = @($opcoes.Keys | Where-Object { $opcoes[$_].Ativo })
        if ($ativas.Count -gt 0) { $textoOpcoes = $ativas -join ', ' } else { $textoOpcoes = '(nenhuma)' }

        if ($cfg.CsvSaida)         { $textoCsv = $cfg.CsvSaida }         else { $textoCsv = '(não exporta)' }
        if ($cfg.CsvResumo)        { $textoResumo = $cfg.CsvResumo }     else { $textoResumo = '(não exporta)' }
        if ($cfg.ListaAutorizados) { $textoAut = $cfg.ListaAutorizados } else { $textoAut = '(não usa)' }

        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' RELATÓRIO DE AUDITORIA DE ACESSOS - MENU' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host " 1) Servidor(es)          : $($cfg.Computador -join ', ')"
        Write-Host " 2) Evento                : $($descEvento[[int]$cfg.EventoId])"
        Write-Host " 3) Período               : $textoPeriodo"
        Write-Host " 4) Pasta/compartilhamento: $textoPasta"
        Write-Host " 5) Usuário               : $textoUsuario"
        Write-Host " 6) Resultado             : $($cfg.Resultado)"
        Write-Host " 7) Excluir usuários      : $textoExcluir"
        Write-Host " 8) Opções                : $textoOpcoes"
        Write-Host " 9) CSV detalhado         : $textoCsv"
        Write-Host "10) CSV resumo            : $textoResumo"
        Write-Host "11) Lista de autorizados  : $textoAut"
        Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host ' E) Executar relatório      Q) Sair'
        Write-Host ' Enter mantém o valor; - limpa um filtro ou caminho.'
        if ($cfg.ListaAutorizados) { Write-Host ' Autorização por grupos: prefira a v8 para classificação por SID.' -ForegroundColor Yellow }
        Write-Host '============================================================' -ForegroundColor DarkGray
    }

    while ($true) {

        Show-Menu

        $op = (Read-Host 'Escolha uma opção').Trim().ToUpper()

        switch ($op) {
            '1'  { Edit-Servidores }
            '2'  { Edit-Evento }
            '3'  { Edit-Periodo }
            '4'  { Edit-Pasta }
            '5'  { Edit-Usuario }
            '6'  { Edit-Resultado }
            '7'  { Edit-ExcluirUsuarios }
            '8'  { Edit-Opcoes }
            '9'  { Edit-Csv -Campo 'CsvSaida'  -Titulo 'CSV detalhado' }
            '10' { Edit-Csv -Campo 'CsvResumo' -Titulo 'CSV resumo' }
            '11' { Edit-ListaAutorizados }
            'E'  { Invoke-Relatorio }
            'Q'  { return }
            default { }
        }
    }
}

if ($Menu) {
    $iniciais = @{}
    foreach ($chave in $PSBoundParameters.Keys) {
        if ($chave -ne 'Menu') { $iniciais[$chave] = $PSBoundParameters[$chave] }
    }
    Show-MenuRelatorioAcesso -ScriptRelatorio $PSCommandPath -ParametrosIniciais $iniciais
    return
}

# ============================================================
# Configuração inicial
# ============================================================

if ($PSCmdlet.ParameterSetName -eq 'Periodo') {

    $dataInicio = $Inicio
    $usaFim = $PSBoundParameters.ContainsKey('Fim')

    if ($usaFim) {
        $dataFim = $Fim
    }
    else {
        $dataFim = Get-Date
    }

    if ($dataFim -le $dataInicio) {
        Write-Error '-Fim deve ser posterior a -Inicio.'
        return
    }
}
else {

    $dataInicio = (Get-Date).AddDays(-$Dias)
    $dataFim = Get-Date
    $usaFim = $false
}

# Padrão de busca da pasta com caracteres especiais escapados ([ ] * ?)
# (sem -Pasta, o filtro de pasta fica aberto e considera tudo)
if ([string]::IsNullOrWhiteSpace($Pasta)) {
    $padraoPasta = '*'
}
else {
    $padraoPasta = '*' + [WildcardPattern]::Escape($Pasta) + '*'
}

# Contadores de controle
$totalLidos = 0
$falhasParse = 0
$ignoradosRuido = 0
$ignoradosEspeciais = 0
$ignoradosExcluidos = 0

# Cache de resolução de SIDs e apelidos SDDL usados no AccessReason (5145)
$cacheSid = @{}
$aliasesSddl = @{
    WD = 'Everyone'
    AU = 'NT AUTHORITY\Authenticated Users'
    BU = 'BUILTIN\Users'
    BA = 'BUILTIN\Administrators'
    SY = 'NT AUTHORITY\SYSTEM'
    DU = 'Domain Users'
    DA = 'Domain Admins'
    DG = 'Domain Guests'
    DC = 'Domain Computers'
    DD = 'Domain Controllers'
    CO = 'CREATOR OWNER'
    CG = 'CREATOR GROUP'
    IU = 'NT AUTHORITY\INTERACTIVE'
    NU = 'NT AUTHORITY\NETWORK'
    AN = 'NT AUTHORITY\ANONYMOUS LOGON'
    LS = 'NT AUTHORITY\LOCAL SERVICE'
    NS = 'NT AUTHORITY\NETWORK SERVICE'
    BO = 'BUILTIN\Backup Operators'
    SO = 'BUILTIN\Server Operators'
    AO = 'BUILTIN\Account Operators'
    BG = 'BUILTIN\Guests'
    RD = 'BUILTIN\Remote Desktop Users'
}

$listaShares = New-Object 'System.Collections.Generic.List[object]'

# Token {data} nos caminhos de CSV (útil em execuções agendadas)
if (-not [string]::IsNullOrWhiteSpace($CsvSaida)) {
    $CsvSaida = $CsvSaida -replace '\{data\}', (Get-Date -Format 'yyyyMMdd-HHmmss')
}

if (-not [string]::IsNullOrWhiteSpace($CsvResumo)) {
    $CsvResumo = $CsvResumo -replace '\{data\}', (Get-Date -Format 'yyyyMMdd-HHmmss')
}

$servidoresComErro = New-Object 'System.Collections.Generic.List[string]'
$servidoresSemEventos = New-Object 'System.Collections.Generic.List[string]'

if ($usaFim) {
    $textoFim = $dataFim.ToString('dd/MM/yyyy HH:mm:ss')
}
else {
    $textoFim = 'agora'
}


Write-Host ''
Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ' RELATÓRIO DE AUDITORIA DE ACESSOS' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor DarkGray

Write-Host "Servidor(es): $($Computador -join ', ')"
Write-Host "Evento      : $EventoId"
if ([string]::IsNullOrWhiteSpace($Pasta)) {
    Write-Host 'Filtro      : (todas as pastas/compartilhamentos)'
}
else {
    Write-Host "Filtro      : $Pasta"
}
Write-Host "Usuário     : $Usuario"
Write-Host "Resultado   : $Resultado"
Write-Host "Período     : $($dataInicio.ToString('dd/MM/yyyy HH:mm:ss')) até $textoFim"

Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ''


# ============================================================
# Lista de autorizados (opcional)
# ============================================================

$regrasAutorizacao = @()
$membrosPorGrupo = @{}

if (-not [string]::IsNullOrWhiteSpace($ListaAutorizados)) {

    if (-not (Test-Path -LiteralPath $ListaAutorizados)) {
        Write-Error "Arquivo de autorizados não encontrado: $ListaAutorizados"
        return
    }

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Error 'O módulo ActiveDirectory (RSAT) é necessário para usar -ListaAutorizados.'
        return
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    $linhasLista = @(Import-Csv -LiteralPath $ListaAutorizados -Delimiter ';' -Encoding UTF8)

    foreach ($linha in $linhasLista) {

        $pastaRegra = ([string]$linha.Pasta).Trim()
        $grupoRegra = ([string]$linha.Grupo).Trim()

        if ($pastaRegra -and $grupoRegra) {

            $regrasAutorizacao += [PSCustomObject]@{
                Pasta  = $pastaRegra
                Grupo  = $grupoRegra
                Padrao = '*' + [WildcardPattern]::Escape($pastaRegra) + '*'
            }
        }
    }

    if ($regrasAutorizacao.Count -eq 0) {
        Write-Error "Nenhuma regra válida em '$ListaAutorizados' (use as colunas Pasta;Grupo, separadas por ';')."
        return
    }

    $gruposDistintos = @($regrasAutorizacao | ForEach-Object { $_.Grupo } | Sort-Object -Unique)

    foreach ($grupo in $gruposDistintos) {

        $nomeGrupo = $grupo -replace '^.*\\', ''

        try {

            $membros = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

            Get-ADGroupMember -Identity $nomeGrupo -Recursive -ErrorAction Stop |
                ForEach-Object { [void]$membros.Add([string]$_.SamAccountName) }

            $membrosPorGrupo[$grupo] = $membros
        }
        catch {

            Write-Warning "Grupo '$grupo' não pôde ser lido: $($_.Exception.Message)"
        }
    }

    Write-Host "Autorizados : $($regrasAutorizacao.Count) regra(s); $($membrosPorGrupo.Count) de $($gruposDistintos.Count) grupo(s) lidos" -ForegroundColor DarkGray
    Write-Host ''
}


# ============================================================
# Montagem do filtro XPath (aplicado direto no log)
# ============================================================

$clausulaTempo = "@SystemTime>='$(ConvertTo-XPathTime $dataInicio)'"

if ($usaFim) {
    $clausulaTempo += " and @SystemTime<='$(ConvertTo-XPathTime $dataFim)'"
}

$condicoesSistema = "(EventID=$EventoId)"

# Palavras-chave de auditoria: Falha = 0x10000000000000, Êxito = 0x20000000000000
# (mesma sintaxe band() das exibições personalizadas do Visualizador de Eventos)
if ($Resultado -eq 'Falha') {
    $condicoesSistema += ' and band(Keywords,4503599627370496)'
}
elseif ($Resultado -eq 'Exito') {
    $condicoesSistema += ' and band(Keywords,9007199254740992)'
}

$condicoesSistema += " and TimeCreated[$clausulaTempo]"

$xpath = "*[System[$condicoesSistema]"

# Filtro de usuário na consulta (opcional, mais rápido; diferencia maiúsculas).
# Se houver aspas ou "\" no nome, o filtro fica apenas no PowerShell para evitar
# incompatibilidades com o subconjunto XPath aceito pelo Event Log.
if (
    $UsuarioExato -and
    $Usuario -notmatch '[\*\?\[\]\\]' -and
    $Usuario -notmatch '["'']'
) {

    $xpath += " and EventData[Data[@Name='SubjectUserName']='$Usuario']"
}
elseif ($UsuarioExato) {

    Write-Verbose 'Nome de usuário com curinga, aspas ou "\"; filtro XPath otimizado não será aplicado.'
}

$xpath += ']'

Write-Verbose "XPath: $xpath"


# ============================================================
# Consulta e processamento (streaming, servidor por servidor)
# ============================================================

$registros = New-Object 'System.Collections.Generic.List[object]'
$indiceGrupos = @{}

foreach ($servidor in $Computador) {
    $pastaLocalTraduzida = ''
    if ($EventoId -eq 4663 -and $Pasta -match '^\\\\([^\\]+)\\([^\\]+)(.*)$') {
        $hostFiltro = $Matches[1]; $nomeShare = $Matches[2]; $subcaminho = $Matches[3]
        if ($hostFiltro -ieq $servidor -or
            (($hostFiltro -notlike '*.*' -or $servidor -notlike '*.*') -and
             ($hostFiltro.Split('.')[0] -ieq $servidor.Split('.')[0]))) {
            $shareFiltro = @(Get-CompartilhamentosServidor -Servidor $servidor | Where-Object { $_.Name -ieq $nomeShare })
            if ($shareFiltro.Count -eq 1 -and $shareFiltro[0].Path) {
                $pastaLocalTraduzida = ([string]$shareFiltro[0].Path).TrimEnd('\') + $subcaminho.TrimEnd('\')
            } else {
                Write-Warning "Não foi possível traduzir '$Pasta' para o caminho local no servidor '$servidor'. Para 4663 use o caminho absoluto, por exemplo E:\FileServer, ou confira o inventário SMB."
            }
        }
    }


    Write-Host "Consultando log de Segurança em $servidor..." -ForegroundColor Cyan

    Test-LogSeguranca -Servidor $servidor -Inicio $dataInicio

    if ($ListarCompartilhamentos) {

        $sharesServidor = @(Get-CompartilhamentosServidor -Servidor $servidor)

        foreach ($sh in $sharesServidor) {

            $listaShares.Add([PSCustomObject]@{
                Servidor  = $servidor
                Nome      = $sh.Name
                Caminho   = $sh.Path
                Descricao = $sh.Description
            })
        }

        if (-not $Silencioso -and $sharesServidor.Count -gt 0) {

            Write-Host "  Compartilhamentos em ${servidor}: $($sharesServidor.Count)" -ForegroundColor DarkGray

            $sharesServidor |
                Format-Table Name, Path -AutoSize |
                Out-Host
        }
    }

    # Servidor local: lê direto, sem RPC (-ComputerName só para remotos)
    $parametrosLog = @{
        LogName     = 'Security'
        FilterXPath = $xpath
        ErrorAction = 'Stop'
    }

    if (-not (Test-ServidorLocal $servidor)) {
        $parametrosLog.ComputerName = $servidor
    }

    try {

        Get-WinEvent @parametrosLog |
            ForEach-Object {

                $registro = Convert-EventoAcesso -Evento $_

                if ($null -eq $registro) {
                    return
                }

                if ($Agrupar) {

                    $chave = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}' -f
                        $registro.Servidor,
                        $registro.Usuario,
                        $registro.LogonId,
                        $registro.IP,
                        $registro.Porta,
                        $registro.Objeto,
                        $registro.Acesso,
                        $registro.AccessMask,
                        $registro.ProcessId,
                        $registro.Resultado,
                        $registro.DataHora.ToString('yyyyMMddHHmm')

                    if ($indiceGrupos.ContainsKey($chave)) {

                        $grupo = $indiceGrupos[$chave]
                        $grupo.Ocorrencias++

                        # Preserva a janela temporal do grupo e mantém DataHora/RecordId
                        # referentes ao evento mais recente.
                        if ($registro.DataHora -lt $grupo.PrimeiroAcesso) {
                            $grupo.PrimeiroAcesso = $registro.DataHora
                        }

                        if ($registro.DataHora -gt $grupo.UltimoAcesso) {
                            $grupo.UltimoAcesso = $registro.DataHora
                        }

                        if ($registro.DataHora -gt $grupo.DataHora) {
                            $grupo.DataHora = $registro.DataHora
                            $grupo.RecordId = $registro.RecordId
                        }
                    }
                    else {

                        $indiceGrupos[$chave] = $registro
                        $registros.Add($registro)
                    }
                }
                else {

                    $registros.Add($registro)
                }
            }

    }
    catch {

        # Detecção independente do idioma do Windows
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {

            $servidoresSemEventos.Add($servidor)
            continue
        }

        Write-Warning "[$servidor] Falha ao ler o log de Segurança: $($_.Exception.Message)"

        $servidoresComErro.Add($servidor)
        continue
    }
}


# ============================================================
# Verificar resultado
# ============================================================

if ($registros.Count -eq 0) {

    Write-Host ''
    Write-Warning "Nenhum acesso encontrado para '$Pasta' no período informado."

    Write-Host ''
    Write-Host 'Possíveis motivos:' -ForegroundColor Yellow
    Write-Host ' - A pasta não teve acesso no período.'
    Write-Host ' - O evento escolhido não está sendo auditado.'
    Write-Host ' - O nome informado em -Pasta não corresponde ao log.'
    Write-Host ' - O log de Segurança já sobrescreveu eventos antigos.'

    if ($UsuarioExato) {
        Write-Host ' - Com -UsuarioExato a comparação diferencia maiúsculas de minúsculas.'
    }

    if ($Resultado -ne 'Todos') {
        Write-Host " - O filtro -Resultado $Resultado pode estar excluindo os eventos existentes."
    }

    if ($servidoresSemEventos.Count -gt 0) {
        Write-Host " - Sem eventos do tipo $EventoId em: $($servidoresSemEventos -join ', ')."
    }

    if ($servidoresComErro.Count -gt 0) {
        Write-Host " - Falha de leitura em: $($servidoresComErro -join ', ') (execute como Administrador; verifique RPC/firewall)."
    }

    if ($ignoradosRuido -gt 0) {
        Write-Host " - $ignoradosRuido evento(s) foram descartados por -IgnorarAtributos."
    }

    if ($ignoradosEspeciais -gt 0) {
        Write-Host " - $ignoradosEspeciais evento(s) de compartilhamentos administrativos (IPC$, ADMIN$, C$...) foram descartados; use -IncluirCompartilhamentosEspeciais para vê-los."
    }

    if ($ignoradosExcluidos -gt 0) {
        Write-Host " - $ignoradosExcluidos evento(s) foram descartados por -ExcluirUsuarios."
    }

    if ($falhasParse -gt 0) {
        Write-Warning "$falhasParse evento(s) não puderam ser processados (use -Verbose para detalhes)."
    }

    return
}


# ============================================================
# Ordenação e totais
# ============================================================

$registros = @(
    $registros |
    Sort-Object DataHora -Descending
)

# Status de autorização (lista de autorizados)
if ($regrasAutorizacao.Count -gt 0) {

    foreach ($r in $registros) {
        $r.Autorizacao = Get-StatusAutorizacao $r
    }
}

# Departamento e cargo (AD), com cache por usuário
if ($EnriquecerAD) {

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {

        Write-Warning 'Módulo ActiveDirectory não encontrado; -EnriquecerAD foi ignorado.'
    }
    else {

        Import-Module ActiveDirectory -ErrorAction SilentlyContinue

        $cacheAD = @{}

        foreach ($r in $registros) {

            $sam = ([string]$r.Usuario) -replace '^.*\\', ''

            if (-not $cacheAD.ContainsKey($sam)) {

                try {

                    $u = Get-ADUser -Identity $sam -Properties Department, Title -ErrorAction Stop

                    $cacheAD[$sam] = [PSCustomObject]@{
                        Departamento = [string]$u.Department
                        Cargo        = [string]$u.Title
                    }
                }
                catch {

                    $cacheAD[$sam] = [PSCustomObject]@{ Departamento = ''; Cargo = '' }
                }
            }

            $r.Departamento = $cacheAD[$sam].Departamento
            $r.Cargo = $cacheAD[$sam].Cargo
        }
    }
}

# Nome da estação (DNS reverso), com cache por IP
if ($ResolverIP) {

    $cacheIP = @{}

    foreach ($r in $registros) {

        if ([string]::IsNullOrWhiteSpace($r.IP)) {
            continue
        }

        if (-not $cacheIP.ContainsKey($r.IP)) {

            $nomeEstacao = ''

            try {
                $nomeEstacao = [System.Net.Dns]::GetHostEntry($r.IP).HostName
            }
            catch {
                $nomeEstacao = ''
            }

            $cacheIP[$r.IP] = $nomeEstacao
        }

        $r.Estacao = $cacheIP[$r.IP]
    }
}

$totalEventos = ($registros | Measure-Object Ocorrencias -Sum).Sum
$totalFalhas = [int](
    ($registros | Where-Object { $_.Resultado -eq 'Falha' } |
        Measure-Object Ocorrencias -Sum).Sum
)

Write-Host ''
Write-Host "$totalEventos acesso(s) encontrado(s) em $($registros.Count) linha(s); $totalFalhas com falha." -ForegroundColor Green
Write-Host "Eventos lidos no log: $totalLidos"
Write-Host ''


if (-not $Silencioso) {

    # ============================================================
    # Resumo por usuário
    # ============================================================

    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ' RESUMO POR USUÁRIO' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkGray

    $registros |
        Group-Object Usuario |
        ForEach-Object {

            [PSCustomObject]@{
                Usuario      = $_.Name
                Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                Falhas       = [int](
                    ($_.Group | Where-Object { $_.Resultado -eq 'Falha' } |
                        Measure-Object Ocorrencias -Sum).Sum
                )
                UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
            }
        } |
        Sort-Object Acessos -Descending |
        Format-Table -AutoSize |
        Out-Host


    # ============================================================
    # Resumo por IP
    # ============================================================

    if ($registros | Where-Object { -not [string]::IsNullOrWhiteSpace($_.IP) }) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' RESUMO POR IP' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkGray

        $registros |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.IP) } |
            Group-Object IP |
            ForEach-Object {

                [PSCustomObject]@{
                    IP           = $_.Name
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                    UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
                }
            } |
            Sort-Object Acessos -Descending |
            Format-Table -AutoSize |
            Out-Host
    }


    # ============================================================
    # Resumo por pasta
    # ============================================================

    $comPasta = $registros |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.PastaResumo) } |
        Select-Object -First 1

    if ($comPasta) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' RESUMO POR PASTA' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor DarkGray

        $registros |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.PastaResumo) } |
            Group-Object PastaResumo |
            ForEach-Object {

                [PSCustomObject]@{
                    Pasta        = $_.Name
                    Usuarios     = @($_.Group | Select-Object -ExpandProperty Usuario -Unique).Count
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                    Falhas       = [int](
                        ($_.Group | Where-Object { $_.Resultado -eq 'Falha' } |
                            Measure-Object Ocorrencias -Sum).Sum
                    )
                    UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
                }
            } |
            Sort-Object Acessos -Descending |
            Format-Table -AutoSize |
            Out-Host
    }

    # Compartilhamentos listados (-ListarCompartilhamentos) sem nenhum acesso
    if ($ListarCompartilhamentos -and $listaShares.Count -gt 0 -and $EventoId -ne 4663) {

        $semAcesso = @(
            foreach ($sh in $listaShares) {

                $teve = $registros |
                    Where-Object {
                        ($_.Servidor -ieq $sh.Servidor -or $_.Servidor -like "$($sh.Servidor).*") -and
                        (([string]$_.Compartilhamento) -replace '^.*\\', '') -ieq $sh.Nome
                    } |
                    Select-Object -First 1

                if (-not $teve) {
                    $sh
                }
            }
        )

        if ($semAcesso.Count -gt 0) {

            Write-Host ''
            Write-Host 'Compartilhamentos SEM acessos no período (considerando os filtros aplicados):' -ForegroundColor Yellow

            $semAcesso |
                Format-Table Servidor, Nome, Caminho -AutoSize |
                Out-Host
        }
    }


    # ============================================================
    # Alertas: permissões amplas e acessos não autorizados
    # ============================================================

    $liberadosAmplo = @($registros | Where-Object { $_.PermissaoAmpla -eq 'Sim' })

    if ($liberadosAmplo.Count -gt 0) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' PERMISSÕES AMPLAS DETECTADAS' -ForegroundColor Yellow
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host 'Regras de permissão amplas identificadas no evento:'

        $liberadosAmplo |
            Group-Object PastaResumo, ConcedidoPor |
            ForEach-Object {

                [PSCustomObject]@{
                    Pasta        = $_.Group[0].PastaResumo
                    ConcedidoPor = $_.Group[0].ConcedidoPor
                    Usuarios     = @($_.Group | Select-Object -ExpandProperty Usuario -Unique).Count
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                }
            } |
            Sort-Object Acessos -Descending |
            Format-Table -AutoSize -Wrap |
            Out-Host
    }

    $naoAutorizados = @($registros | Where-Object { $_.Autorizacao -eq 'NAO AUTORIZADO' })

    if ($naoAutorizados.Count -gt 0) {

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' ACESSOS NAO AUTORIZADOS (conforme -ListaAutorizados)' -ForegroundColor Red
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host 'Fora da regra de autorização. Confira o evento: êxito no 5145 não comprova leitura do conteúdo.'

        $naoAutorizados |
            Group-Object Usuario, PastaResumo, Resultado |
            ForEach-Object {

                [PSCustomObject]@{
                    Usuario      = $_.Group[0].Usuario
                    Departamento = $_.Group[0].Departamento
                    Pasta        = $_.Group[0].PastaResumo
                    Resultado    = $_.Group[0].Resultado
                    Acessos      = ($_.Group | Measure-Object Ocorrencias -Sum).Sum
                    UltimoAcesso = ($_.Group | Measure-Object DataHora -Maximum).Maximum
                }
            } |
            Sort-Object Resultado, Acessos -Descending |
            Format-Table -AutoSize -Wrap |
            Out-Host
    }


    # ============================================================
    # Detalhamento (colunas essenciais; o CSV traz todas)
    # ============================================================

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ' DETALHAMENTO' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkGray

    $colunas = @('DataHora')

    if ($Computador.Count -gt 1) {
        $colunas += 'Servidor'
    }

    $colunas += 'Usuario', 'Resultado', 'IP'

    if ($ResolverIP) {
        $colunas += 'Estacao'
    }

    $colunas += 'Acesso', 'Objeto'

    if ($regrasAutorizacao.Count -gt 0) {
        $colunas += 'Autorizacao'
    }

    if (@($registros | Where-Object { $_.PermissaoAmpla -eq 'Sim' }).Count -gt 0) {
        $colunas += 'PermissaoAmpla'
    }

    $colunas += 'Ocorrencias'

    $registros |
        Select-Object -Property $colunas |
        Format-Table -AutoSize -Wrap |
        Out-Host
}


# ============================================================
# Exportação CSV
# ============================================================

if (-not [string]::IsNullOrWhiteSpace($CsvSaida)) {

    try {

        $diretorio = Split-Path -Path $CsvSaida -Parent

        if (
            -not [string]::IsNullOrWhiteSpace($diretorio) -and
            -not (Test-Path $diretorio)
        ) {

            New-Item -Path $diretorio -ItemType Directory -Force | Out-Null
        }

        $registros |
            ForEach-Object {

                [PSCustomObject]@{
                    DataHora         = $_.DataHora.ToString('yyyy-MM-dd HH:mm:ss')
                    PrimeiroAcesso   = $_.PrimeiroAcesso.ToString('yyyy-MM-dd HH:mm:ss')
                    UltimoAcesso     = $_.UltimoAcesso.ToString('yyyy-MM-dd HH:mm:ss')
                    Servidor         = Protect-CsvCell $_.Servidor
                    RecordId         = $_.RecordId
                    Usuario          = Protect-CsvCell $_.Usuario
                    Resultado        = $_.Resultado
                    IP               = Protect-CsvCell $_.IP
                    Porta            = $_.Porta
                    Acesso           = Protect-CsvCell $_.Acesso
                    AccessList       = Protect-CsvCell $_.AccessList
                    AccessMask       = $_.AccessMask
                    Objeto           = Protect-CsvCell $_.Objeto
                    Compartilhamento = Protect-CsvCell $_.Compartilhamento
                    CaminhoRelativo  = Protect-CsvCell $_.CaminhoRelativo
                    CaminhoLocal     = Protect-CsvCell $_.CaminhoLocal
                    Processo         = Protect-CsvCell $_.Processo
                    ProcessId        = $_.ProcessId
                    HandleId         = $_.HandleId
                    LogonId          = $_.LogonId
                    EventoId         = $_.EventoId
                    Ocorrencias      = $_.Ocorrencias
                    UsuarioSid       = $_.UsuarioSid
                    TipoObjeto       = Protect-CsvCell $_.TipoObjeto
                    AccessReason     = Protect-CsvCell $_.AccessReason
                    ConcedidoPor     = Protect-CsvCell $_.ConcedidoPor
                    PermissaoAmpla   = $_.PermissaoAmpla
                    PastaResumo      = Protect-CsvCell $_.PastaResumo
                    Estacao          = Protect-CsvCell $_.Estacao
                    Departamento     = Protect-CsvCell $_.Departamento
                    Cargo            = Protect-CsvCell $_.Cargo
                    Autorizacao      = $_.Autorizacao
                }
            } |
            Export-Csv `
                -Path $CsvSaida `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Delimiter ';'

        Write-Host ''
        Write-Host '============================================================' -ForegroundColor DarkGray
        Write-Host ' EXPORTAÇÃO CONCLUÍDA' -ForegroundColor Green
        Write-Host '============================================================' -ForegroundColor DarkGray

        Write-Host "Arquivo: $CsvSaida" -ForegroundColor Green
        Write-Host "Linhas exportadas: $($registros.Count)"

    }
    catch {

        Write-Error "Falha ao exportar CSV: $($_.Exception.Message)"
    }
}


# ============================================================
# Exportação CSV consolidado (usuário x pasta)
# ============================================================

if (-not [string]::IsNullOrWhiteSpace($CsvResumo)) {

    try {

        $diretorioResumo = Split-Path -Path $CsvResumo -Parent

        if (
            -not [string]::IsNullOrWhiteSpace($diretorioResumo) -and
            -not (Test-Path $diretorioResumo)
        ) {

            New-Item -Path $diretorioResumo -ItemType Directory -Force | Out-Null
        }

        $linhasResumo = @(
            $registros |
            Group-Object Usuario, PastaResumo |
            ForEach-Object {

                $g = $_.Group

                $razoes = @(
                    $g.ConcedidoPor |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                        ForEach-Object { $_ -split '; ' } |
                        Sort-Object -Unique
                )

                if (@($g | Where-Object { $_.PermissaoAmpla -eq 'Sim' }).Count -gt 0) {
                    $ampla = 'Sim'
                }
                elseif (@($g | Where-Object { $_.PermissaoAmpla -eq 'Nao' }).Count -gt 0) {
                    $ampla = 'Nao'
                }
                else {
                    $ampla = ''
                }

                if (@($g | Where-Object { $_.Autorizacao -eq 'NAO AUTORIZADO' }).Count -gt 0) {
                    $autorizacao = 'NAO AUTORIZADO'
                }
                else {
                    $autorizacao = [string]($g | Select-Object -First 1).Autorizacao
                }

                [PSCustomObject]@{
                    Usuario        = Protect-CsvCell $g[0].Usuario
                    Departamento   = Protect-CsvCell $g[0].Departamento
                    Pasta          = Protect-CsvCell $g[0].PastaResumo
                    Acessos        = ($g | Measure-Object Ocorrencias -Sum).Sum
                    Falhas         = [int](
                        ($g | Where-Object { $_.Resultado -eq 'Falha' } |
                            Measure-Object Ocorrencias -Sum).Sum
                    )
                    PrimeiroAcesso = (($g | Measure-Object PrimeiroAcesso -Minimum).Minimum).ToString('yyyy-MM-dd HH:mm:ss')
                    UltimoAcesso   = (($g | Measure-Object UltimoAcesso -Maximum).Maximum).ToString('yyyy-MM-dd HH:mm:ss')
                    ConcedidoPor   = Protect-CsvCell ($razoes -join '; ')
                    PermissaoAmpla = $ampla
                    Autorizacao    = $autorizacao
                }
            }
        )

        $linhasResumo |
            Sort-Object { [int]$_.Acessos } -Descending |
            Export-Csv `
                -Path $CsvResumo `
                -NoTypeInformation `
                -Encoding UTF8 `
                -Delimiter ';'

        Write-Host ''
        Write-Host "Resumo usuário x pasta: $CsvResumo ($($linhasResumo.Count) linha(s))" -ForegroundColor Green
    }
    catch {

        Write-Error "Falha ao exportar o CSV de resumo: $($_.Exception.Message)"
    }
}


# ============================================================
# Avisos finais
# ============================================================

if ($servidoresSemEventos.Count -gt 0) {

    Write-Host ''
    Write-Host "Sem eventos do tipo $EventoId no período em: $($servidoresSemEventos -join ', ')" -ForegroundColor DarkYellow
}

if ($servidoresComErro.Count -gt 0) {

    Write-Host ''
    Write-Warning "Não foi possível ler o log de: $($servidoresComErro -join ', '). O relatório está incompleto."
}

if ($ignoradosRuido -gt 0) {

    Write-Host ''
    Write-Host "$ignoradosRuido evento(s) de atributos/permissões foram descartados (-IgnorarAtributos)." -ForegroundColor DarkYellow
}

if ($ignoradosEspeciais -gt 0) {

    Write-Host ''
    Write-Host "$ignoradosEspeciais evento(s) de compartilhamentos administrativos (IPC$, ADMIN$, C$...) foram descartados (use -IncluirCompartilhamentosEspeciais para incluí-los)." -ForegroundColor DarkYellow
}

if ($ignoradosExcluidos -gt 0) {

    Write-Host ''
    Write-Host "$ignoradosExcluidos evento(s) foram descartados por -ExcluirUsuarios." -ForegroundColor DarkYellow
}

if ($falhasParse -gt 0) {

    Write-Host ''
    Write-Warning "$falhasParse evento(s) não puderam ser processados e ficaram fora do relatório (use -Verbose para detalhes)."
}


# ============================================================
# Saída interativa / pipeline
# ============================================================

if ($GridView) {

    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {

        $registros |
            Out-GridView -Title 'Relatório de acessos' -Wait
    }
    else {

        Write-Warning 'Out-GridView não está disponível neste ambiente; -GridView foi ignorado.'
    }
}

if ($PassThru) {

    $registros
}
