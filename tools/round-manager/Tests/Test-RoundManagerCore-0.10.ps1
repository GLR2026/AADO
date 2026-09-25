$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$CorePath = Join-Path $PSScriptRoot "..\RoundManagerCore.psm1"
$CorePath = [System.IO.Path]::GetFullPath($CorePath)

$OriginalRootEnv = $env:AADO_REPO_ROOT
$RunId = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$SandboxRoot = Join-Path "C:\AADO_PRIVATE\tests\round-manager" $RunId
$script:PassCount = 0
$script:ExpectedPasses = 10
$Success = $false

function Pass-Test {
    param([string]$Message)
    $script:PassCount++
    Write-Host ("PASS {0:D2}: {1}" -f $script:PassCount, $Message)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Assert-ThrowsLike {
    param([scriptblock]$Action, [string]$Pattern, [string]$Message)
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Wrong exception for '$Message': $($_.Exception.Message)"
        }
        return
    }
    throw "Expected exception was not thrown: $Message"
}

try {
    New-Item -ItemType Directory -Force -Path $SandboxRoot | Out-Null
    $env:AADO_REPO_ROOT = $SandboxRoot

    Remove-Module RoundManagerCore -ErrorAction SilentlyContinue
    Import-Module $CorePath -Force -ErrorAction Stop

    Write-Host ""
    Write-Host "Sandbox: $SandboxRoot"
    Write-Host ""

    $R1 = New-AadoRound -Title "Regression blocked path" -Category testing
    Assert-True ($R1.RoundId -eq "R0001") "sandbox first round must be R0001"

    Save-AadoProposal -RoundId R0001 -Content "Regression test proposal." | Out-Null

    Assert-ThrowsLike -Action {
        Save-AadoBlindResponse -RoundId R0001 -Auditor claude -Content "Unstructured auditor response." | Out-Null
    } -Pattern "no FINDING blocks found" -Message "invalid blind response"

    $R1YamlPath = Join-Path $SandboxRoot "audits\rounds\R0001\round.yaml"
    $ClaudeStatus = Get-AadoPhaseMemberStatus -YamlPath $R1YamlPath -Section blind_review -Member claude
    Assert-True ($ClaudeStatus -eq "pending") "invalid blind must not advance phase"
    Pass-Test "INVALID BLIND -> BLOCK"

    $ClaudeBlind = "FINDING C-001`r`nSeverity: HIGH`r`nType: integrity`r`nEvidence:`r`nStructured evidence.`r`nImpact:`r`nMaterial impact.`r`nRecommendation:`r`nUse deterministic validation."
    $GeminiBlind = "FINDING G-001`r`nSeverity: MEDIUM`r`nType: test-gap`r`nEvidence:`r`nPositive and negative paths require testing.`r`nImpact:`r`nRegression could otherwise pass unnoticed.`r`nRecommendation:`r`nRun repeatable regression tests."

    Save-AadoBlindResponse -RoundId R0001 -Auditor claude -Content $ClaudeBlind | Out-Null
    Save-AadoBlindResponse -RoundId R0001 -Auditor gemini -Content $GeminiBlind | Out-Null
    Close-AadoBlindPhase -RoundId R0001 | Out-Null

    Save-AadoCrossReview -RoundId R0001 -Auditor claude -Content "AGREE - G-001" | Out-Null
    Save-AadoCrossReview -RoundId R0001 -Auditor gemini -Content "AGREE - C-001" | Out-Null

    $BadEnum = "FINDING BAD-ENUM`r`nSeverity: BANANA`r`nDisposition: ACCEPTED`r`nResolution: OPEN`r`nMergeGate: BLOCK"
    Assert-ThrowsLike -Action {
        Save-AadoImplementerResponse -RoundId R0001 -Content $BadEnum | Out-Null
    } -Pattern "Invalid Severity" -Message "invalid severity enum"
    Pass-Test "INVALID ENUM -> BLOCK"

    $Incomplete = "FINDING T-001`r`nSeverity: HIGH`r`nDisposition: ACCEPTED`r`nResolution: OPEN`r`nMergeGate: BLOCK`r`n`r`nFINDING T-002`r`nSeverity: MEDIUM`r`nDisposition: ACCEPTED`r`nResolution: OPEN"
    Assert-ThrowsLike -Action {
        Save-AadoImplementerResponse -RoundId R0001 -Content $Incomplete | Out-Null
    } -Pattern "T-002 has no MergeGate" -Message "incomplete finding"
    Pass-Test "INCOMPLETE FINDING -> BLOCK"

    $ValidBlocked = "FINDING T-001`r`nSeverity: HIGH`r`nDisposition: ACCEPTED`r`nResolution: OPEN`r`nMergeGate: BLOCK`r`n`r`nFINDING T-002`r`nSeverity: MEDIUM`r`nDisposition: ACCEPTED`r`nResolution: VERIFIED`r`nMergeGate: CLEAR"
    Save-AadoImplementerResponse -RoundId R0001 -Content $ValidBlocked | Out-Null
    Pass-Test "MULTI FINDING -> PASS"

    $D1 = Build-AadoPODigest -RoundId R0001
    Assert-True ($D1.MergeGate -eq "BLOCKED") "accepted open finding must block merge"
    Assert-True ($D1.BlockingFindings -eq 1) "exactly one finding should block"
    Pass-Test "ACCEPTED + OPEN -> MERGE BLOCKED"

    $FakeCommit1 = "1111111111111111111111111111111111111111"
    Set-AadoPublicationMetadata -RoundId R0001 -Branch "synthetic/blocked" -Commit $FakeCommit1 -PrUrl "https://github.com/GLR2026/AADO/pull/9991" -PrNumber 1 -Mergeability clean | Out-Null

    Assert-ThrowsLike -Action {
        Set-AadoPODecision -RoundId R0001 -Decision APPROVED_FOR_MERGE -ExpectedCommit $FakeCommit1 -Note "Must fail." | Out-Null
    } -Pattern "Merge gate is not CLEAR" -Message "approval through blocked gate"

    Assert-True (-not (Test-Path (Join-Path $SandboxRoot "audits\rounds\R0001\po-decision.md"))) "failed approval must not create decision file"
    Pass-Test "APPROVED + BLOCKED -> BLOCK"

    $Yaml = Get-Content $R1YamlPath -Raw
    $PoIndex = $Yaml.IndexOf("po_decision:")
    if ($PoIndex -lt 0) { throw "po_decision section not found" }

    $Decoy = "decoy_test:`r`n  status: pending`r`n  purpose: regression_scope_test`r`n`r`n"
    $Yaml = $Yaml.Substring(0, $PoIndex) + $Decoy + $Yaml.Substring($PoIndex)
    Set-Content -Path $R1YamlPath -Value $Yaml -Encoding UTF8

    Set-AadoPODecision -RoundId R0001 -Decision CHANGES_REQUESTED -ExpectedCommit $FakeCommit1 -Note "Blocked gate should permit changes requested." | Out-Null

    $Yaml = Get-Content $R1YamlPath -Raw
    $DecoyMatch = [regex]::Match($Yaml, "(?ms)^decoy_test:\s*\r?\n(?<body>(?:^\s{2}.+\r?\n?)*)")
    Assert-True $DecoyMatch.Success "decoy section must still exist"
    Assert-True ($DecoyMatch.Groups["body"].Value -match "(?m)^\s{2}status:\s+pending\s*$") "decoy status must remain pending"
    Pass-Test "DECOY STATUS -> PO SECTION ONLY"

    $DecisionText = Get-Content (Join-Path $SandboxRoot "audits\rounds\R0001\po-decision.md") -Raw
    Assert-True ($DecisionText -match "Decision:\s+CHANGES_REQUESTED") "changes requested decision must be persisted"
    Pass-Test "CHANGES_REQUESTED + BLOCKED -> PASS"

    $R2 = New-AadoRound -Title "Regression clear path" -Category testing
    Assert-True ($R2.RoundId -eq "R0002") "sandbox second round must be R0002"

    Save-AadoProposal -RoundId R0002 -Content "Positive path." | Out-Null
    Save-AadoBlindResponse -RoundId R0002 -Auditor claude -Content $ClaudeBlind | Out-Null
    Save-AadoBlindResponse -RoundId R0002 -Auditor gemini -Content $GeminiBlind | Out-Null
    Close-AadoBlindPhase -RoundId R0002 | Out-Null

    Save-AadoCrossReview -RoundId R0002 -Auditor claude -Content "AGREE - G-001" | Out-Null
    Save-AadoCrossReview -RoundId R0002 -Auditor gemini -Content "AGREE - C-001" | Out-Null

    $ValidClear = "FINDING T-101`r`nSeverity: HIGH`r`nDisposition: ACCEPTED`r`nResolution: VERIFIED`r`nMergeGate: CLEAR`r`n`r`nFINDING T-102`r`nSeverity: MEDIUM`r`nDisposition: ACCEPTED`r`nResolution: VERIFIED`r`nMergeGate: CLEAR"
    Save-AadoImplementerResponse -RoundId R0002 -Content $ValidClear | Out-Null

    $D2 = Build-AadoPODigest -RoundId R0002
    Assert-True ($D2.MergeGate -eq "CLEAR") "verified findings must produce clear gate"
    Assert-True ($D2.BlockingFindings -eq 0) "clear path must have zero blockers"
    Pass-Test "ALL VERIFIED -> MERGE CLEAR"

    $FakeCommit2 = "2222222222222222222222222222222222222222"
    Set-AadoPublicationMetadata -RoundId R0002 -Branch "synthetic/clear" -Commit $FakeCommit2 -PrUrl "https://github.com/GLR2026/AADO/pull/9992" -PrNumber 2 -Mergeability clean | Out-Null

    $Decision = Set-AadoPODecision -RoundId R0002 -Decision APPROVED_FOR_MERGE -ExpectedCommit $FakeCommit2 -Note "Positive regression path."
    Assert-True ($Decision.ApprovedCommit -eq $FakeCommit2) "approved commit must equal expected commit"
    Pass-Test "APPROVED + CLEAR -> PASS"

    Assert-True ($script:PassCount -eq $script:ExpectedPasses) "unexpected PASS count"

    Write-Host ""
    Write-Host "=============================================="
    Write-Host "$($script:PassCount)/$($script:ExpectedPasses) PASS"
    Write-Host "ROUND MANAGER CORE 0.10.0: VERIFIED"
    Write-Host "=============================================="

    $Success = $true
}
finally {
    Remove-Module RoundManagerCore -ErrorAction SilentlyContinue

    if ($null -eq $OriginalRootEnv) {
        Remove-Item Env:\AADO_REPO_ROOT -ErrorAction SilentlyContinue
    }
    else {
        $env:AADO_REPO_ROOT = $OriginalRootEnv
    }

    if ($Success -and (Test-Path $SandboxRoot)) {
        Remove-Item -Path $SandboxRoot -Recurse -Force
    }
    elseif (-not $Success) {
        Write-Host ""
        Write-Host "FAILED SANDBOX PRESERVED:"
        Write-Host $SandboxRoot
    }
}

