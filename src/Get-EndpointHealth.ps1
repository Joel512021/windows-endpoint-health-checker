#Requires -Version 5.1

<#
.SYNOPSIS
    Displays basic Windows endpoint health information.

.DESCRIPTION
    Collects Windows version, uptime, and fixed-drive space.
    Does not modify system settings.

.PARAMETER MinimumFreePercent
    Reports a warning when a drive's free space falls below
    this percentage. Default: 15.

.EXAMPLE
    .\Get-EndpointHealth.ps1

.EXAMPLE
    .\Get-EndpointHealth.ps1 -MinimumFreePercent 20
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 99)]
    [int]$MinimumFreePercent = 15
)

Set-StrictMode -Version Latest

Write-Host "`nWindows Endpoint Health Checker" -ForegroundColor Cyan
Write-Host "Run time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem `
        -ErrorAction Stop

    $uptime = (Get-Date) - $os.LastBootUpTime

    $systemInfo = [PSCustomObject]@{
        OperatingSystem   = $os.Caption
        Version           = $os.Version
        Build             = $os.BuildNumber
        LastBoot          = $os.LastBootUpTime
        Uptime            = "{0} days, {1} hours, {2} minutes" -f `
            $uptime.Days, $uptime.Hours, $uptime.Minutes
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    }

    Write-Host "`nSystem Information" -ForegroundColor Cyan
    $systemInfo | Format-List
}
catch {
    Write-Warning "System information check failed: $($_.Exception.Message)"
}

try {
    $disks = @(
        Get-CimInstance -ClassName Win32_LogicalDisk `
            -Filter "DriveType=3" -ErrorAction Stop
    )

    $diskResults = @(
        foreach ($disk in $disks) {
            if ($null -eq $disk.Size -or $disk.Size -le 0 -or
                $null -eq $disk.FreeSpace) {

                [PSCustomObject]@{
                    Drive       = $disk.DeviceID
                    TotalGB     = $null
                    FreeGB      = $null
                    FreePercent = $null
                    Status      = "UNKNOWN"
                }

                continue
            }

            $freePercent = ($disk.FreeSpace / $disk.Size) * 100

            $status = if ($freePercent -lt $MinimumFreePercent) {
                "WARNING"
            }
            else {
                "OK"
            }

            [PSCustomObject]@{
                Drive       = $disk.DeviceID
                TotalGB     = [math]::Round($disk.Size / 1GB, 2)
                FreeGB      = [math]::Round($disk.FreeSpace / 1GB, 2)
                FreePercent = [math]::Round($freePercent, 1)
                Status      = $status
            }
        }
    )

    Write-Host "`nDisk Space" -ForegroundColor Cyan
    Write-Host "Warning threshold: below $MinimumFreePercent% free"

    if ($diskResults.Count -eq 0) {
        Write-Warning "No fixed drives were returned."
    }
    else {
        $diskResults | Format-Table -AutoSize
    }
}
catch {
    Write-Warning "Disk space check failed: $($_.Exception.Message)"
}

Write-Host "`nChecks finished. Review any warnings above."
