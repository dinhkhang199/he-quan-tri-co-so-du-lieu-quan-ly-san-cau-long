[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppPassword,

    [string]$Server = '.\SQLEXPRESS'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$EvidenceDir = Join-Path $RepoRoot 'evidence\patched'
$AppDir = Join-Path $RepoRoot 'app'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null

$SqlCmdCommand = Get-Command sqlcmd -ErrorAction SilentlyContinue
if ($SqlCmdCommand) {
    $SqlCmd = $SqlCmdCommand.Source
}
elseif (Test-Path -LiteralPath 'C:\Program Files\SqlCmd\sqlcmd.exe' -PathType Leaf) {
    $SqlCmd = 'C:\Program Files\SqlCmd\sqlcmd.exe'
}
else {
    throw 'sqlcmd was not found in PATH or C:\Program Files\SqlCmd\sqlcmd.exe.'
}
$Npm = (Get-Command npm -ErrorAction Stop).Source
$Python = (Get-Command python -ErrorAction Stop).Source
$Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Step, [string]$Status, [string]$Log, [string]$Note = '')
    $script:Results.Add([pscustomobject]@{
        Step = $Step
        Status = $Status
        Log = $Log
        Note = $Note
    })
}

function Invoke-LoggedProcess {
    param(
        [string]$Step,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $safeStep = $Step -replace '[^A-Za-z0-9_-]', '_'
    $logPath = Join-Path $EvidenceDir ("$Timestamp-$safeStep.txt")
    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $logPath
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($exitCode -eq 0) {
        Add-Result $Step 'PASS' $logPath
        return
    }
    Add-Result $Step 'FAIL' $logPath "exit=$exitCode"
    throw "$Step failed with exit code $exitCode. See $logPath"
}

function Start-SqlPair {
    param([string]$Name, [string]$SessionA, [string]$SessionB)

    $aLog = Join-Path $EvidenceDir ("$Timestamp-$Name-A.txt")
    $bLog = Join-Path $EvidenceDir ("$Timestamp-$Name-B.txt")
    $aErr = Join-Path $EvidenceDir ("$Timestamp-$Name-A.err.txt")
    $bErr = Join-Path $EvidenceDir ("$Timestamp-$Name-B.err.txt")

    $sqlJob = {
        param($Executable, $TargetServer, $InputFile, $StdOut, $StdErr)
        & $Executable -S $TargetServer -E -C -b -i $InputFile 1> $StdOut 2> $StdErr
        if ($null -eq $LASTEXITCODE) { return 9999 }
        return [int]$LASTEXITCODE
    }

    $a = Start-Job -ScriptBlock $sqlJob -ArgumentList $SqlCmd, $Server, $SessionA, $aLog, $aErr
    Start-Sleep -Seconds 3
    $b = Start-Job -ScriptBlock $sqlJob -ArgumentList $SqlCmd, $Server, $SessionB, $bLog, $bErr

    Wait-Job -Job @($a, $b) | Out-Null
    $aExitCode = [int](Receive-Job -Job $a | Select-Object -Last 1)
    $bExitCode = [int](Receive-Job -Job $b | Select-Object -Last 1)
    Remove-Job -Job @($a, $b) -Force
    $failedMarker = Select-String -Path @($aLog, $bLog, $aErr, $bErr) `
        -Pattern 'ASSERTION FAIL|>>> FAIL|TIMEOUT chờ cờ' -Quiet

    if ($aExitCode -eq 0 -and $bExitCode -eq 0 -and -not $failedMarker) {
        Add-Result "$Name-A" 'PASS' $aLog
        Add-Result "$Name-B" 'PASS' $bLog
        return
    }
    Add-Result "$Name-A" 'FAIL' $aLog "exit=$aExitCode"
    Add-Result "$Name-B" 'FAIL' $bLog "exit=$bExitCode; marker=$failedMarker"
    throw "Concurrency pair $Name failed; see $aLog and $bLog"
}

try {
    $buildScripts = Get-ChildItem (Join-Path $RepoRoot 'database') -File |
        Where-Object { $_.Name -match '^0[0-8]_.*\.sql$' } |
        Sort-Object Name
    if ($buildScripts.Count -ne 9) {
        throw "Expected database scripts 00..08, found $($buildScripts.Count)."
    }

    foreach ($script in $buildScripts) {
        $args = @('-S', $Server, '-E', '-C', '-b', '-i', $script.FullName)
        if ($script.Name -eq '08_security.sql') {
            $args += @('-v', "BCM_APP_PASSWORD=$AppPassword")
        }
        Invoke-LoggedProcess "db-$($script.BaseName)" $SqlCmd $args $RepoRoot
    }

    Invoke-LoggedProcess 'db-functional-09' $SqlCmd `
        @('-S', $Server, '-E', '-C', '-b', '-i', (Join-Path $RepoRoot 'database\09_tests_functional.sql')) $RepoRoot

    Start-SqlPair 'transactions-10' `
        (Join-Path $RepoRoot 'database\10_tests_transactions.sql') `
        (Join-Path $RepoRoot 'tests\concurrency\transactions10_session_B.sql')

    Invoke-LoggedProcess 'db-regression' $SqlCmd `
        @('-S', $Server, '-E', '-C', '-b', '-i', (Join-Path $RepoRoot 'tests\regression\imp_regression.sql')) $RepoRoot

    Invoke-LoggedProcess 'db-auth-features' $SqlCmd `
        @('-S', $Server, '-E', '-C', '-b', '-i', (Join-Path $RepoRoot 'tests\regression\auth_features.sql')) $RepoRoot

    $pairs = @(
        @('lost-update', 'lost_update_session_A.sql', 'lost_update_session_B.sql'),
        @('dirty-read', 'dirty_read_session_A.sql', 'dirty_read_session_B.sql'),
        @('nonrepeatable', 'nonrepeatable_session_A.sql', 'nonrepeatable_session_B.sql'),
        @('phantom', 'phantom_session_A.sql', 'phantom_session_B.sql'),
        @('toctou', 'toctou_booking_vs_deactivate_session_A.sql', 'toctou_booking_vs_deactivate_session_B.sql')
    )
    foreach ($pair in $pairs) {
        $a = Join-Path $RepoRoot "tests\concurrency\$($pair[1])"
        $b = Join-Path $RepoRoot "tests\concurrency\$($pair[2])"
        Start-SqlPair $pair[0] $a $b
    }

    Invoke-LoggedProcess 'db-backup-restore-15' $SqlCmd `
        @('-S', $Server, '-E', '-C', '-b', '-i', (Join-Path $RepoRoot 'database\15_backup_restore_demo.sql')) $RepoRoot

    Invoke-LoggedProcess 'app-install' $Npm @('install') $AppDir
    Invoke-LoggedProcess 'app-lint' $Npm @('run', 'lint') $AppDir
    Invoke-LoggedProcess 'app-typecheck' $Npm @('run', 'typecheck') $AppDir
    Invoke-LoggedProcess 'app-test' $Npm @('test') $AppDir
    Invoke-LoggedProcess 'app-build' $Npm @('run', 'build') $AppDir
    Invoke-LoggedProcess 'static-checks' $Python @('tests/static/check_static.py') $RepoRoot

    $serverEntry = Join-Path $AppDir 'dist\server\index.js'
    if (Test-Path -LiteralPath $serverEntry -PathType Leaf) {
        Add-Result 'dist-server-index' 'PASS' $serverEntry 'compiled entry exists'
    }
    else {
        Add-Result 'dist-server-index' 'FAIL' $serverEntry 'compiled entry missing'
        throw "Missing compiled server entry: $serverEntry"
    }
}
catch {
    Add-Result 'runner' 'FAIL' '' $_.Exception.Message
    throw
}
finally {
    $summary = Join-Path $EvidenceDir 'SUMMARY.csv'
    $Results | Export-Csv -LiteralPath $summary -NoTypeInformation -Encoding utf8
    Write-Host "Evidence summary: $summary"
}
