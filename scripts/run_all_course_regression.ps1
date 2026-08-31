# ============================================================
# Script: run_all_course_regression.ps1
# Mục đích: Chạy toàn bộ regression test suite môn học trên BadmintonCourtManagement_ProductTest
# ============================================================

$Server = ".\SQLEXPRESS"
$DbName = "BadmintonCourtManagement_ProductTest"

function Run-ScriptOnTestDb($filePath, $title) {
    Write-Host "
========================================================"
    Write-Host ">>> RUNNING: $title ($filePath)"
    Write-Host "========================================================"
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

Run-ScriptOnTestDb "database\09_tests_functional.sql" "09 Functional Tests (47/47)"
Run-ScriptOnTestDb "tests\regression\audit_actor.sql" "Audit Actor Regression"
Run-ScriptOnTestDb "tests\regression\auth_features.sql" "Product Auth Extension Suite (16/16)"

Write-Host "
[ALL RUNS COMPLETE]"
