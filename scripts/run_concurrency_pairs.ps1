# ============================================================
# Script: run_concurrency_pairs.ps1
# Chạy các kịch bản concurrency song song (A + B) trên BadmintonCourtManagement_ProductTest
# ============================================================

$Server = ".\SQLEXPRESS"
$DbName = "BadmintonCourtManagement_ProductTest"
$Root = (Get-Item -Path ".\").FullName

function Run-ConcurrencyPair($fileA, $fileB, $delayMs = 800) {
    Write-Host "
========================================================"
    Write-Host ">>> RUNNING CONCURRENT PAIR: $fileA & $fileB"
    Write-Host "========================================================"

    $jobA = Start-Job -ScriptBlock {
        param($srv, $db, $path)
        $content = Get-Content -Path $path -Raw -Encoding UTF8
        $testContent = $content -replace '(?i)\bUSE\s+BadmintonCourtManagement\b', "USE $db"
        $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sql")
        Set-Content -Path $tempFile -Value $testContent -Encoding UTF8
        try { sqlcmd -S $srv -f 65001 -W -i $tempFile } finally { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
    } -ArgumentList $Server, $DbName, (Join-Path $Root $fileA)

    Start-Sleep -Milliseconds $delayMs

    $jobB = Start-Job -ScriptBlock {
        param($srv, $db, $path)
        $content = Get-Content -Path $path -Raw -Encoding UTF8
        $testContent = $content -replace '(?i)\bUSE\s+BadmintonCourtManagement\b', "USE $db"
        $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sql")
        Set-Content -Path $tempFile -Value $testContent -Encoding UTF8
        try { sqlcmd -S $srv -f 65001 -W -i $tempFile } finally { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
    } -ArgumentList $Server, $DbName, (Join-Path $Root $fileB)

    $resA = Receive-Job -Job $jobA -Wait
    $resB = Receive-Job -Job $jobB -Wait
    Remove-Job -Job $jobA, $jobB

    Write-Host "[Session A Result]:"
    Write-Host ($resA | Out-String).Trim()
    Write-Host "[Session B Result]:"
    Write-Host ($resB | Out-String).Trim()
}

Run-ConcurrencyPair "database\11_tests_concurrency_session_A.sql" "database\12_tests_concurrency_session_B.sql" 600
Run-ConcurrencyPair "database\13_deadlock_demo_session_A.sql" "database\14_deadlock_demo_session_B.sql" 800
Run-ConcurrencyPair "tests\concurrency\lost_update_session_A.sql" "tests\concurrency\lost_update_session_B.sql" 800
Run-ConcurrencyPair "tests\concurrency\dirty_read_session_A.sql" "tests\concurrency\dirty_read_session_B.sql" 800
Run-ConcurrencyPair "tests\concurrency\nonrepeatable_session_A.sql" "tests\concurrency\nonrepeatable_session_B.sql" 800
Run-ConcurrencyPair "tests\concurrency\phantom_session_A.sql" "tests\concurrency\phantom_session_B.sql" 800
Run-ConcurrencyPair "tests\concurrency\register_email_session_A.sql" "tests\concurrency\register_email_session_B.sql" 400

Write-Host "
========================================================"
Write-Host ">>> ALL CONCURRENCY PAIRS COMPLETED!"
Write-Host "========================================================"

Write-Host "
>>> CLEANING UP ALL HELPER SYNC TABLES..."
$cleanupSql = @"
USE [$DbName];
DROP TABLE IF EXISTS dbo._CCTestSync;
DROP TABLE IF EXISTS dbo._DLTestSync;
DROP TABLE IF EXISTS dbo._LUTestSync;
DROP TABLE IF EXISTS dbo._DRTestSync;
DROP TABLE IF EXISTS dbo._NRTestSync;
DROP TABLE IF EXISTS dbo._PhTestSync;
"@
sqlcmd -S $Server -Q $cleanupSql

Write-Host "
>>> POST-CONCURRENCY OBJECT COUNTS:"
$checkSql = @"
USE [$DbName];
SET NOCOUNT ON;
SELECT 'Tables' AS ObjectType, COUNT(*) AS [Count] FROM sys.tables WHERE is_ms_shipped = 0
UNION ALL SELECT 'Views', COUNT(*) FROM sys.views WHERE is_ms_shipped = 0
UNION ALL SELECT 'Functions', COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF') AND is_ms_shipped = 0
UNION ALL SELECT 'Stored Procedures', COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0
UNION ALL SELECT 'Triggers', COUNT(*) FROM sys.triggers WHERE is_ms_shipped = 0;
"@
sqlcmd -S $Server -f 65001 -W -Q $checkSql
