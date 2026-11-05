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

# Build and save an HTML report.
try {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $reportFolder = Join-Path $projectRoot "reports"

    New-Item -ItemType Directory -Path $reportFolder `
        -Force -ErrorAction Stop | Out-Null

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss-fff"
    $reportPath = Join-Path $reportFolder `
        "EndpointHealth-$timestamp.html"

    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($null -ne $systemInfo) {
        $systemHtml = (
            $systemInfo |
                ConvertTo-Html -Fragment -As List
        ) -join "`n"
    }
    else {
        $systemHtml = "<p>System information could not be collected.</p>"
    }

    if ($diskResults.Count -gt 0) {
        $diskHtml = (
            $diskResults |
                Select-Object Drive, TotalGB, FreeGB,
                    FreePercent, Status |
                ConvertTo-Html -Fragment
        ) -join "`n"

        $diskHtml = $diskHtml.Replace(
            "<td>WARNING</td>",
            '<td class="warning">WARNING</td>'
        )

        $diskHtml = $diskHtml.Replace(
            "<td>OK</td>",
            '<td class="ok">OK</td>'
        )

        $diskHtml = $diskHtml.Replace(
            "<td>UNKNOWN</td>",
            '<td class="unknown">UNKNOWN</td>'
        )
    }
    else {
        $diskHtml = "<p>No disk-space results are available.</p>"
    }

    $reportHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Windows Endpoint Health Report</title>
    <style>
        body {
            font-family: Segoe UI, Arial, sans-serif;
            background: #f3f6fa;
            color: #243247;
            margin: 0;
            padding: 24px;
        }

        main {
            max-width: 1000px;
            margin: auto;
        }

        h1 { color: #123b63; }

        section {
            background: white;
            padding: 24px;
            margin: 20px 0;
            border-radius: 12px;
            overflow-x: auto;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
        }

        table {
            border-collapse: collapse;
            width: 100%;
        }

        th, td {
            border: 1px solid #dce3eb;
            padding: 12px;
            text-align: left;
        }

        th {
            background: #123b63;
            color: white;
        }

        tr:nth-child(even) { background: #f6f8fb; }

        .ok {
            background: #dcfce7;
            color: #166534;
            font-weight: bold;
        }

        .warning {
            background: #fef3c7;
            color: #92400e;
            font-weight: bold;
        }

        .unknown {
            background: #e5e7eb;
            color: #374151;
            font-weight: bold;
        }

        .note {
            color: #526174;
            line-height: 1.6;
        }
    </style>
</head>
<body>
<main>
    <h1>Windows Endpoint Health Report</h1>
    <p class="note">Generated: $generatedAt</p>

    <section>
        <h2>System Information</h2>
        $systemHtml
    </section>

    <section>
        <h2>Disk Space</h2>
        <p>Warning threshold: below $MinimumFreePercent% free.</p>
        $diskHtml
    </section>

    <p class="note">
        OK means a drive meets the configured free-space threshold.
        It does not indicate overall system health or security.
        Review this report before sharing device information.
    </p>
</main>
</body>
</html>
"@

    Set-Content -LiteralPath $reportPath `
        -Value $reportHtml -Encoding UTF8 -ErrorAction Stop

    Write-Host "`nHTML report saved:" -ForegroundColor Green
    Write-Host $reportPath

    Invoke-Item -LiteralPath $reportPath -ErrorAction Stop
}
catch {
    Write-Warning "Report export or opening failed: $($_.Exception.Message)"
}

# Export diagnostic results as JSON.
try {
    $jsonFolder = Join-Path `
        (Split-Path -Parent $PSScriptRoot) "reports"

    New-Item -ItemType Directory -Path $jsonFolder `
        -Force -ErrorAction Stop | Out-Null

    $jsonTimestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss-fff"

    $jsonPath = Join-Path $jsonFolder `
        "EndpointHealth-$jsonTimestamp.json"

    $reportData = [PSCustomObject]@{
        SchemaVersion      = "1.0"
        GeneratedAt        = (Get-Date).ToString("o")
        MinimumFreePercent = $MinimumFreePercent
        SystemInformation  = $systemInfo
        DiskResults        = @($diskResults)
    }

    $reportData |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $jsonPath `
            -Encoding UTF8 -ErrorAction Stop

    Write-Host "`nJSON report saved:" -ForegroundColor Green
    Write-Host $jsonPath
}
catch {
    Write-Warning "JSON export failed: $($_.Exception.Message)"
}
