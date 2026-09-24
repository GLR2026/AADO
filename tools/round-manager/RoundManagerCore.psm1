<#
AADO-COMM-001
Round Manager Core

Version: 0.8.0
Status: EARLY FUNCTIONAL

Purpose:
Deterministic workflow core for review/audit rounds.

Important:
- No AI logic.
- No automatic merge to main.
- No secrets.
- No git add .
- Core must remain callable without GUI.
- Phase member state is always addressed by section + member.
#>

Set-StrictMode -Version Latest

$script:AadoRepoRoot   = "C:\AADO"
$script:AadoRoundsRoot = Join-Path $script:AadoRepoRoot "audits\rounds"


function Get-AadoTimestamp {
    [CmdletBinding()]
    param()

    try {
        $Tz = [System.TimeZoneInfo]::FindSystemTimeZoneById(
            "Argentina Standard Time"
        )

        $Local = [System.TimeZoneInfo]::ConvertTime(
            [System.DateTimeOffset]::UtcNow,
            $Tz
        )

        return $Local.ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
    catch {
        return [System.DateTimeOffset]::UtcNow.ToOffset(
            [System.TimeSpan]::FromHours(-3)
        ).ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
}


function Get-AadoNextRoundId {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:AadoRoundsRoot)) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path $script:AadoRoundsRoot |
            Out-Null
    }

    $ExistingIds = @(
        Get-ChildItem `
            -Path $script:AadoRoundsRoot `
            -Directory `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^R\d{4}$'
        } |
        ForEach-Object {
            [int]($_.Name.Substring(1))
        }
    )

    if ($ExistingIds.Count -eq 0) {
        return "R0001"
    }

    $MaxNumber = [int](
        ($ExistingIds | Measure-Object -Maximum).Maximum
    )

    $NextNumber = [int]($MaxNumber + 1)

    return ("R{0:D4}" -f $NextNumber)
}


function Get-AadoRoundDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId
    )

    $RoundDir = Join-Path $script:AadoRoundsRoot $RoundId

    if (-not (Test-Path $RoundDir)) {
        throw "Round does not exist: $RoundId"
    }

    return $RoundDir
}


function Get-AadoPhaseMemberStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$YamlPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("blind_review","cross_review")]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [ValidateSet("claude","gemini")]
        [string]$Member
    )

    $Lines = @(Get-Content $YamlPath)
    $InSection = $false

    foreach ($Line in $Lines) {

        if ($Line -match "^\s{2}$Section`:\s*$") {
            $InSection = $true
            continue
        }

        if (
            $InSection -and
            $Line -match '^\s{2}[A-Za-z_]+:'
        ) {
            break
        }

        if (
            $InSection -and
            $Line -match "^\s{4}$Member`:\s+([A-Za-z_]+)\s*$"
        ) {
            return $Matches[1]
        }
    }

    throw "No se encontró $Section -> $Member"
}


function Set-AadoPhaseMemberStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$YamlPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet("blind_review","cross_review")]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [ValidateSet("claude","gemini")]
        [string]$Member,

        [Parameter(Mandatory = $true)]
        [ValidateSet("pending","completed")]
        [string]$Status
    )

    $Lines = [System.Collections.Generic.List[string]](
        @(Get-Content $YamlPath)
    )

    $InSection = $false
    $Changed = $false

    for ($i = 0; $i -lt $Lines.Count; $i++) {

        $Line = $Lines[$i]

        if ($Line -match "^\s{2}$Section`:\s*$") {
            $InSection = $true
            continue
        }

        if (
            $InSection -and
            $Line -match '^\s{2}[A-Za-z_]+:'
        ) {
            break
        }

        if (
            $InSection -and
            $Line -match "^\s{4}$Member`:\s+[A-Za-z_]+\s*$"
        ) {
            $Lines[$i] = "    $Member`: $Status"
            $Changed = $true
            break
        }
    }

    if (-not $Changed) {
        throw "No se pudo actualizar $Section -> $Member"
    }

    Set-Content `
        -Path $YamlPath `
        -Value $Lines `
        -Encoding UTF8
}


function New-AadoRound {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
            "architecture",
            "implementation",
            "security",
            "testing",
            "operations",
            "other"
        )]
        [string]$Category = "other"
    )

    if (-not (Test-Path $script:AadoRoundsRoot)) {
        New-Item `
            -ItemType Directory `
            -Force `
            -Path $script:AadoRoundsRoot |
            Out-Null
    }

    $RoundId = Get-AadoNextRoundId
    $RoundDir = Join-Path $script:AadoRoundsRoot $RoundId

    if (Test-Path $RoundDir) {
        throw "Round directory already exists: $RoundDir"
    }

    New-Item `
        -ItemType Directory `
        -Path $RoundDir |
        Out-Null

    $Now = Get-AadoTimestamp

    $RoundYaml = @"
schema_version: 1
round_id: $RoundId
created_at: "$Now"
updated_at: "$Now"
status: draft

topic:
  title: "$Title"
  category: "$Category"

participants:
  implementer: ChatGPT
  auditors:
    - Claude
    - Gemini
  po: Guido

phases:
  proposal: pending
  blind_review:
    claude: pending
    gemini: pending
  blind_review_closed: false
  cross_review:
    claude: pending
    gemini: pending
  implementer_response: pending
  po_digest: pending

publication:
  branch: null
  commit: null
  pr_url: null
"@

    Set-Content `
        -Path (Join-Path $RoundDir "round.yaml") `
        -Value $RoundYaml `
        -Encoding UTF8

    @"
# $RoundId — Prompt

## Objetivo

[PENDIENTE]

## Instrucciones para auditores

- Auditar de forma independiente en la primera fase.
- No asumir que la coincidencia entre auditores constituye evidencia.
- Distinguir hallazgos de auditoría de propuestas de consultoría.
- Señalar BLOCKER / HIGH / MEDIUM / LOW / OPPORTUNITY según corresponda.

## Preguntas específicas

[PENDIENTE]
"@ | Set-Content `
        -Path (Join-Path $RoundDir "prompt.md") `
        -Encoding UTF8

    @"
# $RoundId — Proposal

[PENDIENTE]
"@ | Set-Content `
        -Path (Join-Path $RoundDir "proposal.md") `
        -Encoding UTF8

    @"
# $RoundId — PO Notes

[PENDIENTE]
"@ | Set-Content `
        -Path (Join-Path $RoundDir "po-notes.md") `
        -Encoding UTF8

    @"
# $RoundId — Consolidated

[PENDIENTE]
"@ | Set-Content `
        -Path (Join-Path $RoundDir "consolidated.md") `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId   = $RoundId
        RoundPath = $RoundDir
        Status    = "draft"
        Title     = $Title
        Category  = $Category
    }
}


function Save-AadoProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"
    $ProposalPath = Join-Path $RoundDir "proposal.md"

    $Yaml = Get-Content $YamlPath -Raw

    if (
        $Yaml -notmatch
        '(?m)^\s{2}proposal:\s+pending\s*$'
    ) {
        throw "Proposal phase is not pending. Refusing silent overwrite."
    }

    @"
# $RoundId — Proposal

$Content
"@ | Set-Content `
        -Path $ProposalPath `
        -Encoding UTF8

    $Now = Get-AadoTimestamp

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^updated_at:\s*".*?"\s*$',
        "updated_at: `"$Now`""
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})proposal:\s+pending\s*$',
        '${1}proposal: completed'
    )

    Set-Content `
        -Path $YamlPath `
        -Value $Yaml `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId      = $RoundId
        ProposalFile = $ProposalPath
        Phase        = "completed"
        UpdatedAt    = $Now
    }
}


function Save-AadoBlindResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("claude","gemini")]
        [string]$Auditor,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"

    $Yaml = Get-Content $YamlPath -Raw

    if (
        $Yaml -notmatch
        '(?m)^\s{2}proposal:\s+completed\s*$'
    ) {
        throw "Proposal must be completed before blind review."
    }

    if (
        $Yaml -match
        '(?m)^\s{2}blind_review_closed:\s+true\s*$'
    ) {
        throw "Blind review is already closed."
    }

    $CurrentStatus = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "blind_review" `
        -Member $Auditor

    if ($CurrentStatus -ne "pending") {
        throw "Blind response for $Auditor is not pending. Refusing silent overwrite."
    }

    $ResponsePath = Join-Path `
        $RoundDir `
        ("blind-{0}.md" -f $Auditor)

    if (Test-Path $ResponsePath) {
        throw "Blind response file already exists: $ResponsePath"
    }

    $Now = Get-AadoTimestamp

    @"
# $RoundId — Blind Review — $Auditor

Captured at: $Now
Phase: blind_review
Auditor: $Auditor

---

$Content
"@ | Set-Content `
        -Path $ResponsePath `
        -Encoding UTF8

    Set-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "blind_review" `
        -Member $Auditor `
        -Status "completed"

    $Yaml = Get-Content $YamlPath -Raw

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^updated_at:\s*".*?"\s*$',
        "updated_at: `"$Now`""
    )

    Set-Content `
        -Path $YamlPath `
        -Value $Yaml `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId      = $RoundId
        Auditor      = $Auditor
        ResponseFile = $ResponsePath
        Phase        = "completed"
        UpdatedAt    = $Now
    }
}


function Close-AadoBlindPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"

    $Yaml = Get-Content $YamlPath -Raw

    if (
        $Yaml -match
        '(?m)^\s{2}blind_review_closed:\s+true\s*$'
    ) {
        throw "Blind review is already closed."
    }

    $ClaudeStatus = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "blind_review" `
        -Member "claude"

    $GeminiStatus = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "blind_review" `
        -Member "gemini"

    if ($ClaudeStatus -ne "completed") {
        throw "Claude blind review is not completed."
    }

    if ($GeminiStatus -ne "completed") {
        throw "Gemini blind review is not completed."
    }

    $Now = Get-AadoTimestamp

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^updated_at:\s*".*?"\s*$',
        "updated_at: `"$Now`""
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})blind_review_closed:\s+false\s*$',
        '${1}blind_review_closed: true'
    )

    Set-Content `
        -Path $YamlPath `
        -Value $Yaml `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId   = $RoundId
        Phase     = "blind_review"
        Closed    = $true
        UpdatedAt = $Now
    }
}


function Save-AadoCrossReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("claude","gemini")]
        [string]$Auditor,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"

    $Yaml = Get-Content $YamlPath -Raw

    if (
        $Yaml -notmatch
        '(?m)^\s{2}blind_review_closed:\s+true\s*$'
    ) {
        throw "Blind review must be closed before cross review."
    }

    $CurrentStatus = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "cross_review" `
        -Member $Auditor

    if ($CurrentStatus -ne "pending") {
        throw "Cross review for $Auditor is not pending. Refusing silent overwrite."
    }

    $OwnBlindPath = Join-Path `
        $RoundDir `
        ("blind-{0}.md" -f $Auditor)

    if (-not (Test-Path $OwnBlindPath)) {
        throw "Own blind review is missing for $Auditor."
    }

    $OtherAuditor = if ($Auditor -eq "claude") {
        "gemini"
    }
    else {
        "claude"
    }

    $OtherBlindPath = Join-Path `
        $RoundDir `
        ("blind-{0}.md" -f $OtherAuditor)

    if (-not (Test-Path $OtherBlindPath)) {
        throw "Other auditor blind review is missing: $OtherAuditor"
    }

    $CrossPath = Join-Path `
        $RoundDir `
        ("cross-{0}.md" -f $Auditor)

    if (Test-Path $CrossPath) {
        throw "Cross review file already exists: $CrossPath"
    }

    $Now = Get-AadoTimestamp

    @"
# $RoundId — Cross Review — $Auditor

Captured at: $Now
Phase: cross_review
Auditor: $Auditor
Reviewed auditor: $OtherAuditor

Allowed dispositions:
- AGREE
- DISAGREE
- PARTIAL
- NEW_FINDING
- CHANGED_POSITION

Rule:
Coincidence is not evidence.
A changed position should identify the evidence that caused the change.

---

$Content
"@ | Set-Content `
        -Path $CrossPath `
        -Encoding UTF8

    Set-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "cross_review" `
        -Member $Auditor `
        -Status "completed"

    $Yaml = Get-Content $YamlPath -Raw

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^updated_at:\s*".*?"\s*$',
        "updated_at: `"$Now`""
    )

    Set-Content `
        -Path $YamlPath `
        -Value $Yaml `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId       = $RoundId
        Auditor       = $Auditor
        Reviewed      = $OtherAuditor
        CrossFile     = $CrossPath
        Phase         = "completed"
        UpdatedAt     = $Now
    }
}


function Save-AadoImplementerResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"

    $ClaudeCross = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "cross_review" `
        -Member "claude"

    $GeminiCross = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section "cross_review" `
        -Member "gemini"

    if ($ClaudeCross -ne "completed") {
        throw "Claude cross review is not completed."
    }

    if ($GeminiCross -ne "completed") {
        throw "Gemini cross review is not completed."
    }

    $Yaml = Get-Content $YamlPath -Raw

    if (
        $Yaml -notmatch
        '(?m)^\s{2}implementer_response:\s+pending\s*$'
    ) {
        throw "Implementer response is not pending. Refusing silent overwrite."
    }

    $ResponsePath = Join-Path $RoundDir "implementer-response.md"

    if (Test-Path $ResponsePath) {
        throw "Implementer response file already exists."
    }

    $Now = Get-AadoTimestamp

    @"
# $RoundId — Implementer Response

Captured at: $Now
Phase: implementer_response
Role: implementer

Allowed dispositions:
- ACCEPTED
- REJECTED
- DEFERRED
- NEEDS_PO
- NEEDS_TEST

Rule:
Every material finding must receive an explicit disposition.
No finding may disappear silently.

---

$Content
"@ | Set-Content `
        -Path $ResponsePath `
        -Encoding UTF8

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^updated_at:\s*".*?"\s*$',
        "updated_at: `"$Now`""
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})implementer_response:\s+pending\s*$',
        '${1}implementer_response: completed'
    )

    Set-Content `
        -Path $YamlPath `
        -Value $Yaml `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId      = $RoundId
        ResponseFile = $ResponsePath
        Phase        = "completed"
        UpdatedAt    = $Now
    }
}

function Build-AadoPODigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"
    $ImplementerPath = Join-Path $RoundDir "implementer-response.md"
    $DigestPath = Join-Path $RoundDir "po-digest.md"

    if (-not (Test-Path $ImplementerPath)) {
        throw "implementer-response.md does not exist."
    }

    $Yaml = Get-Content $YamlPath -Raw

    if (
        $Yaml -notmatch
        '(?m)^\s{2}implementer_response:\s+completed\s*$'
    ) {
        throw "Implementer response must be completed before PO Digest."
    }

    if (
        $Yaml -notmatch
        '(?m)^\s{2}po_digest:\s+pending\s*$'
    ) {
        throw "PO Digest is not pending. Refusing silent overwrite."
    }

    if (Test-Path $DigestPath) {
        throw "PO Digest file already exists."
    }

    $Lines = @(Get-Content $ImplementerPath)

    $Allowed = @(
        "ACCEPTED",
        "REJECTED",
        "DEFERRED",
        "NEEDS_PO",
        "NEEDS_TEST"
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $CurrentFinding = $null

    foreach ($Line in $Lines) {

        if ($Line -match '^FINDING\s+(.+?)\s*$') {
            $CurrentFinding = $Matches[1].Trim()
            continue
        }

        if ($Line -match '^Disposition:\s*([A-Z_]+)\s*$') {

            if (-not $CurrentFinding) {
                throw "Disposition found without preceding FINDING."
            }

            $Disposition = $Matches[1].Trim()

            if ($Allowed -notcontains $Disposition) {
                throw "Invalid disposition: $Disposition"
            }

            $Findings.Add(
                [pscustomobject]@{
                    Finding     = $CurrentFinding
                    Disposition = $Disposition
                }
            )

            $CurrentFinding = $null
        }
    }

    if ($Findings.Count -eq 0) {
        throw "No structured FINDING / Disposition pairs were found."
    }

    $DuplicateIds = @(
        $Findings |
        Group-Object Finding |
        Where-Object Count -gt 1
    )

    if ($DuplicateIds.Count -gt 0) {
        $Ids = ($DuplicateIds.Name -join ", ")
        throw "Duplicate finding IDs detected: $Ids"
    }

    $Counts = @{}

    foreach ($State in $Allowed) {
        $Counts[$State] = @(
            $Findings |
            Where-Object Disposition -eq $State
        ).Count
    }

    $Attention = @(
        $Findings |
        Where-Object {
            $_.Disposition -in @(
                "REJECTED",
                "DEFERRED",
                "NEEDS_PO",
                "NEEDS_TEST"
            )
        }
    )

    $Now = Get-AadoTimestamp

    $Digest = [System.Collections.Generic.List[string]]::new()

    $Digest.Add("# $RoundId — PO Digest")
    $Digest.Add("")
    $Digest.Add("Generated at: $Now")
    $Digest.Add("Generation mode: deterministic")
    $Digest.Add("")
    $Digest.Add("## Resumen")
    $Digest.Add("")
    $Digest.Add("Total findings: $($Findings.Count)")
    $Digest.Add("ACCEPTED: $($Counts['ACCEPTED'])")
    $Digest.Add("REJECTED: $($Counts['REJECTED'])")
    $Digest.Add("DEFERRED: $($Counts['DEFERRED'])")
    $Digest.Add("NEEDS_PO: $($Counts['NEEDS_PO'])")
    $Digest.Add("NEEDS_TEST: $($Counts['NEEDS_TEST'])")
    $Digest.Add("")
    $Digest.Add("## Puntos que requieren atención del PO")
    $Digest.Add("")

    if ($Attention.Count -eq 0) {
        $Digest.Add("Ninguno.")
    }
    else {
        foreach ($Item in $Attention) {
            $Digest.Add(
                "- $($Item.Finding) — $($Item.Disposition)"
            )
        }
    }

    $Digest.Add("")
    $Digest.Add("## Todos los findings")
    $Digest.Add("")

    foreach ($Item in $Findings) {
        $Digest.Add(
            "- $($Item.Finding) — $($Item.Disposition)"
        )
    }

    $Digest.Add("")
    $Digest.Add("## Regla")
    $Digest.Add("")
    $Digest.Add(
        "Este digest no interpreta argumentos ni decide quién tiene razón."
    )
    $Digest.Add(
        "Resume mecánicamente las disposiciones registradas por el implementador."
    )
    $Digest.Add(
        "Los informes originales permanecen disponibles para revisión."
    )

    Set-Content `
        -Path $DigestPath `
        -Value $Digest `
        -Encoding UTF8

    $Yaml = Get-Content $YamlPath -Raw

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^updated_at:\s*".*?"\s*$',
        "updated_at: `"$Now`""
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})po_digest:\s+pending\s*$',
        '${1}po_digest: completed'
    )

    Set-Content `
        -Path $YamlPath `
        -Value $Yaml `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId       = $RoundId
        DigestFile    = $DigestPath
        TotalFindings = $Findings.Count
        Accepted      = $Counts["ACCEPTED"]
        Rejected      = $Counts["REJECTED"]
        Deferred      = $Counts["DEFERRED"]
        NeedsPO       = $Counts["NEEDS_PO"]
        NeedsTest     = $Counts["NEEDS_TEST"]
        Attention     = $Attention.Count
        Phase         = "completed"
        UpdatedAt     = $Now
    }
}

Export-ModuleMember -Function @(
    "Get-AadoTimestamp",
    "Get-AadoNextRoundId",
    "Get-AadoPhaseMemberStatus",
    "Set-AadoPhaseMemberStatus",
    "New-AadoRound",
    "Save-AadoProposal",
    "Save-AadoBlindResponse",
    "Close-AadoBlindPhase",
    "Save-AadoCrossReview",
    "Save-AadoImplementerResponse",
    "Build-AadoPODigest"
)

