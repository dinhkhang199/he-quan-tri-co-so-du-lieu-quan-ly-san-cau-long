# ============================================================
# Script: verify_concurrency_anomalies.ps1
# Mục đích: Chạy kiểm thử tự động các kịch bản concurrency & deadlock
#           trên database cô lập BadmintonCourtManagement_ProductTest
# ============================================================

$Server = ".\SQLEXPRESS"
$DbName = "BadmintonCourtManagement_ProductTest"

function Run-ScriptDirect($filePath) {
    $content = Get-Content -Path $filePath -Raw -Encoding UTF8
    $testContent = $content -replace '(?i)\bUSE\s+BadmintonCourtManagement\b', "USE $DbName"
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sql")
    Set-Content -Path $tempFile -Value $testContent -Encoding UTF8
    try {
        sqlcmd -S $Server -f 65001 -W -i $tempFile
    } finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ">>> 1. 10_tests_transactions.sql (Phantom Isolation Demo)..."
Run-ScriptDirect "database\10_tests_transactions.sql"

Write-Host "
>>> 2. Concurrency CC-01 (11 & 12 concurrent approve serialization)..."
$jobA = Start-Job -ScriptBlock {
    param($srv, $db)
    $content = Get-Content -Path "database\11_tests_concurrency_session_A.sql" -Raw -Encoding UTF8
    $testContent = $content -replace '(?i)\bUSE\s+BadmintonCourtManagement\b', "USE $db"
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sql")
    Set-Content -Path $tempFile -Value $testContent -Encoding UTF8
    try { sqlcmd -S $srv -f 65001 -W -i $tempFile } finally { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
} -ArgumentList $Server, $DbName

Start-Sleep -Milliseconds 600

$jobB = Start-Job -ScriptBlock {
    param($srv, $db)
    $content = Get-Content -Path "database\12_tests_concurrency_session_B.sql" -Raw -Encoding UTF8
    $testContent = $content -replace '(?i)\bUSE\s+BadmintonCourtManagement\b', "USE $db"
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sql")
    Set-Content -Path $tempFile -Value $testContent -Encoding UTF8
    try { sqlcmd -S $srv -f 65001 -W -i $tempFile } finally { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
} -ArgumentList $Server, $DbName

$resA = Receive-Job -Job $jobA -Wait
$resB = Receive-Job -Job $jobB -Wait
Remove-Job -Job $jobA, $jobB

Write-Host "Job A Output summary:" ($resA | Out-String).Trim()
Write-Host "Job B Output summary:" ($resB | Out-String).Trim()

Write-Host "
[OK] Concurrency & transaction scripts verified on $DbName!"
