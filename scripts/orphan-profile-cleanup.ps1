# ============================================================
# orphan-profile-cleanup.ps1
# Scans FSLogix profile share, cross-checks SIDs against
# Entra ID (Azure AD), then:
#   90+ days orphaned  → archive to cool-tier storage
#   180+ days orphaned → delete with full audit log
# ============================================================

param(
    [Parameter(Mandatory)] [string] $StorageAccount,
    [Parameter(Mandatory)] [string] $StorageKey,
    [Parameter(Mandatory)] [string] $ShareName,
    [string] $ArchiveStorageAccount = "",
    [string] $ArchiveStorageKey     = "",
    [string] $ArchiveShareName      = "fslogix-archive",
    [string] $TeamsWebhookUrl       = "",
    [int]    $ArchiveAfterDays      = 90,
    [int]    $DeleteAfterDays       = 180,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"
$auditLog = @()
$stats    = @{ Scanned = 0; Orphaned = 0; Archived = 0; Deleted = 0; Skipped = 0; Errors = 0 }

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   FSLogix Orphan Profile Cleanup"           -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Share           : \\$StorageAccount\$ShareName"
Write-Host "Archive after   : $ArchiveAfterDays days"
Write-Host "Delete after    : $DeleteAfterDays days"
if ($DryRun) { Write-Host "Mode            : DRY RUN" -ForegroundColor Yellow }

# ── Pre-generate SAS tokens (valid 8 hrs for full run) ──────
$sourceSasToken = ""
$targetSasToken = ""

if ($ArchiveStorageAccount) {
    Write-Host "`nGenerating SAS tokens..." -ForegroundColor Yellow
    $expiry = (Get-Date).AddHours(8).ToString("yyyy-MM-ddTHH:mm:ssZ")

    $sourceSasToken = az storage share generate-sas `
        --account-name $StorageAccount `
        --account-key $StorageKey `
        --name $ShareName `
        --permissions "rl" `
        --expiry $expiry `
        --output tsv

    $targetSasToken = az storage share generate-sas `
        --account-name $ArchiveStorageAccount `
        --account-key $ArchiveStorageKey `
        --name $ArchiveShareName `
        --permissions "rwdl" `
        --expiry $expiry `
        --output tsv

    Write-Host "SAS tokens ready (8-hour window)" -ForegroundColor Green
}

# ── Helper: Check SID against Entra ID (Azure AD) ───────────
# Requires User.Read.All on the service principal.
# For on-premises AD only (no Azure AD sync), use a self-hosted
# domain-joined runner and replace this with Get-ADObject.
function Test-UserExistsInEntraID {
    param([string] $Sid)
    try {
        $result = az rest --method GET `
            --url "https://graph.microsoft.com/v1.0/users" `
            --url-params "`$filter=onPremisesSecurityIdentifier eq '$Sid'&`$select=id" `
            --headers "ConsistencyLevel=eventual" `
            --query "value" `
            --output json 2>$null | ConvertFrom-Json

        return ($null -ne $result -and $result.Count -gt 0)
    } catch {
        Write-Host "  Warning: Entra ID query failed for SID $Sid — $($_.Exception.Message)" -ForegroundColor Yellow
        return $null  # null = unknown, we do not act on unknowns
    }
}

# ── Helper: Get profile last-used date from VHDX mtime ──────
function Get-ProfileLastUsed {
    param([string] $FolderName)
    try {
        $files = az storage file list `
            --account-name $StorageAccount `
            --account-key $StorageKey `
            --share-name $ShareName `
            --path $FolderName `
            --query "[?ends_with(name, '.vhd') || ends_with(name, '.vhdx')]" `
            --output json | ConvertFrom-Json

        if ($files.Count -gt 0) {
            $newest = $files | Sort-Object { [datetime]$_.properties.lastModified } -Descending | Select-Object -First 1
            return [datetime]$newest.properties.lastModified
        }

        # Fallback: use the directory's own last-modified
        $dirMeta = az storage directory show `
            --account-name $StorageAccount `
            --account-key $StorageKey `
            --share-name $ShareName `
            --name $FolderName `
            --query "properties.lastModified" `
            --output tsv
        return [datetime]$dirMeta
    } catch {
        return $null
    }
}

# ── Helper: AzCopy profile folder to archive share ──────────
function Invoke-ArchiveProfile {
    param([string] $FolderName)

    if (-not $ArchiveStorageAccount) {
        Write-Host "  Warning: ARCHIVE_STORAGE_ACCOUNT not configured — skipping archive step" -ForegroundColor Yellow
        return $false
    }

    $sourceUrl = "https://$StorageAccount.file.core.windows.net/$ShareName/$FolderName`?$sourceSasToken"
    $targetUrl = "https://$ArchiveStorageAccount.file.core.windows.net/$ArchiveShareName/$FolderName`?$targetSasToken"

    & C:\azcopy.exe copy $sourceUrl $targetUrl `
        --recursive `
        --preserve-smb-info `
        --log-level=WARNING 2>&1 | Out-Null

    return $LASTEXITCODE -eq 0
}

# ── Helper: Delete a profile folder and all its contents ────
function Remove-ProfileFolder {
    param([string] $FolderName)
    az storage remove `
        --account-name $StorageAccount `
        --account-key $StorageKey `
        --share-name $ShareName `
        --path $FolderName `
        --recursive | Out-Null
}

# ── Scan Share Root for Profile Folders ─────────────────────
Write-Host "`nScanning share root for profile folders..." -ForegroundColor Yellow

$sidPattern   = [regex]'_(S-1-5-21-\d+-\d+-\d+-\d+)$'
$profileDirs  = az storage directory list `
    --account-name $StorageAccount `
    --account-key $StorageKey `
    --share-name $ShareName `
    --output json | ConvertFrom-Json

Write-Host "Found $($profileDirs.Count) folder(s) in share root"

foreach ($dir in $profileDirs) {
    $folderName = $dir.name
    $stats.Scanned++

    # Only process folders that carry an embedded SID
    $match = $sidPattern.Match($folderName)
    if (-not $match.Success) {
        Write-Host "`n[$folderName] — no SID pattern, skipping" -ForegroundColor Gray
        $stats.Skipped++
        continue
    }

    $sid = $match.Groups[1].Value
    Write-Host "`n[$folderName]" -ForegroundColor Cyan
    Write-Host "  SID: $sid"

    # AD lookup — skip on failure to avoid false deletions
    $userExists = Test-UserExistsInEntraID -Sid $sid
    if ($null -eq $userExists) {
        Write-Host "  AD lookup indeterminate — skipping to prevent false deletion" -ForegroundColor Yellow
        $stats.Skipped++
        continue
    }
    if ($userExists) {
        Write-Host "  User active in AD — skipping" -ForegroundColor Green
        continue
    }

    Write-Host "  User NOT in AD — orphaned profile" -ForegroundColor Yellow
    $stats.Orphaned++

    # Determine age from VHDX last-modified
    $lastUsed = Get-ProfileLastUsed -FolderName $folderName
    if ($null -eq $lastUsed) {
        Write-Host "  Cannot determine last-used date — skipping" -ForegroundColor Yellow
        $stats.Skipped++
        continue
    }

    $ageDays = [math]::Floor(((Get-Date) - $lastUsed).TotalDays)
    Write-Host "  Last used : $($lastUsed.ToString('yyyy-MM-dd')) ($ageDays days ago)"

    $action = if     ($ageDays -ge $DeleteAfterDays)  { "DELETE" }
              elseif ($ageDays -ge $ArchiveAfterDays)  { "ARCHIVE" }
              else                                      { "MONITOR" }

    $actionColor = switch ($action) {
        "DELETE"  { "Red"    }
        "ARCHIVE" { "Yellow" }
        default   { "Gray"   }
    }
    Write-Host "  Action    : $action" -ForegroundColor $actionColor

    $auditEntry = [PSCustomObject]@{
        Timestamp  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        FolderName = $folderName
        SID        = $sid
        LastUsed   = $lastUsed.ToString("yyyy-MM-dd")
        AgeDays    = $ageDays
        Action     = $action
        DryRun     = $DryRun.IsPresent
        Result     = "Pending"
    }

    if ($action -eq "MONITOR") {
        $auditEntry.Result = "Monitored — below $ArchiveAfterDays-day threshold"
        $auditLog += $auditEntry
        continue
    }

    if ($DryRun) {
        $auditEntry.Result = "DRY RUN — no changes made"
        $auditLog += $auditEntry
        if ($action -eq "ARCHIVE") { $stats.Archived++ } else { $stats.Deleted++ }
        Write-Host "  [DRY RUN] Would $action this profile" -ForegroundColor Yellow
        continue
    }

    try {
        if ($action -eq "ARCHIVE") {
            Write-Host "  Copying to archive storage..." -ForegroundColor Yellow
            $ok = Invoke-ArchiveProfile -FolderName $folderName
            if ($ok) {
                Remove-ProfileFolder -FolderName $folderName
                $auditEntry.Result = "Archived to $ArchiveStorageAccount/$ArchiveShareName then removed from primary"
                $stats.Archived++
                Write-Host "  Archived successfully" -ForegroundColor Green
            } else {
                $auditEntry.Result = "Archive FAILED — primary copy retained (safe)"
                $stats.Errors++
                Write-Host "  Archive copy failed — primary retained" -ForegroundColor Red
            }
        } else {
            Write-Host "  Deleting profile..." -ForegroundColor Red
            Remove-ProfileFolder -FolderName $folderName
            $auditEntry.Result = "Deleted"
            $stats.Deleted++
            Write-Host "  Deleted" -ForegroundColor Green
        }
    } catch {
        $auditEntry.Result = "Error: $($_.Exception.Message)"
        $stats.Errors++
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    $auditLog += $auditEntry
}

# ── Write Audit CSV ──────────────────────────────────────────
$auditPath = "orphan-cleanup-audit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$auditLog | Export-Csv -Path $auditPath -NoTypeInformation -Encoding UTF8
Write-Host "`nAudit log written: $auditPath ($($auditLog.Count) entries)"

# ── Summary ──────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   Cleanup Summary"                            -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Scanned  : $($stats.Scanned)"
Write-Host "Orphaned : $($stats.Orphaned)"   -ForegroundColor $(if ($stats.Orphaned -gt 0) { "Yellow" } else { "Green" })
Write-Host "Archived : $($stats.Archived)"   -ForegroundColor $(if ($stats.Archived -gt 0) { "Yellow" } else { "Gray" })
Write-Host "Deleted  : $($stats.Deleted)"    -ForegroundColor $(if ($stats.Deleted -gt 0)  { "Red"    } else { "Gray" })
Write-Host "Skipped  : $($stats.Skipped)"
Write-Host "Errors   : $($stats.Errors)"     -ForegroundColor $(if ($stats.Errors -gt 0)   { "Red"    } else { "Green" })

# ── Teams Notification ───────────────────────────────────────
if ($TeamsWebhookUrl) {
    Write-Host "`nSending Teams notification..." -ForegroundColor Yellow

    $themeColor = if     ($stats.Errors -gt 0)                           { "FF0000" }
                  elseif ($stats.Deleted -gt 0 -or $stats.Archived -gt 0){ "FF8C00" }
                  else                                                     { "00CC00" }

    $runLabel = if ($DryRun) { " (DRY RUN)" } else { "" }

    $card = @{
        "@type"      = "MessageCard"
        "@context"   = "https://schema.org/extensions"
        "themeColor" = $themeColor
        "summary"    = "FSLogix Orphan Profile Cleanup$runLabel"
        "sections"   = @(
            @{
                "activityTitle"    = "FSLogix Orphan Profile Cleanup$runLabel"
                "activitySubtitle" = "Completed $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC"
                "facts" = @(
                    @{ name = "Profiles Scanned";        value = "$($stats.Scanned)"   }
                    @{ name = "Orphaned (no AD account)";value = "$($stats.Orphaned)"  }
                    @{ name = "Archived (>$ArchiveAfterDays days)"; value = "$($stats.Archived)" }
                    @{ name = "Deleted (>$DeleteAfterDays days)";   value = "$($stats.Deleted)"  }
                    @{ name = "Errors";                  value = "$($stats.Errors)"    }
                    @{ name = "Share";                   value = "$StorageAccount/$ShareName" }
                )
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $TeamsWebhookUrl -Method POST -Body $card -ContentType "application/json"
        Write-Host "Teams notification sent" -ForegroundColor Green
    } catch {
        Write-Host "Teams notification failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($stats.Errors -gt 0) { exit 1 }
exit 0
