$ErrorActionPreference = "Stop"

$Repo = "C:\AADO"
$PrivateRoot = "C:\AADO_PRIVATE\telegram"
$RuntimeRoot = Join-Path $PrivateRoot "runtime"

$CredentialFile = Join-Path $PrivateRoot "bot-token.credential.xml"
$ConfigFile = Join-Path $PrivateRoot "telegram-config.json"
$StateFile = Join-Path $RuntimeRoot "state.json"
$AuditFile = Join-Path $RuntimeRoot "audit.log"

$CoreModule = Join-Path $Repo "tools\telegram-runner\TelegramRunnerCore.psm1"
$Git = "C:\Program Files\Git\cmd\git.exe"

New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null

Import-Module $CoreModule -Force

function Write-Audit {
    param(
        [string]$Event,
        [string]$Detail
    )

    $Line = "{0}`t{1}`t{2}" -f `
        (Get-AadoTelegramTimestamp),
        $Event,
        $Detail

    Add-Content -Path $AuditFile -Value $Line -Encoding UTF8
}

function Send-TelegramMessage {
    param(
        [long]$ChatId,
        [string]$Text
    )

    $Uri = "https://api.telegram.org/bot$script:Token/sendMessage"

    $Body = @{
        chat_id = $ChatId
        text = $Text
    }

    $Response = Invoke-RestMethod `
        -Method Post `
        -Uri $Uri `
        -Body $Body `
        -TimeoutSec 15

    if (-not $Response.ok) {
        throw "Telegram sendMessage returned ok=false."
    }
}

function Get-StatusMessage {
    $Branch = (& $Git -C $Repo branch --show-current).Trim()
    $Head = (& $Git -C $Repo rev-parse --short=12 HEAD).Trim()
    $Dirty = @(& $Git -C $Repo status --porcelain).Count

    $TreeState = if ($Dirty -eq 0) { "CLEAN" } else { "DIRTY ($Dirty)" }

    return @"
AADO STATUS

Branch: $Branch
Commit: $Head
Working tree: $TreeState
Telegram runner: ONLINE
"@
}

function Get-HealthMessage {
    $Checks = @()

    $Checks += if (Test-Path $Repo) {
        "PASS repo"
    } else {
        "FAIL repo"
    }

    $Checks += if (Test-Path $CoreModule) {
        "PASS telegram core"
    } else {
        "FAIL telegram core"
    }

    $Checks += if (Test-Path $CredentialFile) {
        "PASS bot credential"
    } else {
        "FAIL bot credential"
    }

    $Checks += if (Test-Path $ConfigFile) {
        "PASS telegram config"
    } else {
        "FAIL telegram config"
    }

    try {
        $null = & $Git -C $Repo rev-parse --is-inside-work-tree
        $Checks += "PASS git"
    }
    catch {
        $Checks += "FAIL git"
    }

    return "AADO HEALTH`n`n" + ($Checks -join "`n")
}

if (-not (Test-Path $CredentialFile)) {
    throw "Missing Telegram credential file."
}

if (-not (Test-Path $ConfigFile)) {
    throw "Missing Telegram config."
}

$Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$Credential = Import-Clixml $CredentialFile
$script:Token = $Credential.GetNetworkCredential().Password

if ([string]::IsNullOrWhiteSpace($script:Token)) {
    throw "Could not recover Telegram bot token."
}

$State = Read-AadoTelegramState -Path $StateFile

if (-not (Test-Path $StateFile)) {
    Write-AadoTelegramState -State $State -Path $StateFile
}

$Open = @(Get-AadoTelegramOpenUpdates -State $State)

if ($Open.Count -gt 0) {
    Write-Audit `
        -Event "RECOVERY_REQUIRED" `
        -Detail "Found $($Open.Count) IN_PROGRESS update(s). No automatic replay."

    Send-TelegramMessage `
        -ChatId ([long]$Config.allowed_chat_id) `
        -Text "AADO WARNING`n`nPrevious Telegram action was interrupted. Automatic replay is disabled. Review required."
}

$Offset = Get-AadoTelegramNextOffset -State $State

Write-Host ""
Write-Host "=== AADO TELEGRAM RUNNER MVP-1 ==="
Write-Host "Bot    : @$($Config.bot_username)"
Write-Host "Offset : $Offset"
Write-Host "Mode   : READ_ONLY"
Write-Host ""
Write-Host "Commands: /ping /help /status /health"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

Write-Audit -Event "RUNNER_START" -Detail "offset=$Offset"

try {
    while ($true) {

        $Uri = "https://api.telegram.org/bot$script:Token/getUpdates?timeout=20&offset=$Offset&limit=10"

        try {
            $Response = Invoke-RestMethod `
                -Method Get `
                -Uri $Uri `
                -TimeoutSec 30
        }
        catch {
            Write-Audit -Event "NETWORK_ERROR" -Detail $_.Exception.Message
            Start-Sleep -Seconds 3
            continue
        }

        if (-not $Response.ok) {
            Write-Audit -Event "TELEGRAM_ERROR" -Detail "getUpdates ok=false"
            Start-Sleep -Seconds 3
            continue
        }

        foreach ($Update in $Response.result) {

            $UpdateId = [long]$Update.update_id
            $Offset = $UpdateId + 1

            $ExistingStatus = Get-AadoTelegramUpdateStatus `
                -State $State `
                -UpdateId $UpdateId

            if ($ExistingStatus) {
                Write-Audit `
                    -Event "DUPLICATE_UPDATE" `
                    -Detail "update=$UpdateId status=$ExistingStatus"

                continue
            }

            if (-not $Update.message) {
                Add-AadoTelegramUpdate `
                    -State $State `
                    -UpdateId $UpdateId `
                    -Status "IGNORED" `
                    -Command ""

                Write-AadoTelegramState -State $State -Path $StateFile
                continue
            }

            $Message = $Update.message

            $UserId = [long]$Message.from.id
            $ChatId = [long]$Message.chat.id
            $ChatType = [string]$Message.chat.type
            $Text = [string]$Message.text

            $Authorized = Test-AadoTelegramAuthorization `
                -UserId $UserId `
                -ChatId $ChatId `
                -ChatType $ChatType `
                -Config $Config

            if (-not $Authorized) {

                Add-AadoTelegramUpdate `
                    -State $State `
                    -UpdateId $UpdateId `
                    -Status "REJECTED" `
                    -Command ""

                Write-AadoTelegramState -State $State -Path $StateFile

                Write-Audit `
                    -Event "AUTH_REJECT" `
                    -Detail "update=$UpdateId user=$UserId chat=$ChatId type=$ChatType"

                continue
            }

            $Command = Get-AadoTelegramCommand -Text $Text

            Add-AadoTelegramUpdate `
                -State $State `
                -UpdateId $UpdateId `
                -Status "IN_PROGRESS" `
                -Command ([string]$Command)

            Write-AadoTelegramState -State $State -Path $StateFile

            Write-Audit `
                -Event "COMMAND_RECEIVED" `
                -Detail "update=$UpdateId command=$Command"

            try {
                switch ($Command) {

                    "PING" {
                        $Reply = "AADO ONLINE"
                    }

                    "HELP" {
                        $Reply = @"
AADO MVP-1

/ping - verifica Telegram Runner
/status - estado Git basico
/health - chequeos basicos
/help - comandos disponibles

Modo actual: READ_ONLY
"@
                    }

                    "STATUS" {
                        $Reply = Get-StatusMessage
                    }

                    "HEALTH" {
                        $Reply = Get-HealthMessage
                    }

                    default {
                        $Reply = "Comando no permitido. Usa /help."
                    }
                }

                Send-TelegramMessage `
                    -ChatId $ChatId `
                    -Text $Reply

                Set-AadoTelegramUpdateStatus `
                    -State $State `
                    -UpdateId $UpdateId `
                    -Status "COMPLETED"

                Write-AadoTelegramState -State $State -Path $StateFile

                Write-Audit `
                    -Event "COMMAND_COMPLETED" `
                    -Detail "update=$UpdateId command=$Command"

                Write-Host "PASS update=$UpdateId command=$Command"
            }
            catch {
                Set-AadoTelegramUpdateStatus `
                    -State $State `
                    -UpdateId $UpdateId `
                    -Status "FAILED"

                Write-AadoTelegramState -State $State -Path $StateFile

                Write-Audit `
                    -Event "COMMAND_FAILED" `
                    -Detail "update=$UpdateId command=$Command error=$($_.Exception.Message)"

                Write-Warning "Command failed: $Command"
            }
        }
    }
}
finally {
    Write-Audit -Event "RUNNER_STOP" -Detail "process stopped"

    Remove-Variable Token `
        -Scope Script `
        -ErrorAction SilentlyContinue
}
