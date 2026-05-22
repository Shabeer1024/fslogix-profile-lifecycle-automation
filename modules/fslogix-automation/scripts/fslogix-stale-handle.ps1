<#
.SYNOPSIS
    FSLogix Stale SMB Handle Cleanup
.DESCRIPTION
    Lists open handles on the FSLogix Azure Files share. Closes handles held longer than
    MaxHandleAgeHours that have no corresponding active RDS session on this session host.
    Notifies Teams only when handles are actually closed or errors occur.
.NOTES
    Runs on Hybrid Worker (sh01). Requires:
    - Az.Storage PowerShell module (installed by install-az-storage-module Run Command)
    Automation Variables consumed:
    - FslogixStorageAccount : storage account name
    - FslogixStorageKey     : storage account primary key (encrypted)
    - FslogixShareName      : file share name (e.g. "profiles")
    - FslogixTeamsWebhook   : Teams incoming webhook URL (encrypted, optional)
#>
param(
    [int]$MaxHandleAgeHours = 2
)

$StorageAccountName = Get-AutomationVariable -Name "FslogixStorageAccount"
$StorageAccountKey  = Get-AutomationVariable -Name "FslogixStorageKey"
$ShareName          = Get-AutomationVariable -Name "FslogixShareName"
$TeamsWebhookUrl    = Get-AutomationVariable -Name "FslogixTeamsWebhook"

$result = @{
    StartTime         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    MaxHandleAgeHours = $MaxHandleAgeHours
    TotalHandles      = 0
    ClosedHandles     = @()
    SkippedHandles    = @()
    Errors            = @()
    Status            = "Running"
}

try {
    Import-Module Az.Storage -ErrorAction Stop
    Write-Output "Az.Storage module loaded"

    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

    # Enumerate users with active sessions on this host
    $activeUsers = @()
    try {
        $loggedOn = Get-CimInstance -ClassName Win32_LoggedOnUser -ErrorAction SilentlyContinue
        foreach ($s in $loggedOn) {
            if ($s.Antecedent -match 'Name="([^"]+)"') {
                $activeUsers += $matches[1].ToLower()
            }
        }
        $activeUsers = $activeUsers | Sort-Object -Unique
    } catch {
        Write-Warning "Session enumeration failed: $_"
    }
    Write-Output "Active users on host: $(if ($activeUsers) { $activeUsers -join ', ' } else { '(none)' })"

    $handles = @(Get-AzStorageFileHandle -Context $ctx -ShareName $ShareName -Recursive -ErrorAction Stop)
    $result.TotalHandles = $handles.Count
    Write-Output "Open handles found: $($handles.Count)"

    $cutoffUtc = (Get-Date).ToUniversalTime().AddHours(-$MaxHandleAgeHours)
    $sidRx     = [regex]'S-1-5-21-\d+-\d+-\d+-\d+'

    foreach ($handle in $handles) {
        $entry = @{
            HandleId = $handle.HandleId
            Path     = $handle.Path
            ClientIp = $handle.ClientIp
            OpenTime = if ($handle.OpenTime) { $handle.OpenTime.ToString("yyyy-MM-dd HH:mm:ss UTC") } else { "unknown" }
        }

        try {
            # Skip handles that are not yet stale
            if ($handle.OpenTime -and $handle.OpenTime.UtcDateTime -gt $cutoffUtc) {
                $entry.Status = "Skipped-TooNew"
                $result.SkippedHandles += $entry
                continue
            }

            # Extract username from FSLogix folder name in the path
            # Path format: /<SID>_<username>/Profile_<SID>.vhdx  (FlipFlopProfileDirectoryName=1)
            $segments   = ($handle.Path -split "/") | Where-Object { $_ -ne "" }
            $folderName = if ($segments.Count -ge 1) { $segments[0] } else { "" }
            $sidMatch   = $sidRx.Match($folderName)
            $handleUser = ""
            if ($sidMatch.Success) {
                $handleUser = ($folderName -replace [regex]::Escape($sidMatch.Value), "" -replace "^_|_$", "").ToLower()
            }

            # If user is still actively logged in, the lock is legitimate — leave it
            if ($handleUser -and ($activeUsers -contains $handleUser)) {
                $entry.Status = "Skipped-UserActive"
                $entry.User   = $handleUser
                $result.SkippedHandles += $entry
                Write-Output "SKIP (user $handleUser active): $($handle.Path)"
                continue
            }

            # Stale and no active session — force close
            Close-AzStorageFileHandle -Context $ctx -ShareName $ShareName -Handle $handle -Force -ErrorAction Stop
            $entry.Status = "Closed"
            $entry.User   = $handleUser
            $result.ClosedHandles += $entry
            Write-Output "CLOSED handle $($handle.HandleId) | $($handle.Path) | open since $($entry.OpenTime)"

        } catch {
            $entry.Status = "Error"
            $entry.Reason = "$_"
            $result.Errors += $entry
            Write-Error "Error on handle $($handle.HandleId): $_"
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

# Notify Teams only when handles were closed or errors occurred
if ($TeamsWebhookUrl -and ($result.ClosedHandles.Count -gt 0 -or $result.Errors.Count -gt 0)) {
    $color   = if ($result.Errors.Count -gt 0) { "FF0000" } elseif ($result.ClosedHandles.Count -gt 0) { "FF8C00" } else { "00C853" }
    $summary = "FSLogix Stale Handle Cleanup | Closed: $($result.ClosedHandles.Count) / $($result.TotalHandles) handles | Errors: $($result.Errors.Count)"
    $card    = @{
        "@type"    = "MessageCard"
        "@context" = "http://schema.org/extensions"
        themeColor = $color
        summary    = $summary
        title      = "FSLogix Stale Handle Cleanup — $($result.Status)"
        text       = $summary
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body $card -ContentType "application/json" -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Teams notification failed: $_"
    }
}
