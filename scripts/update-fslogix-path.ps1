# ============================================================
# update-fslogix-path.ps1
# Updates FSLogix VHD location on all AVD session hosts
# via Azure VM Run Command — no RDP needed
# ============================================================

param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $HostPoolName,
    [Parameter(Mandatory)] [string] $NewProfilePath,
    [string] $OldProfilePath = "",
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   FSLogix Path Update"                      -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Host Pool   : $HostPoolName"
Write-Host "New Path    : $NewProfilePath"
if ($DryRun) { Write-Host "Mode        : DRY RUN" -ForegroundColor Yellow }

# ── Get All Session Hosts ────────────────────────────────────
Write-Host "`nGetting session hosts from host pool..." -ForegroundColor Yellow

$sessionHosts = az desktopvirtualization sessionhost list `
    --resource-group $ResourceGroup `
    --host-pool-name $HostPoolName `
    --query "[].{Name:name, Status:status, VM:resourceId}" `
    --output json | ConvertFrom-Json

if ($sessionHosts.Count -eq 0) {
    Write-Host "No session hosts found in host pool!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($sessionHosts.Count) session host(s):" -ForegroundColor Green
$sessionHosts | ForEach-Object {
    Write-Host "  - $($_.Name) [$($_.Status)]"
}

# ── FSLogix Registry Update Script ──────────────────────────
$fslogixScript = @"
`$ErrorActionPreference = 'Stop'
`$regPath = 'HKLM:\SOFTWARE\FSLogix\Profiles'

# Ensure FSLogix registry key exists
if (-not (Test-Path `$regPath)) {
    New-Item -Path `$regPath -Force | Out-Null
    Write-Host 'Created FSLogix registry key'
}

# Backup old path
`$oldPath = Get-ItemProperty -Path `$regPath -Name 'VHDLocations' -ErrorAction SilentlyContinue
if (`$oldPath) {
    Write-Host "Old VHDLocations: `$(`$oldPath.VHDLocations)"
    Set-ItemProperty -Path `$regPath -Name 'VHDLocations_Backup' -Value `$oldPath.VHDLocations
}

# Set new path
Set-ItemProperty -Path `$regPath -Name 'VHDLocations' -Value '$NewProfilePath'
Set-ItemProperty -Path `$regPath -Name 'Enabled' -Value 1 -Type DWord
Set-ItemProperty -Path `$regPath -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -Type DWord
Set-ItemProperty -Path `$regPath -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord

# Verify
`$newPath = Get-ItemProperty -Path `$regPath -Name 'VHDLocations'
Write-Host "New VHDLocations: `$(`$newPath.VHDLocations)"
Write-Host "FSLogix path updated successfully"
"@

# ── Apply to Each Session Host ───────────────────────────────
Write-Host "`nUpdating FSLogix path on session hosts..." -ForegroundColor Yellow

$successCount = 0
$failCount    = 0

foreach ($host in $sessionHosts) {
    # Extract VM name from resource ID
    $vmName = $host.Name.Split('/')[1]
    Write-Host "`nProcessing: $vmName" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would update FSLogix path on $vmName" -ForegroundColor Yellow
        $successCount++
        continue
    }

    try {
        # Check VM is running
        $vmStatus = az vm get-instance-view `
            --resource-group $ResourceGroup `
            --name $vmName `
            --query "instanceView.statuses[1].displayStatus" `
            --output tsv

        if ($vmStatus -ne "VM running") {
            Write-Host "  ⚠ VM not running ($vmStatus) — skipping" -ForegroundColor Yellow
            continue
        }

        # Run registry update via run-command
        Write-Host "  Updating FSLogix registry..." -ForegroundColor Gray

        $result = az vm run-command invoke `
            --resource-group $ResourceGroup `
            --name $vmName `
            --command-id RunPowerShellScript `
            --scripts $fslogixScript `
            --output json | ConvertFrom-Json

        $output = $result.value[0].message
        $stderr = $result.value[1].message

        if ($stderr) {
            Write-Host "  ❌ Error: $stderr" -ForegroundColor Red
            $failCount++
        } else {
            Write-Host "  ✅ Updated successfully" -ForegroundColor Green
            Write-Host "  Output: $output" -ForegroundColor Gray
            $successCount++
        }

    } catch {
        Write-Host "  ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

# ── Verify on First Host ─────────────────────────────────────
if (-not $DryRun -and $successCount -gt 0) {
    Write-Host "`nVerifying registry update on first host..." -ForegroundColor Yellow

    $firstVm = $sessionHosts[0].Name.Split('/')[1]

    $verifyScript = @"
`$path = Get-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'VHDLocations'
Write-Host "Current VHDLocations: `$(`$path.VHDLocations)"
"@

    $verify = az vm run-command invoke `
        --resource-group $ResourceGroup `
        --name $firstVm `
        --command-id RunPowerShellScript `
        --scripts $verifyScript `
        --output json | ConvertFrom-Json

    Write-Host "Verification: $($verify.value[0].message)" -ForegroundColor Cyan
}

# ── Summary ──────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "   Update Summary"                             -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Total hosts : $($sessionHosts.Count)"
Write-Host "Updated     : $successCount" -ForegroundColor Green
Write-Host "Failed      : $failCount"    -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host "New path    : $NewProfilePath"

if ($failCount -gt 0) {
    Write-Host "`n⚠ Some hosts failed — check above output" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "`n✅ All session hosts updated successfully!" -ForegroundColor Green
    Write-Host "Users will get new profile path on next login." -ForegroundColor Green
    exit 0
}
