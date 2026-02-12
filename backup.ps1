
$Equipamento = (Get-CimInstance -ClassName Win32_ComputerSystem).Name
$BackupDestino = "\\10.0.0.132\Backup\Backups\$Equipamento\$(Get-Date -Format yyyy-MM-dd_HH-mm)"
$PerfisExcluirPorNome = @('Default','Default User','Public','All Users','WDAGUtilityAccount','imaflora','defaultuser0','DWM-1')

Write-Host "Destino do backup: $BackupDestino" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $BackupDestino -Force | Out-Null
$LogPath = Join-Path $BackupDestino 'backup.log'

function Get-RoboCopyMeaning {
    param([int]$Code)
    switch ($Code) {
        0 { 'Sem cópias; nada a fazer' }
        1 { 'Arquivos idênticos ou copiados com sucesso' }
        2 { 'Alguns arquivos extras/removidos' }
        3 { 'Cópias e remoções bem-sucedidas' }
        5 { 'Alguns arquivos ignorados/novos' }
        6 { 'Novos arquivos e removidos' }
        default { 'Verifique detalhes no log' }
    }
}

$chavePerfis = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$perfis = Get-ChildItem $chavePerfis | ForEach-Object { try { Get-ItemProperty $_.PSPath } catch { $null } } | Where-Object { $_ -and $_.ProfileImagePath }

$usuarios = foreach ($p in $perfis) {
    $caminhoPerfil = [Environment]::ExpandEnvironmentVariables($p.ProfileImagePath)
    if ($caminhoPerfil -like "*\systemprofile*" -or $caminhoPerfil -like "*\ServiceProfiles\*" -or $caminhoPerfil -like "*\LocalService*" -or $caminhoPerfil -like "*\NetworkService*") { continue }
    if ($caminhoPerfil -notmatch "\\Users\\") { continue }
    if (-not (Test-Path $caminhoPerfil)) { continue }
    $nomePerfil = Split-Path -Leaf $caminhoPerfil
    if ( ($PerfisExcluirPorNome | ForEach-Object { $_.ToLower() }) -contains $nomePerfil.ToLower() ) { continue }
    [PSCustomObject]@{ Nome = $nomePerfil; Caminho = $caminhoPerfil }
}

$usuarios = @($usuarios)
if (-not $usuarios -or $usuarios.Count -eq 0) {
    Write-Warning "`nNenhum usuário elegível para backup."
    return
}

Write-Host "`nUsuários que terão backup executado:" -ForegroundColor Yellow
$usuarios | Format-Table Nome, Caminho -AutoSize
if (-not $usuarios -or $usuarios.Count -eq 0) { Write-Warning "`nNenhum usuário elegível para backup."; return }

Write-Host "`nPressione ENTER para iniciar o backup, ou CTRL+C para cancelar..."
[void][System.Console]::ReadLine()

$robocopyPath = "$env:SystemRoot\System32\robocopy.exe"
$temRobocopy = Test-Path $robocopyPath
$relogioGeral = [System.Diagnostics.Stopwatch]::StartNew()

for ($ui = 0; $ui -lt $usuarios.Count; $ui++) {
    $u = $usuarios[$ui]
    $percentUsuarios = [math]::Round((($ui+1) / $usuarios.Count) * 100, 2)
    Write-Progress -Id 1 -Activity "Backup de usuários" -Status "Processando: $($u.Nome) ($($ui+1)/$($usuarios.Count))" -PercentComplete $percentUsuarios

    $srcRoot = $u.Caminho
    $dstRoot = Join-Path $BackupDestino $u.Nome
    New-Item -ItemType Directory -Path $dstRoot -Force | Out-Null

    "`n===== Backup do usuário: $($u.Nome) | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') =====" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host (">>> Iniciando usuário: {0}" -f $u.Nome) -ForegroundColor Cyan
    $inicioUsuario = Get-Date

    $pastas = Get-ChildItem -LiteralPath $srcRoot -Directory -Force 2>$null | Where-Object {
        ($_.Name -notlike "OneDrive*") -and
        ($_.Name -notlike "IMAFLORA*") -and
        ($_.Name -notmatch '^\.') -and
        -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and
        -not ($_.Attributes -band [IO.FileAttributes]::System)
    }

    $pastas = @($pastas)
    $pastasCount = $pastas.Count
    for ($pi = 0; $pi -lt $pastasCount; $pi++) {
        $pasta = $pastas[$pi]
        $percentPastas = if ($pastasCount -gt 0) { [math]::Round((($pi+1) / $pastasCount) * 100, 2) } else { 100 }
        Write-Progress -Id 2 -ParentId 1 -Activity "Pastas do usuário: $($u.Nome)" -Status "Copiando: $($pasta.Name) ($($pi+1)/$pastasCount)" -PercentComplete $percentPastas

        $dest = Join-Path $dstRoot $pasta.Name
        New-Item -ItemType Directory -Path $dest -Force | Out-Null

        if ($temRobocopy) {
            & $robocopyPath "$($pasta.FullName)" "$dest" /E /COPY:DAT /R:2 /W:3 /NFL /NDL /NP /TEE /LOG+:"$LogPath" | Out-Null
            $exitCode = $LASTEXITCODE
            $meaning = Get-RoboCopyMeaning -Code $exitCode
            # Write-Host (" [{0}%] {1} -> {2} | RC={3} ({4})" -f $percentPastas, $pasta.Name, $dest, $exitCode, $meaning)
            Write-Host (" [{0}%] {1} -> {2}" -f $percentPastas, $pasta.Name, $dest, $exitCode, $meaning)
            "[RC=$exitCode] $($pasta.FullName) -> $dest | $meaning" | Out-File -FilePath $LogPath -Append -Encoding UTF8
        } else {
            try {
                Copy-Item -LiteralPath $pasta.FullName -Destination $dest -Recurse -Force -ErrorAction Stop
                Write-Host (" [{0}%] {1} -> {2} (Copy-Item OK)" -f $percentPastas, $pasta.Name, $dest)
                ('[Copy-Item] {0} -> {1}' -f $pasta.FullName, $dest) | Out-File -FilePath $LogPath -Append -Encoding UTF8
            } catch {
                ('[ERRO] Falha ao copiar {0}: {1}' -f $pasta.FullName, $_.Exception.Message) | Out-File -FilePath $LogPath -Append -Encoding UTF8
                Write-Warning (" Falha ao copiar: {0} | {1}" -f $pasta.FullName, $_.Exception.Message)
            }
        }
    }

    $fimUsuario = Get-Date
    $duracao = New-TimeSpan -Start $inicioUsuario -End $fimUsuario
    Write-Host ("<<< Finalizado usuário: {0} | Duração: {1:hh\:mm\:ss}" -f $u.Nome, $duracao) -ForegroundColor Green
    "Finalizado $($u.Nome) | Duração: $($duracao.ToString())" | Out-File -FilePath $LogPath -Append -Encoding UTF8

    Write-Progress -Id 2 -Activity "Pastas do usuário" -Completed
}

Write-Progress -Id 1 -Activity "Backup de usuários" -Completed
$relogioGeral.Stop()
Write-Host ("`nBackup concluído. Tempo total: {0:hh\:mm\:ss}" -f $relogioGeral.Elapsed) -ForegroundColor Green
Write-Host "Log: $LogPath"
