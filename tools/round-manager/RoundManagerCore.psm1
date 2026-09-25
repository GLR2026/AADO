<#
AADO-COMM-001
Round Manager Core

Version: 0.10.0
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

if ([string]::IsNullOrWhiteSpace($env:AADO_REPO_ROOT)) {
    $script:AadoRepoRoot = "C:\AADO"
}
else {
    $script:AadoRepoRoot = [System.IO.Path]::GetFullPath(
        $env:AADO_REPO_ROOT
    )
}

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
        [string]$Title,

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

    $RoundId = Get-AadoNextRoundId
    $RoundDir = Join-Path $script:AadoRoundsRoot $RoundId

    if (Test-Path $RoundDir) {
        throw "Round already exists: $RoundId"
    }

    New-Item `
        -ItemType Directory `
        -Path $RoundDir `
        -Force |
        Out-Null

    $Now = Get-AadoTimestamp

    $RoundYaml = @"
schema_version: 2
round_id: $RoundId
created_at: "$Now"
updated_at: "$Now"
status: draft

topic:
  title: "$Title"
  category: $Category

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

merge_gate:
  status: pending
  blocking_findings: 0

publication:
  branch: null
  commit: null
  pr_url: null
  pr_number: null
  mergeability: null
  checked_at: null

po_decision:
  status: pending
  decided_at: null
  approved_commit: null
"@

    Set-Content `
        -Path (Join-Path $RoundDir "round.yaml") `
        -Value $RoundYaml `
        -Encoding UTF8

    @"
# $RoundId — Prompt

Pending.
"@ |
        Set-Content `
            -Path (Join-Path $RoundDir "prompt.md") `
            -Encoding UTF8

    @"
# $RoundId — Proposal

Pending.
"@ |
        Set-Content `
            -Path (Join-Path $RoundDir "proposal.md") `
            -Encoding UTF8

    @"
# $RoundId — PO Notes

Pending.
"@ |
        Set-Content `
            -Path (Join-Path $RoundDir "po-notes.md") `
            -Encoding UTF8

    @"
# $RoundId — Consolidated

Pending.
"@ |
        Set-Content `
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
        [ValidateSet('claude','gemini')]
        [string]$Auditor,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"

    $BlindClosed = Get-Content $YamlPath -Raw

    if ($BlindClosed -match '(?m)^\s{2}blind_review_closed:\s+true\s*$') {
        throw "Blind review is already closed."
    }

    $CurrentStatus = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section blind_review `
        -Member $Auditor

    if ($CurrentStatus -ne "pending") {
        throw "Blind response for $Auditor is not pending. Refusing silent overwrite."
    }

    Test-AadoBlindResponseContent -Content $Content | Out-Null

    $ResponsePath = Join-Path $RoundDir "blind-$Auditor.md"

    if (Test-Path $ResponsePath) {
        throw "Blind response file already exists."
    }

    $Now = Get-AadoTimestamp

    Set-Content `
        -Path $ResponsePath `
        -Value $Content `
        -Encoding UTF8

    Set-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section blind_review `
        -Member $Auditor `
        -Status completed

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
        [string]$Content
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"
    $ResponsePath = Join-Path $RoundDir "implementer-response.md"

    $CrossClaude = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section cross_review `
        -Member claude

    $CrossGemini = Get-AadoPhaseMemberStatus `
        -YamlPath $YamlPath `
        -Section cross_review `
        -Member gemini

    if ($CrossClaude -ne "completed" -or $CrossGemini -ne "completed") {
        throw "Both cross reviews must be completed before implementer response."
    }

    $Yaml = Get-Content $YamlPath -Raw

    if ($Yaml -notmatch '(?m)^\s{2}implementer_response:\s+pending\s*$') {
        throw "Implementer response is not pending. Refusing silent overwrite."
    }

    if (Test-Path $ResponsePath) {
        throw "Implementer response file already exists."
    }

    ConvertFrom-AadoImplementerFindings -Content $Content | Out-Null

    $Now = Get-AadoTimestamp

    Set-Content `
        -Path $ResponsePath `
        -Value $Content `
        -Encoding UTF8

    $Yaml = Get-Content $YamlPath -Raw

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})implementer_response:\s+pending\s*$',
        '${1}implementer_response: completed',
        1
    )

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

    if ($Yaml -notmatch '(?m)^\s{2}implementer_response:\s+completed\s*$') {
        throw "Implementer response must be completed before PO Digest."
    }

    if ($Yaml -notmatch '(?m)^\s{2}po_digest:\s+pending\s*$') {
        throw "PO Digest is not pending. Refusing silent overwrite."
    }

    if (Test-Path $DigestPath) {
        throw "PO Digest file already exists."
    }

    $Content = Get-Content $ImplementerPath -Raw

    $Findings = @(
        ConvertFrom-AadoImplementerFindings -Content $Content
    )

    $Blocking = @(
        $Findings |
        Where-Object MergeGate -eq "BLOCK"
    )

    $GateStatus = if ($Blocking.Count -gt 0) {
        "BLOCKED"
    }
    else {
        "CLEAR"
    }

    $Now = Get-AadoTimestamp

    $Digest = [System.Collections.Generic.List[string]]::new()

    $Digest.Add("# $RoundId — PO Digest")
    $Digest.Add("")
    $Digest.Add("Generated at: $Now")
    $Digest.Add("Generation mode: deterministic")
    $Digest.Add("")
    $Digest.Add("## MERGE GATE")
    $Digest.Add("")
    $Digest.Add("MERGE GATE: $GateStatus")
    $Digest.Add("Blocking findings: $($Blocking.Count)")
    $Digest.Add("")
    $Digest.Add("## Resumen")
    $Digest.Add("")
    $Digest.Add("Total findings: $($Findings.Count)")
    $Digest.Add("OPEN: $(@($Findings | Where-Object Resolution -eq 'OPEN').Count)")
    $Digest.Add("VERIFIED: $(@($Findings | Where-Object Resolution -eq 'VERIFIED').Count)")
    $Digest.Add("NOT_APPLICABLE: $(@($Findings | Where-Object Resolution -eq 'NOT_APPLICABLE').Count)")
    $Digest.Add("")

    if ($Blocking.Count -gt 0) {
        $Digest.Add("## Bloqueos")
        $Digest.Add("")

        foreach ($Item in $Blocking) {
            $Digest.Add(
                "- $($Item.Finding) — $($Item.Severity) — $($Item.Disposition) — $($Item.Resolution)"
            )
        }

        $Digest.Add("")
    }

    $Digest.Add("## Todos los findings")
    $Digest.Add("")

    foreach ($Item in $Findings) {
        $Digest.Add(
            "- $($Item.Finding) — Severity=$($Item.Severity) — Disposition=$($Item.Disposition) — Resolution=$($Item.Resolution) — MergeGate=$($Item.MergeGate)"
        )
    }

    $Digest.Add("")
    $Digest.Add("## Regla")
    $Digest.Add("")
    $Digest.Add(
        "ACCEPTED significa que el implementador acepta el hallazgo; no significa que esté resuelto."
    )
    $Digest.Add(
        "Sólo Resolution=VERIFIED acredita una corrección objetivamente verificada."
    )
    $Digest.Add(
        "APPROVED_FOR_MERGE sólo puede registrarse cuando MERGE GATE=CLEAR."
    )

    Set-Content `
        -Path $DigestPath `
        -Value $Digest `
        -Encoding UTF8

    $Yaml = Get-Content $YamlPath -Raw

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})po_digest:\s+pending\s*$',
        '${1}po_digest: completed',
        1
    )

    $Yaml = Set-AadoTopLevelSectionFieldValue `
        -YamlText $Yaml `
        -Section merge_gate `
        -Field status `
        -Value $GateStatus

    $Yaml = Set-AadoTopLevelSectionFieldValue `
        -YamlText $Yaml `
        -Section merge_gate `
        -Field blocking_findings `
        -Value ([string]$Blocking.Count)

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
        RoundId          = $RoundId
        DigestFile       = $DigestPath
        TotalFindings    = $Findings.Count
        BlockingFindings = $Blocking.Count
        MergeGate        = $GateStatus
        Phase            = "completed"
        UpdatedAt        = $Now
    }
}

function Set-AadoPublicationMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId,

        [Parameter(Mandatory = $true)]
        [string]$Branch,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string]$Commit,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^https://github\.com/.+/.+/pull/\d+$')]
        [string]$PrUrl,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 2147483647)]
        [int]$PrNumber,

        [Parameter(Mandatory = $true)]
        [ValidateSet('clean','conflicts','unknown')]
        [string]$Mergeability
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"

    $Yaml = Get-Content $YamlPath -Raw

    if (
        $Yaml -notmatch
        '(?m)^\s{2}po_digest:\s+completed\s*$'
    ) {
        throw "PO Digest must be completed before publication metadata."
    }

    if (
        $Yaml -match
        '(?m)^\s{2}branch:\s+(?!null\s*$).+$'
    ) {
        throw "Publication metadata already exists. Refusing silent overwrite."
    }

    $Now = Get-AadoTimestamp

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})branch:\s+null\s*$',
        '${1}branch: "' + $Branch + '"',
        1
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})commit:\s+null\s*$',
        '${1}commit: "' + $Commit.ToLowerInvariant() + '"',
        1
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})pr_url:\s+null\s*$',
        '${1}pr_url: "' + $PrUrl + '"',
        1
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})pr_number:\s+null\s*$',
        '${1}pr_number: ' + $PrNumber,
        1
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})mergeability:\s+null\s*$',
        '${1}mergeability: "' + $Mergeability + '"',
        1
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^(\s{2})checked_at:\s+null\s*$',
        '${1}checked_at: "' + $Now + '"',
        1
    )

    $Yaml = [regex]::Replace(
        $Yaml,
        '(?m)^updated_at:\s*".*?"\s*$',
        'updated_at: "' + $Now + '"'
    )

    Set-Content `
        -Path $YamlPath `
        -Value $Yaml `
        -Encoding UTF8

    return [pscustomobject]@{
        RoundId      = $RoundId
        Branch       = $Branch
        Commit       = $Commit.ToLowerInvariant()
        PrNumber     = $PrNumber
        PrUrl        = $PrUrl
        Mergeability = $Mergeability
        CheckedAt    = $Now
    }
}


function Set-AadoPODecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^R\d{4}$')]
        [string]$RoundId,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'APPROVED_FOR_MERGE',
            'CHANGES_REQUESTED',
            'REJECTED'
        )]
        [string]$Decision,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{40}$')]
        [string]$ExpectedCommit,

        [string]$Note = ""
    )

    $RoundDir = Get-AadoRoundDirectory -RoundId $RoundId
    $YamlPath = Join-Path $RoundDir "round.yaml"
    $DecisionPath = Join-Path $RoundDir "po-decision.md"

    $Yaml = Get-Content $YamlPath -Raw

    $CurrentDecision = Get-AadoTopLevelSectionFieldValue `
        -YamlText $Yaml `
        -Section po_decision `
        -Field status

    if ($CurrentDecision -ne "pending") {
        throw "PO decision is not pending. Refusing silent overwrite."
    }

    $PublishedCommitRaw = Get-AadoTopLevelSectionFieldValue `
        -YamlText $Yaml `
        -Section publication `
        -Field commit

    if ($PublishedCommitRaw -eq "null") {
        throw "Published commit is missing."
    }

    $PublishedCommit = $PublishedCommitRaw.Trim('"').ToLowerInvariant()
    $Expected = $ExpectedCommit.ToLowerInvariant()

    if ($PublishedCommit -ne $Expected) {
        throw "Expected commit does not match published commit. Approval blocked."
    }

    if ($Decision -eq "APPROVED_FOR_MERGE") {

        $MergeabilityRaw = Get-AadoTopLevelSectionFieldValue `
            -YamlText $Yaml `
            -Section publication `
            -Field mergeability

        $Mergeability = $MergeabilityRaw.Trim('"')

        if ($Mergeability -ne "clean") {
            throw "Mergeability is not clean. Approval blocked."
        }

        $Gate = Get-AadoTopLevelSectionFieldValue `
            -YamlText $Yaml `
            -Section merge_gate `
            -Field status

        if ($Gate -ne "CLEAR") {
            throw "Merge gate is not CLEAR. Approval blocked."
        }
    }

    if (Test-Path $DecisionPath) {
        throw "po-decision.md already exists."
    }

    $Now = Get-AadoTimestamp

    if ($Decision -eq "APPROVED_FOR_MERGE") {
        $CommitLabel = "Approved commit"
    }
    else {
        $CommitLabel = "Commit at decision time"
    }

    $DecisionText = @(
        "# $RoundId — PO Decision",
        "",
        "Decision: $Decision",
        "${CommitLabel}: $PublishedCommit",
        "Decided at: $Now",
        "",
        "Note:",
        $Note
    )

    Set-Content `
        -Path $DecisionPath `
        -Value $DecisionText `
        -Encoding UTF8

    $Yaml = Set-AadoTopLevelSectionFieldValue `
        -YamlText $Yaml `
        -Section po_decision `
        -Field status `
        -Value "`"$Decision`""

    $Yaml = Set-AadoTopLevelSectionFieldValue `
        -YamlText $Yaml `
        -Section po_decision `
        -Field decided_at `
        -Value "`"$Now`""

    if ($Decision -eq "APPROVED_FOR_MERGE") {
        $Yaml = Set-AadoTopLevelSectionFieldValue `
            -YamlText $Yaml `
            -Section po_decision `
            -Field approved_commit `
            -Value "`"$PublishedCommit`""
    }

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
        RoundId         = $RoundId
        Decision        = $Decision
        PublishedCommit = $PublishedCommit
        ApprovedCommit  = if ($Decision -eq "APPROVED_FOR_MERGE") {
            $PublishedCommit
        }
        else {
            $null
        }
        DecisionFile    = $DecisionPath
        DecidedAt       = $Now
    }
}


function Get-AadoTopLevelSectionFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$YamlText,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Field
    )

    $Lines = @([regex]::Split($YamlText, '\r?\n'))

    $SectionIndex = -1
    $EndIndex = $Lines.Count

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match ('^' + [regex]::Escape($Section) + ':\s*$')) {
            if ($SectionIndex -ne -1) {
                throw "Duplicate top-level section: $Section"
            }

            $SectionIndex = $i
            continue
        }

        if (
            $SectionIndex -ne -1 -and
            $i -gt $SectionIndex -and
            $Lines[$i] -match '^[A-Za-z_][A-Za-z0-9_-]*:\s*.*$'
        ) {
            $EndIndex = $i
            break
        }
    }

    if ($SectionIndex -eq -1) {
        throw "Top-level section not found: $Section"
    }

    $Pattern = '^\s{2}' + [regex]::Escape($Field) + ':\s*(.*?)\s*$'
    $MatchesFound = @()

    for ($i = $SectionIndex + 1; $i -lt $EndIndex; $i++) {
        if ($Lines[$i] -match $Pattern) {
            $MatchesFound += $Matches[1]
        }
    }

    if ($MatchesFound.Count -ne 1) {
        throw "Expected exactly one $Section.$Field field; found $($MatchesFound.Count)."
    }

    return $MatchesFound[0].Trim()
}


function Set-AadoTopLevelSectionFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$YamlText,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Field,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $Lines = @([regex]::Split($YamlText, '\r?\n'))

    $SectionIndex = -1
    $EndIndex = $Lines.Count

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match ('^' + [regex]::Escape($Section) + ':\s*$')) {
            if ($SectionIndex -ne -1) {
                throw "Duplicate top-level section: $Section"
            }

            $SectionIndex = $i
            continue
        }

        if (
            $SectionIndex -ne -1 -and
            $i -gt $SectionIndex -and
            $Lines[$i] -match '^[A-Za-z_][A-Za-z0-9_-]*:\s*.*$'
        ) {
            $EndIndex = $i
            break
        }
    }

    if ($SectionIndex -eq -1) {
        throw "Top-level section not found: $Section"
    }

    $Pattern = '^\s{2}' + [regex]::Escape($Field) + ':\s*.*$'
    $Found = @()

    for ($i = $SectionIndex + 1; $i -lt $EndIndex; $i++) {
        if ($Lines[$i] -match $Pattern) {
            $Found += $i
        }
    }

    if ($Found.Count -ne 1) {
        throw "Expected exactly one $Section.$Field field; found $($Found.Count)."
    }

    $Lines[$Found[0]] = "  ${Field}: $Value"

    return ($Lines -join "`r`n")
}


function Test-AadoBlindResponseContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $Lines = @([regex]::Split($Content, '\r?\n'))

    $FindingIndexes = @()

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^FINDING\s+(.+?)\s*$') {
            $FindingIndexes += $i
        }
    }

    if ($FindingIndexes.Count -eq 0) {
        throw "Blind response invalid: no FINDING blocks found."
    }

    $AllowedSeverity = @(
        "BLOCKER",
        "HIGH",
        "MEDIUM",
        "LOW",
        "OPPORTUNITY"
    )

    $AllowedType = @(
        "bug",
        "security",
        "integrity",
        "architecture",
        "test-gap",
        "usability"
    )

    for ($n = 0; $n -lt $FindingIndexes.Count; $n++) {

        $Start = $FindingIndexes[$n]

        if ($n -lt ($FindingIndexes.Count - 1)) {
            $End = $FindingIndexes[$n + 1] - 1
        }
        else {
            $End = $Lines.Count - 1
        }

        $Block = @($Lines[$Start..$End]) -join "`n"

        $FindingId = $null

        if ($Lines[$Start] -match '^FINDING\s+(.+?)\s*$') {
            $FindingId = $Matches[1].Trim()
        }

        if ($Block -notmatch '(?m)^Severity:\s*(BLOCKER|HIGH|MEDIUM|LOW|OPPORTUNITY)\s*$') {
            throw "Blind response invalid: FINDING $FindingId has no valid Severity."
        }

        if ($Block -notmatch '(?m)^Type:\s*(bug|security|integrity|architecture|test-gap|usability)\s*$') {
            throw "Blind response invalid: FINDING $FindingId has no valid Type."
        }

        foreach ($Required in @("Evidence:", "Impact:", "Recommendation:")) {
            if ($Block -notmatch ('(?m)^' + [regex]::Escape($Required) + '\s*$')) {
                throw "Blind response invalid: FINDING $FindingId missing $Required"
            }
        }
    }

    return $true
}


function ConvertFrom-AadoImplementerFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $AllowedSeverity = @(
        "BLOCKER",
        "HIGH",
        "MEDIUM",
        "LOW",
        "OPPORTUNITY"
    )

    $AllowedDisposition = @(
        "ACCEPTED",
        "REJECTED",
        "DEFERRED",
        "NEEDS_PO",
        "NEEDS_TEST"
    )

    $AllowedResolution = @(
        "OPEN",
        "VERIFIED",
        "NOT_APPLICABLE"
    )

    $AllowedMergeGate = @(
        "BLOCK",
        "CLEAR"
    )

    $Lines = @([regex]::Split($Content, '\r?\n'))

    $Findings = [System.Collections.Generic.List[object]]::new()

    $CurrentId = $null
    $CurrentSeverity = $null
    $CurrentDisposition = $null
    $CurrentResolution = $null
    $CurrentMergeGate = $null

    foreach ($Line in $Lines) {

        if ($Line -match '^FINDING\s+(.+?)\s*$') {

            if ($CurrentId) {

                if (-not $CurrentSeverity) {
                    throw "FINDING $CurrentId has no Severity before next FINDING."
                }

                if (-not $CurrentDisposition) {
                    throw "FINDING $CurrentId has no Disposition before next FINDING."
                }

                if (-not $CurrentResolution) {
                    throw "FINDING $CurrentId has no Resolution before next FINDING."
                }

                if (-not $CurrentMergeGate) {
                    throw "FINDING $CurrentId has no MergeGate before next FINDING."
                }

                $Findings.Add(
                    [pscustomobject]@{
                        Finding     = $CurrentId
                        Severity    = $CurrentSeverity
                        Disposition = $CurrentDisposition
                        Resolution  = $CurrentResolution
                        MergeGate   = $CurrentMergeGate
                    }
                )
            }

            $CurrentId = $Matches[1].Trim()
            $CurrentSeverity = $null
            $CurrentDisposition = $null
            $CurrentResolution = $null
            $CurrentMergeGate = $null

            continue
        }

        if (-not $CurrentId) {
            continue
        }

        if ($Line -match '^Severity:\s*(.+?)\s*$') {

            $Value = $Matches[1].Trim()

            if ($AllowedSeverity -notcontains $Value) {
                throw "Invalid Severity for FINDING ${CurrentId}: $Value"
            }

            $CurrentSeverity = $Value
            continue
        }

        if ($Line -match '^Disposition:\s*(.+?)\s*$') {

            $Value = $Matches[1].Trim()

            if ($AllowedDisposition -notcontains $Value) {
                throw "Invalid Disposition for FINDING ${CurrentId}: $Value"
            }

            $CurrentDisposition = $Value
            continue
        }

        if ($Line -match '^Resolution:\s*(.+?)\s*$') {

            $Value = $Matches[1].Trim()

            if ($AllowedResolution -notcontains $Value) {
                throw "Invalid Resolution for FINDING ${CurrentId}: $Value"
            }

            $CurrentResolution = $Value
            continue
        }

        if ($Line -match '^MergeGate:\s*(.+?)\s*$') {

            $Value = $Matches[1].Trim()

            if ($AllowedMergeGate -notcontains $Value) {
                throw "Invalid MergeGate for FINDING ${CurrentId}: $Value"
            }

            $CurrentMergeGate = $Value
            continue
        }
    }

    if ($CurrentId) {

        if (-not $CurrentSeverity) {
            throw "FINDING $CurrentId has no Severity."
        }

        if (-not $CurrentDisposition) {
            throw "FINDING $CurrentId has no Disposition."
        }

        if (-not $CurrentResolution) {
            throw "FINDING $CurrentId has no Resolution."
        }

        if (-not $CurrentMergeGate) {
            throw "FINDING $CurrentId has no MergeGate."
        }

        $Findings.Add(
            [pscustomobject]@{
                Finding     = $CurrentId
                Severity    = $CurrentSeverity
                Disposition = $CurrentDisposition
                Resolution  = $CurrentResolution
                MergeGate   = $CurrentMergeGate
            }
        )
    }

    if ($Findings.Count -eq 0) {
        throw "No structured implementer FINDING blocks found."
    }

    $Duplicates = @(
        $Findings |
        Group-Object Finding |
        Where-Object Count -gt 1
    )

    if ($Duplicates.Count -gt 0) {
        throw "Duplicate finding IDs: $($Duplicates.Name -join ', ')"
    }

    return @($Findings)
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
    "Build-AadoPODigest",
    "Set-AadoPublicationMetadata",
    "Set-AadoPODecision"
)








