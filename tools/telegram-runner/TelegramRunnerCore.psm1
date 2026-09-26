<#
AADO Telegram Runner Core
Version: 0.1.0
Scope: MVP-1 READ_ONLY
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AadoTelegramTimestamp {
    return [DateTimeOffset]::UtcNow.
        ToOffset([TimeSpan]::FromHours(-3)).
        ToString("yyyy-MM-ddTHH:mm:sszzz")
}

function Test-AadoTelegramAuthorization {
    param(
        [Parameter(Mandatory)]
        [long]$UserId,

        [Parameter(Mandatory)]
        [long]$ChatId,

        [Parameter(Mandatory)]
        [string]$ChatType,

        [Parameter(Mandatory)]
        $Config
    )

    return (
        $UserId -eq [long]$Config.allowed_user_id -and
        $ChatId -eq [long]$Config.allowed_chat_id -and
        $ChatType -eq [string]$Config.allowed_chat_type
    )
}

function Get-AadoTelegramCommand {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $FirstToken = ($Text.Trim() -split '\s+')[0]

    if ($FirstToken.Contains("@")) {
        $FirstToken = ($FirstToken -split "@")[0]
    }

    switch ($FirstToken.ToLowerInvariant()) {
        "/ping"   { return "PING" }
        "/help"   { return "HELP" }
        "/status" { return "STATUS" }
        "/health" { return "HEALTH" }
        default   { return "UNKNOWN" }
    }
}

function New-AadoTelegramState {
    return [ordered]@{
        schema_version = 1
        updates = @()
    }
}

function Read-AadoTelegramState {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return New-AadoTelegramState
    }

    $Raw = Get-Content $Path -Raw

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        throw "Telegram state file is empty."
    }

    $State = $Raw | ConvertFrom-Json

    if ([int]$State.schema_version -ne 1) {
        throw "Unsupported Telegram state schema."
    }

    return $State
}

function Write-AadoTelegramState {
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $Directory = Split-Path $Path -Parent

    if (-not (Test-Path $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $Temp = "$Path.tmp"

    $State |
        ConvertTo-Json -Depth 10 |
        Set-Content -Path $Temp -Encoding UTF8

    Move-Item -Path $Temp -Destination $Path -Force
}

function Get-AadoTelegramUpdateStatus {
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [long]$UpdateId
    )

    $Match = @(
        $State.updates |
        Where-Object { [long]$_.update_id -eq $UpdateId }
    )

    if ($Match.Count -eq 0) {
        return $null
    }

    return [string]$Match[-1].status
}

function Add-AadoTelegramUpdate {
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [long]$UpdateId,

        [Parameter(Mandatory)]
        [ValidateSet("IN_PROGRESS","COMPLETED","REJECTED","IGNORED","FAILED")]
        [string]$Status,

        [string]$Command = ""
    )

    $Existing = @(
        $State.updates |
        Where-Object { [long]$_.update_id -eq $UpdateId }
    )

    if ($Existing.Count -gt 0) {
        throw "Update already exists: $UpdateId"
    }

    $Entry = [ordered]@{
        update_id = $UpdateId
        status = $Status
        command = $Command
        updated_at = Get-AadoTelegramTimestamp
    }

    $All = @($State.updates) + @($Entry)

    if ($All.Count -gt 200) {
        $All = @($All | Select-Object -Last 200)
    }

    $State.updates = $All
}

function Set-AadoTelegramUpdateStatus {
    param(
        [Parameter(Mandatory)]
        $State,

        [Parameter(Mandatory)]
        [long]$UpdateId,

        [Parameter(Mandatory)]
        [ValidateSet("IN_PROGRESS","COMPLETED","REJECTED","IGNORED","FAILED")]
        [string]$Status
    )

    $Found = $false

    foreach ($Entry in $State.updates) {
        if ([long]$Entry.update_id -eq $UpdateId) {
            $Entry.status = $Status
            $Entry.updated_at = Get-AadoTelegramTimestamp
            $Found = $true
            break
        }
    }

    if (-not $Found) {
        throw "Update not found: $UpdateId"
    }
}

function Get-AadoTelegramNextOffset {
    param(
        [Parameter(Mandatory)]
        $State
    )

    if (-not $State.updates -or @($State.updates).Count -eq 0) {
        return [long]0
    }

    $Max = (
        $State.updates |
        ForEach-Object { [long]$_.update_id } |
        Measure-Object -Maximum
    ).Maximum

    return ([long]$Max + 1)
}

function Get-AadoTelegramOpenUpdates {
    param(
        [Parameter(Mandatory)]
        $State
    )

    return @(
        $State.updates |
        Where-Object { $_.status -eq "IN_PROGRESS" }
    )
}

Export-ModuleMember -Function @(
    "Get-AadoTelegramTimestamp",
    "Test-AadoTelegramAuthorization",
    "Get-AadoTelegramCommand",
    "New-AadoTelegramState",
    "Read-AadoTelegramState",
    "Write-AadoTelegramState",
    "Get-AadoTelegramUpdateStatus",
    "Add-AadoTelegramUpdate",
    "Set-AadoTelegramUpdateStatus",
    "Get-AadoTelegramNextOffset",
    "Get-AadoTelegramOpenUpdates"
)

