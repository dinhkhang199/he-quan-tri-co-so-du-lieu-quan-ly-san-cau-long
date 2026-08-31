# ============================================================
# Script: build_demo_databases.ps1
# Tạo hai cơ sở dữ liệu Demo sạch và cô lập phục vụ thuyết trình:
#   1. BadmintonCourtManagement_CourseDemo (Core 00->08: 14 SPs)
#   2. BadmintonCourtManagement_ProductDemo (Core + 16: 17 SPs)
# TUYỆT ĐỐI KHÔNG DROP HAY SỬA DATABASE BadmintonCourtManagement GỐC.
# ============================================================

$Server = ".\SQLEXPRESS"

function Build-Database($targetDb, $includeExtension = $false) {
    Write-Host "`n========================================================"
    Write-Host ">>> BUILDING DATABASE: $targetDb (Extension: $includeExtension)"
    Write-Host "========================================================"

    $createSql = @"
USE master;
IF DB_ID('$targetDb') IS NOT NULL
BEGIN
    ALTER DATABASE [$targetDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$targetDb];
END;
CREATE DATABASE [$targetDb];
"@
    sqlcmd -S $Server -Q $createSql

    $scripts = @(
        "database\01_tables_constraints.sql",
        "database\02_seed.sql",
        "database\03_indexes.sql",
        "database\04_functions.sql",
        "database\05_views.sql",
        "database\06_procedures.sql",
        "database\07_triggers.sql",
        "database\08_security.sql"
    )

    if ($includeExtension) {
        $scripts += "database\16_product_extension.sql"
    }

    foreach ($file in $scripts) {
        $content = Get-Content -Path $file -Raw -Encoding UTF8
        $testContent = $content -replace '(?i)\bUSE\s+BadmintonCourtManagement\b', "USE $targetDb"
        $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sql")
        Set-Content -Path $tempFile -Value $testContent -Encoding UTF8
        try {
            sqlcmd -S $Server -f 65001 -W -i $tempFile | Out-Null
        } finally {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    $checkSql = @"
USE [$targetDb];
SET NOCOUNT ON;
SELECT 'Tables' AS ObjectType, COUNT(*) AS [Count] FROM sys.tables WHERE is_ms_shipped = 0 AND name NOT LIKE '\_%' ESCAPE '\'
UNION ALL SELECT 'Views', COUNT(*) FROM sys.views WHERE is_ms_shipped = 0
UNION ALL SELECT 'Functions', COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF') AND is_ms_shipped = 0
UNION ALL SELECT 'Stored Procedures', COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0
UNION ALL SELECT 'Triggers', COUNT(*) FROM sys.triggers WHERE is_ms_shipped = 0;
"@
    Write-Host "Object counts on ${targetDb}:"
    sqlcmd -S $Server -f 65001 -W -Q $checkSql
}

Build-Database "BadmintonCourtManagement_CourseDemo" $false
Build-Database "BadmintonCourtManagement_ProductDemo" $true

Write-Host "`n[DEMO DATABASES CREATED SAFELY]"
