<#
.SYNOPSIS
    FSLogix Orphaned Profile Cleanup
.DESCRIPTION
    Scans the FSLogix profile share for VHDX containers belonging to deleted AD users.
    - User absent from AD AND age >= ArchiveDays  : uploads VHDXes to blob (Cool tier), removes folder from share
    - User absent from AD AND age >= DeleteDays   : removes folder directly (expected already archived)
    Emits a JSON summary and POSTs a card to Teams if FslogixTeamsWebhook automation variable is set.
.NOTES
    Runs on Hybrid Worker (sh01). Requires:
    - ActiveDirectory RSAT module (installed with AD-DS feature during domain join)
    - Az.Storage PowerShell module (installed by install-az-storage-module Run Command)
    Automation Variables consumed:
    - FslogixStorageAccount  : storage account name
    - FslogixStorageKey      : storage account primary key (encrypted)
    - FslogixShareName       : file share name (e.g. "profiles")
    - FslogixArchiveContainer: blob container name for archived profiles
    - FslogixTeamsWebhook    : Teams incoming webhook URL (encrypted, optional)
#>
param(
    [int]   $ArchiveDays = 90,
    [int]   $DeleteDays  = 180,
    [switch]$DryRun
)

$StorageAccountName = Get-AutomationVariable -Name "FslogixStorageAccount"
$StorageAccountKey  = Get-AutomationVariable -Name "FslogixStorageKey"
$ShareName          = Get-AutomationVariable -Name "FslogixShareName"
$ArchiveContainer   = Get-AutomationVariable -Name "FslogixArchiveContainer"
$TeamsWebhookUrl    = Get-AutomationVariable -Name "FslogixTeamsWebhook"
$SharePath          = "\\$StorageAccountName.file.core.windows.net\$ShareName"

$result = @{
    StartTime   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    DryRun      = $DryRun.IsPresent
    ArchiveDays = $ArchiveDays
    DeleteDays  = $DeleteDays
    Archived    = @()
    Deleted     = @()
    Skipped     = @()
    Errors      = @()
    Status      = "Running"
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module Az.Storage      -ErrorAction Stop
    Write-Output "Modules loaded"

    $ctx   = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    $now   = Get-Date
    $sidRx = [regex]'(S-1-5-21-\d+-\d+-\d+-\d+)'

    if (-not (Test-Path $SharePath)) { throw "Cannot access share: $SharePath" }

    $folders = @(Get-ChildItem -Path $SharePath -Directory -ErrorAction SilentlyContinue)
    Write-Output "Found $($folders.Count) profile folder(s) on share"

    foreach ($folder in $folders) {
        $entry = @{ Folder = $folder.Name }

        try {
            # FSLogix folder name (FlipFlopProfileDirectoryName=1): <SID>_<username>
            $sidMatch = $sidRx.Match($folder.Name)
            if (-not $sidMatch.Success) {
                $entry.Status = "Skipped-NoSID"
                $result.Skipped += $entry
                continue
            }

            $sid       = $sidMatch.Value
            $entry.SID = $sid

            # Check AD — Get-ADUser accepts SID objects directly
            $adUser = $null
            try {
                $sidObject = [System.Security.Principal.SecurityIdentifier]$sid
                $adUser    = Get-ADUser -Identity $sidObject -ErrorAction Stop
            } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
                $adUser = $null
            } catch {
                Write-Warning "AD lookup failed for ${sid}: $_"
                $adUser = $null
            }

            if ($adUser) {
                $entry.Status = "Skipped-UserActive"
                $entry.ADUser = $adUser.SamAccountName
                $result.Skipped += $entry
                Write-Output "SKIP (active user $($adUser.SamAccountName)): $($folder.Name)"
                continue
            }

            # Use most-recent LastWriteTime across folder + any VHDX inside as the activity timestamp
            $lastActivity = $folder.LastWriteTime
            $vhdxFiles = @(Get-ChildItem -Path $folder.FullName -Recurse -Filter "*.vhdx" -ErrorAction SilentlyContinue)
            foreach ($v in $vhdxFiles) {
                if ($v.LastWriteTime -gt $lastActivity) { $lastActivity = $v.LastWriteTime }
            }

            $ageInDays          = ($now - $lastActivity).TotalDays
            $entry.AgeInDays    = [math]::Round($ageInDays, 1)
            $entry.LastActivity = $lastActivity.ToString("yyyy-MM-dd")

            if ($ageInDays -ge $DeleteDays) {
                if (-not $DryRun) {
                    Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                }
                $entry.Status = "Deleted"
                $result.Deleted += $entry
                Write-Output "DELETED ($([math]::Round($ageInDays,0))d old): $($folder.Name)"

            } elseif ($ageInDays -ge $ArchiveDays) {
                $blobs = @()

                foreach ($vhdx in $vhdxFiles) {
                    $blobName = "$($folder.Name)/$($vhdx.Name)"
                    if (-not $DryRun) {
                        Set-AzStorageBlobContent `
                            -Context          $ctx `
                            -Container        $ArchiveContainer `
                            -File             $vhdx.FullName `
                            -Blob             $blobName `
                            -BlobType         Block `
                            -StandardBlobTier Cool `
                            -Force            -ErrorAction Stop
                    }
                    $blobs += $blobName
                    Write-Output "UPLOADED to blob (Cool): $blobName"
                }

                if (-not $DryRun) {
                    Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                }
                $entry.Status        = "Archived"
                $entry.ArchivedBlobs = $blobs
                $result.Archived    += $entry
                Write-Output "ARCHIVED ($([math]::Round($ageInDays,0))d, $($blobs.Count) VHDX): $($folder.Name)"

            } else {
                $entry.Status = "Skipped-TooNew"
                $result.Skipped += $entry
                Write-Output "SKIP ($([math]::Round($ageInDays,0))d old, under threshold): $($folder.Name)"
            }
        } catch {
            $entry.Status = "Error"
            $entry.Reason = "$_"
            $result.Errors += $entry
            Write-Error "Error processing $($folder.Name): $_"
        }
    }

    $result.Status  = "Completed"
    $result.EndTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

} catch {
    $result.Status = "Failed"
    $result.Errors += "$_"
    Write-Error $_
}

$json = $result | ConvertTo-Json -Depth 5
Write-Output $json

if ($TeamsWebhookUrl) {
    $color   = if ($result.Errors.Count -gt 0) { "FF0000" } else { "00C853" }
    $summary = "FSLogix Orphan Cleanup | Archived: $($result.Archived.Count) | Deleted: $($result.Deleted.Count) | Errors: $($result.Errors.Count) | DryRun: $($result.DryRun)"
    $card    = @{
        "@type"    = "MessageCard"
        "@context" = "http://schema.org/extensions"
        themeColor = $color
        summary    = $summary
        title      = "FSLogix Orphaned Profile Cleanup — $($result.Status)"
        text       = $summary
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body $card -ContentType "application/json" -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Teams notification failed: $_"
    }
}
