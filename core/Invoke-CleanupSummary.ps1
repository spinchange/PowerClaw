function ConvertTo-CleanupSummaryNormalizedInput {
    [CmdletBinding()]
    param(
        [object[]]$SearchResults,
        [string]$Scope,
        [datetimeoffset]$CapturedAt = [datetimeoffset]::Now
    )

    [PSCustomObject]@{
        scope = if ([string]::IsNullOrWhiteSpace($Scope)) { [string]$env:USERPROFILE } else { $Scope }
        captured_at = $CapturedAt.ToString('o')
        candidates = @(
            @($SearchResults) |
                Where-Object { $_.Path -or $_.ItemPathDisplay } |
                ForEach-Object {
                    $path = [string]($_.Path ?? $_.ItemPathDisplay)
                    $name = [string]($_.Name ?? $_.ItemName ?? [System.IO.Path]::GetFileName($path))
                    [PSCustomObject]@{
                        name = $name
                        path = $path
                        size_mb = if ($_.PSObject.Properties.Name -contains 'SizeMB') { [math]::Round([double]$_.SizeMB, 2) } elseif ($_.PSObject.Properties.Name -contains 'Size') { [math]::Round(([double]$_.Size / 1MB), 2) } else { 0 }
                        modified_at = if ($_.PSObject.Properties.Name -contains 'DateModified' -and $_.DateModified) { ([datetimeoffset]$_.DateModified).ToString('o') } else { $null }
                    }
                }
        )
    }
}

function Invoke-CleanupSummary {
    [CmdletBinding()]
    param(
        [string]$Scope = "$env:USERPROFILE\Downloads",
        [ValidateRange(1, 25)]
        [int]$Limit = 10,
        [ValidateRange(0, 500000)]
        [int]$MinSizeMB = 50,
        [switch]$AsJson
    )

    $capturedAt = [datetimeoffset]::Now
    $source = $null
    $searchResults = @()

    try {
        $searchResults = @(
            Search-Files -Scope $Scope -Limit $Limit -SortBy Size -MinSizeMB $MinSizeMB -Aggregate:$false
        )
        $source = [PSCustomObject]@{
            id = 'src_search'
            tool = 'Search-Files'
            captured_at = $capturedAt.ToString('o')
            scope = $Scope
        }
    }
    catch {
        $searchResults = @()
    }

    $normalized = ConvertTo-CleanupSummaryNormalizedInput -SearchResults $searchResults -Scope $Scope -CapturedAt $capturedAt
    $document = if ($source) {
        New-CleanupSummaryDocument -NormalizedInput $normalized -Sources @($source)
    } else {
        New-CleanupSummaryDocument -NormalizedInput $normalized
    }

    if ($AsJson) {
        return $document | ConvertTo-Json -Depth 10
    }

    return $document
}

function New-CleanupSummaryDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$NormalizedInput,

        [object[]]$Sources
    )

    function Get-CleanupCategory {
        param([string]$Path)
        $extension = [System.IO.Path]::GetExtension(($Path ?? '')).ToLowerInvariant()
        switch ($extension) {
            { $_ -in @('.log', '.tmp', '.bak', '.old', '.dmp') } { return 'logs' }
            { $_ -in @('.exe', '.msi', '.msix', '.msu', '.iso') } { return 'installer' }
            { $_ -in @('.zip', '.7z', '.rar', '.tar', '.gz', '.bz2') } { return 'archive' }
            { $_ -in @('.mp3', '.wav', '.flac', '.mp4', '.mkv', '.avi', '.mov', '.jpg', '.jpeg', '.png', '.webp') } { return 'media' }
            default { return 'other' }
        }
    }

    function Get-CleanupState {
        param([string]$Category)
        if ($Category -eq 'logs') { return 'execution_allowed' }
        return 'review_only'
    }

    function Get-CleanupStateReason {
        param([string]$Category)
        switch ($Category) {
            'logs' { return 'low_risk_remnant' }
            'installer' { return 'installer_requires_review' }
            'archive' { return 'archive_requires_review' }
            'media' { return 'media_requires_review' }
            default { return 'unclassified_requires_review' }
        }
    }

    function Get-CleanupRationale {
        param([string]$Category)
        switch ($Category) {
            'logs' { return 'Log, temp, dump, or backup-style remnants are usually the strongest cleanup candidates.' }
            'installer' { return 'Installers are often disposable after one-time setup, but may still be part of a normal reinstall path.' }
            'archive' { return 'Archives may be backups or bundled deliverables and should be confirmed as redundant first.' }
            'media' { return 'Media files are often intentional recordings or downloads and should be reviewed before deletion.' }
            default { return 'Uncategorized files should stay review-only until the user identifies them more specifically.' }
        }
    }

    function Get-CleanupRankWeight {
        param([string]$Category)
        switch ($Category) {
            'logs' { return 0 }
            'installer' { return 1 }
            'archive' { return 2 }
            'media' { return 3 }
            default { return 4 }
        }
    }

    $scope = [string]($NormalizedInput.scope ?? $env:USERPROFILE)
    $capturedAt = [string]($NormalizedInput.captured_at ?? ([datetimeoffset]::Now.ToString('o')))
    $sourceList = if ($PSBoundParameters.ContainsKey('Sources')) { @($Sources | Where-Object { $null -ne $_ }) } else { @() }

    if ($sourceList.Count -eq 0 -and @($NormalizedInput.candidates).Count -gt 0) {
        $sourceList = @([PSCustomObject]@{
            id = 'src_search'
            tool = 'Search-Files'
            captured_at = $capturedAt
            scope = $scope
        })
    }

    $candidateDocs = @(
        @($NormalizedInput.candidates) |
            Sort-Object @{
                Expression = { Get-CleanupRankWeight -Category (Get-CleanupCategory -Path ([string]$_.path)) }
            }, @{
                Expression = { -[double]($_.size_mb ?? 0) }
            }, @{
                Expression = { [string]$_.name }
            } |
            Select-Object -First 10 |
            ForEach-Object {
                $category = Get-CleanupCategory -Path ([string]$_.path)
                $state = Get-CleanupState -Category $category
                $stateReason = Get-CleanupStateReason -Category $category
                [PSCustomObject]@{
                    id = "candidate:$([regex]::Replace(([string]$_.name).ToLowerInvariant(), '[^a-z0-9_-]', '_'))"
                    name = [string]$_.name
                    path = [string]$_.path
                    category = $category
                    state = $state
                    state_reason = $stateReason
                    rank = 0
                    size_mb = [math]::Round([double]($_.size_mb ?? 0), 2)
                    modified_at = if ($_.modified_at) { [string]$_.modified_at } else { $null }
                    rationale = Get-CleanupRationale -Category $category
                    evidence = @(
                        "Path: $([string]$_.path)"
                        "Size: $([math]::Round([double]($_.size_mb ?? 0), 2)) MB"
                    )
                    source_refs = @('src_search')
                }
            }
    )

    for ($i = 0; $i -lt $candidateDocs.Count; $i++) {
        $candidateDocs[$i].rank = $i + 1
    }

    $recommendedOrder = @($candidateDocs | Sort-Object rank | ForEach-Object { [string]$_.id })
    $executionAllowedCount = @($candidateDocs | Where-Object state -eq 'execution_allowed').Count
    $status = if ($candidateDocs.Count -eq 0) { 'empty' } elseif ($executionAllowedCount -gt 0) { 'actionable' } else { 'review_only' }
    $headline = switch ($status) {
        'empty' { "No cleanup candidates above the current threshold were found in $scope" }
        'actionable' { "Cleanup candidates were found in $scope, and some low-risk remnants are execution-allowed after confirmation" }
        default { "Cleanup candidates were found in $scope, but they remain review-only until the user is more specific" }
    }
    $nextAction = switch ($status) {
        'empty' {
            [PSCustomObject]@{
                kind = 'expand_scope'
                policy_reason = 'no_candidates_found'
                reason = 'No candidates met the current threshold, so the next step is to widen scope or lower the size filter.'
            }
        }
        'actionable' {
            [PSCustomObject]@{
                kind = 'confirm_delete'
                policy_reason = 'low_risk_candidates_available_after_confirmation'
                reason = 'Review the ranked candidates, then confirm only the low-risk remnants the user actually wants removed.'
            }
        }
        default {
            [PSCustomObject]@{
                kind = 'review_candidates'
                policy_reason = 'specific_user_reference_required'
                reason = 'Review the ranked candidates with the user and ask them to name the specific file or type before any delete action.'
            }
        }
    }

    $document = [PSCustomObject]@{
        schema_version = '1.0'
        kind = 'cleanup_summary'
        scope = $scope
        captured_at = $capturedAt
        summary = [PSCustomObject]@{
            status = $status
            headline = $headline
            candidate_count = $candidateDocs.Count
            execution_allowed_count = $executionAllowedCount
        }
        candidates = @($candidateDocs)
        recommended_order = @($recommendedOrder)
        next_action = $nextAction
        sources = @($sourceList)
    }

    $validation = Test-CleanupSummaryDocument -Document $document
    if (-not $validation.IsValid) {
        throw "Cleanup summary document validation failed: $($validation.Errors -join '; ')"
    }

    return $document
}

function Test-CleanupSummaryDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Document,

        [string]$SchemaPath = (Join-Path $PSScriptRoot '..\docs\cleanup-summary-v1.schema.json')
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $json = $Document | ConvertTo-Json -Depth 10

    try {
        if (-not (Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop)) {
            $errors.Add('Document failed JSON schema validation') | Out-Null
        }
    }
    catch {
        $errors.Add("Schema validation failed: $($_.Exception.Message)") | Out-Null
    }

    $candidateIds = @($Document.candidates | ForEach-Object { [string]$_.id })
    if (@($candidateIds | Select-Object -Unique).Count -ne $candidateIds.Count) {
        $errors.Add('Candidate IDs must be unique') | Out-Null
    }

    foreach ($candidateId in @($Document.recommended_order)) {
        if ($candidateId -notin $candidateIds) {
            $errors.Add("Recommended order id does not resolve: $candidateId") | Out-Null
        }
    }

    if ([int]$Document.summary.candidate_count -ne @($Document.candidates).Count) {
        $errors.Add('Summary candidate_count mismatch') | Out-Null
    }

    $executionAllowedCount = @($Document.candidates | Where-Object state -eq 'execution_allowed').Count
    if ([int]$Document.summary.execution_allowed_count -ne $executionAllowedCount) {
        $errors.Add('Summary execution_allowed_count mismatch') | Out-Null
    }

    $expectedStateReasons = @{
        logs = 'low_risk_remnant'
        installer = 'installer_requires_review'
        archive = 'archive_requires_review'
        media = 'media_requires_review'
        other = 'unclassified_requires_review'
    }

    foreach ($candidate in @($Document.candidates)) {
        $expectedReason = $expectedStateReasons[[string]$candidate.category]
        if ([string]$candidate.state_reason -ne $expectedReason) {
            $errors.Add("Candidate state_reason mismatch for $([string]$candidate.id)") | Out-Null
        }

        if ([string]$candidate.category -eq 'logs' -and [string]$candidate.state -ne 'execution_allowed') {
            $errors.Add("Logs candidate must be execution_allowed: $([string]$candidate.id)") | Out-Null
        }

        if ([string]$candidate.category -ne 'logs' -and [string]$candidate.state -ne 'review_only') {
            $errors.Add("Non-log candidate must be review_only: $([string]$candidate.id)") | Out-Null
        }
    }

    $expectedNextActionPolicyReason = switch ([string]$Document.summary.status) {
        'empty' { 'no_candidates_found' }
        'actionable' { 'low_risk_candidates_available_after_confirmation' }
        'review_only' { 'specific_user_reference_required' }
        default { '' }
    }

    if ([string]$Document.next_action.policy_reason -ne $expectedNextActionPolicyReason) {
        $errors.Add('Next action policy_reason mismatch') | Out-Null
    }

    return [PSCustomObject]@{
        IsValid = $errors.Count -eq 0
        Errors = @($errors)
    }
}
