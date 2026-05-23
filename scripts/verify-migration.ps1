# ============================================================
# verify-migration.ps1
# Verifies FSLogix profile data migrated correctly
# Checks: file count, VHD presence, size comparison
# ============================================================

param(
    [Parameter(Mandatory)] [string] $SourceStorageAccount,
    [Parameter(Mandatory)] [string] $SourceStorageKey,
    [Parameter(Mandatory)] [string] $SourceShareName,
    [Parameter(Mandatory)] [string] $TargetStorageAccount,
    [Parameter(Mandatory)] [string] $TargetStorageKey,
    [Parameter(Mandatory)] [string] $TargetShareName
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   FSLogix Migration Verification Report"    -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$passCount = 0
$failCount = 0
$results   = @()

function Write-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    $status = if ($Passed) { "PASS ✅" } else { "FAIL ❌" }
    $color  = if ($Passed) { "Green" } else { "Red" }
    Write-Host "[$status] $Name" -ForegroundColor $color
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor Gray }
    $script:results += [PSCustomObject]@{
        Check  = $Name
        Status = $status
        Detail = $Detail
    }
    if ($Passed) { $script:passCount++ } else { $script:failCount++ }
}

# ── Check 1: Source share accessible ────────────────────────
Write-Host "`n--- Connectivity Checks ---" -ForegroundColor Yellow
try {
    $sourceCheck = az storage share exists `
        --account-name $SourceStorageAccount `
        --account-key $SourceStorageKey `
        --name $SourceShareName `
        --query "exists" --output tsv
    Write-Check "Source share accessible" ($sourceCheck -eq "true") "Share: $SourceShareName"
} catch {
    Write-Check "Source share accessible" $false $_.Exception.Message
}

# ── Check 2: Target share accessible ────────────────────────
try {
    $targetCheck = az storage share exists `
        --account-name $TargetStorageAccount `
        --account-key $TargetStorageKey `
        --name $TargetShareName `
        --query "exists" --output tsv
    Write-Check "Target share accessible" ($targetCheck -eq "true") "Share: $TargetShareName"
} catch {
    Write-Check "Target share accessible" $false $_.Exception.Message
}

# ── Check 3: File count comparison ──────────────────────────
Write-Host "`n--- File Count Checks ---" -ForegroundColor Yellow
try {
    $sourceCount = (az storage file list `
        --account-name $SourceStorageAccount `
        --account-key $SourceStorageKey `
        --share-name $SourceShareName `
        --recursive `
        --output json | ConvertFrom-Json).Count

    $targetCount = (az storage file list `
        --account-name $TargetStorageAccount `
        --account-key $TargetStorageKey `
        --share-name $TargetShareName `
        --recursive `
        --output json | ConvertFrom-Json).Count

    $countMatch = $sourceCount -eq $targetCount
    Write-Check "File count matches" $countMatch "Source: $sourceCount | Target: $targetCount"
} catch {
    Write-Check "File count matches" $false $_.Exception.Message
}

# ── Check 4: VHD/VHDX files present ─────────────────────────
Write-Host "`n--- FSLogix VHD Checks ---" -ForegroundColor Yellow
try {
    $vhdFiles = az storage file list `
        --account-name $TargetStorageAccount `
        --account-key $TargetStorageKey `
        --share-name $TargetShareName `
        --recursive `
        --query "[?ends_with(name, '.vhd') || ends_with(name, '.vhdx')]" `
        --output json | ConvertFrom-Json

    $hasVhd = $vhdFiles.Count -gt 0
    Write-Check "VHD/VHDX files migrated" $hasVhd "Found $($vhdFiles.Count) VHD files"

    # List VHD files found
    if ($hasVhd) {
        Write-Host "         VHD files found:" -ForegroundColor Gray
        $vhdFiles | ForEach-Object {
            Write-Host "           - $($_.name) ($([math]::Round($_.properties.contentLength/1GB, 2)) GB)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Check "VHD/VHDX files migrated" $false $_.Exception.Message
}

# ── Check 5: Total size comparison ──────────────────────────
Write-Host "`n--- Size Checks ---" -ForegroundColor Yellow
try {
    $sourceStats = az storage share stats `
        --account-name $SourceStorageAccount `
        --account-key $SourceStorageKey `
        --name $SourceShareName `
        --query "shareUsageBytes" --output tsv

    $targetStats = az storage share stats `
        --account-name $TargetStorageAccount `
        --account-key $TargetStorageKey `
        --name $TargetShareName `
        --query "shareUsageBytes" --output tsv

    $sourceGB = [math]::Round([long]$sourceStats / 1GB, 2)
    $targetGB = [math]::Round([long]$targetStats / 1GB, 2)

    # Allow 1% tolerance for metadata differences
    $tolerance  = [long]$sourceStats * 0.01
    $sizeMatch  = [math]::Abs([long]$sourceStats - [long]$targetStats) -le $tolerance
    Write-Check "Total size matches (±1%)" $sizeMatch "Source: $sourceGB GB | Target: $targetGB GB"
} catch {
    Write-Check "Total size matches" $false $_.Exception.Message
}

# ── Check 6: User profile folders ───────────────────────────
Write-Host "`n--- Profile Folder Checks ---" -ForegroundColor Yellow
try {
    $sourceFolders = az storage directory list `
        --account-name $SourceStorageAccount `
        --account-key $SourceStorageKey `
        --share-name $SourceShareName `
        --query "length(@)" --output tsv

    $targetFolders = az storage directory list `
        --account-name $TargetStorageAccount `
        --account-key $TargetStorageKey `
        --share-name $TargetShareName `
        --query "length(@)" --output tsv

    $foldersMatch = $sourceFolders -eq $targetFolders
    Write-Check "User profile folders match" $foldersMatch "Source: $sourceFolders | Target: $targetFolders"
} catch {
    Write-Check "User profile folders" $false $_.Exception.Message
}

# ── Summary ──────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   Verification Summary"                       -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Total checks : $($passCount + $failCount)"
Write-Host "Passed       : $passCount" -ForegroundColor Green
Write-Host "Failed       : $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

$results | Format-Table -AutoSize

if ($failCount -gt 0) {
    Write-Host "`n❌ Verification FAILED — do NOT update FSLogix path" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n✅ Verification PASSED — safe to update FSLogix path" -ForegroundColor Green
    exit 0
}
