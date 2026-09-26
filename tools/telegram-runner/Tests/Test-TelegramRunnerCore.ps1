$ErrorActionPreference = "Stop"

$Core = "C:\AADO\tools\telegram-runner\TelegramRunnerCore.psm1"

Import-Module $Core -Force

$Pass = 0
$Fail = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Name
    )

    if ($Condition) {
        Write-Host "PASS: $Name"
        $script:Pass++
    }
    else {
        Write-Host "FAIL: $Name"
        $script:Fail++
    }
}

$Timestamp = Get-AadoTelegramTimestamp

Assert-True `
    ($Timestamp -match '-03:00$') `
    "timestamp Buenos Aires -03:00"

$Config = [pscustomobject]@{
    allowed_user_id = 8943678477
    allowed_chat_id = 8943678477
    allowed_chat_type = "private"
}

Assert-True `
    (Test-AadoTelegramAuthorization `
        -UserId 8943678477 `
        -ChatId 8943678477 `
        -ChatType "private" `
        -Config $Config) `
    "authorized exact user + chat + type"

Assert-True `
    (-not (Test-AadoTelegramAuthorization `
        -UserId 111 `
        -ChatId 8943678477 `
        -ChatType "private" `
        -Config $Config)) `
    "reject wrong user"

Assert-True `
    (-not (Test-AadoTelegramAuthorization `
        -UserId 8943678477 `
        -ChatId 222 `
        -ChatType "private" `
        -Config $Config)) `
    "reject wrong chat"

Assert-True `
    (-not (Test-AadoTelegramAuthorization `
        -UserId 8943678477 `
        -ChatId 8943678477 `
        -ChatType "group" `
        -Config $Config)) `
    "reject non-private chat"

Assert-True `
    ((Get-AadoTelegramCommand "/ping") -eq "PING") `
    "route /ping"

Assert-True `
    ((Get-AadoTelegramCommand "/status@AADO_GL_bot") -eq "STATUS") `
    "route command with bot suffix"

Assert-True `
    ((Get-AadoTelegramCommand "/exec whoami") -eq "UNKNOWN") `
    "reject arbitrary shell command"

$State = New-AadoTelegramState

Add-AadoTelegramUpdate `
    -State $State `
    -UpdateId 100 `
    -Status "IN_PROGRESS" `
    -Command "PING"

Assert-True `
    ((Get-AadoTelegramUpdateStatus -State $State -UpdateId 100) -eq "IN_PROGRESS") `
    "persist in-progress state"

Set-AadoTelegramUpdateStatus `
    -State $State `
    -UpdateId 100 `
    -Status "COMPLETED"

Assert-True `
    ((Get-AadoTelegramUpdateStatus -State $State -UpdateId 100) -eq "COMPLETED") `
    "complete update"

Assert-True `
    ((Get-AadoTelegramNextOffset -State $State) -eq 101) `
    "next offset"

$DuplicateBlocked = $false

try {
    Add-AadoTelegramUpdate `
        -State $State `
        -UpdateId 100 `
        -Status "IN_PROGRESS" `
        -Command "PING"
}
catch {
    $DuplicateBlocked = $true
}

Assert-True `
    $DuplicateBlocked `
    "duplicate update blocked"

$State2 = New-AadoTelegramState

Add-AadoTelegramUpdate `
    -State $State2 `
    -UpdateId 200 `
    -Status "IN_PROGRESS" `
    -Command "STATUS"

$Open = @(Get-AadoTelegramOpenUpdates -State $State2)

Assert-True `
    ($Open.Count -eq 1) `
    "detect interrupted update"

Write-Host ""
Write-Host "===================================="
Write-Host "$Pass PASS / $Fail FAIL"
Write-Host "===================================="

if ($Fail -gt 0) {
    exit 1
}

exit 0

