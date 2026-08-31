$Server = ".\SQLEXPRESS"
$DbName = "BadmintonCourtManagement_ProductTest"

Write-Host "Tạo database $DbName..."
sqlcmd -S $Server -f 65001 -i "database\build_product_test_db.sql"

$scripts = @(
    "database\01_tables_constraints.sql",
    "database\02_seed.sql",
    "database\03_indexes.sql",
    "database\04_functions.sql",
    "database\05_views.sql",
    "database\06_procedures.sql",
    "database\07_triggers.sql",
    "database\08_security.sql",
    "database\16_product_extension.sql"
)

foreach ($s in $scripts) {
    Write-Host "Running $s on $DbName..."
    $content = Get-Content -Path $s -Raw -Encoding UTF8
    $testContent = $content -replace '(?i)\bUSE\s+BadmintonCourtManagement\b', "USE $DbName"
    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sql")
    Set-Content -Path $tempFile -Value $testContent -Encoding UTF8
    try {
        sqlcmd -S $Server -f 65001 -i $tempFile
    } finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "[OK] BadmintonCourtManagement_ProductTest ready!"
