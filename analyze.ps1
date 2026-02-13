$a = (Get-Content 'C:\Users\rumba\Disaster Lab Projects\fema_approved.json' | ConvertFrom-Json).FemaWebDisasterDeclarations
$d = (Get-Content 'C:\Users\rumba\Disaster Lab Projects\fema_denied.json' | ConvertFrom-Json).DeclarationDenials

Write-Host "=== APPROVED (non-FM, 2025+) ==="
Write-Host "Total raw records: $($a.Count)"

# Unique disasters
$uniq = $a | Select-Object -ExpandProperty disasterNumber -Unique
Write-Host "Unique disaster numbers: $($uniq.Count)"
Write-Host "Duplicates removed by disasterNumber dedup: $($a.Count - $uniq.Count)"

# Missing request dates
$noReq = @($a | Where-Object { [string]::IsNullOrEmpty($_.declarationRequestDate) })
Write-Host "Missing declarationRequestDate: $($noReq.Count)"
foreach ($r in $noReq) {
    Write-Host "  - #$($r.disasterNumber) $($r.disasterName) [$($r.stateName)]"
}

# Missing declaration dates
$noDec = @($a | Where-Object { [string]::IsNullOrEmpty($_.declarationDate) })
Write-Host "Missing declarationDate: $($noDec.Count)"

# Processing time analysis
$times = @()
foreach ($r in $a) {
    if ($r.declarationRequestDate -and $r.declarationDate) {
        $req = [datetime]$r.declarationRequestDate
        $dec = [datetime]$r.declarationDate
        $days = ($dec - $req).Days
        $times += [PSCustomObject]@{
            Number = $r.disasterNumber
            Name = $r.disasterName
            State = ($r.stateName -replace '\s+$','')
            Days = $days
            ReqDate = $r.declarationRequestDate.Substring(0,10)
            DecDate = $r.declarationDate.Substring(0,10)
        }
    }
}

$negative = @($times | Where-Object { $_.Days -lt 0 })
Write-Host "Negative processing time: $($negative.Count)"
foreach ($r in $negative) {
    Write-Host "  - #$($r.Number) $($r.Name) $($r.State) req:$($r.ReqDate) dec:$($r.DecDate) = $($r.Days) days"
}

$zero = @($times | Where-Object { $_.Days -eq 0 })
Write-Host "Zero-day processing (same day): $($zero.Count)"
foreach ($r in $zero) {
    Write-Host "  - #$($r.Number) $($r.Name) $($r.State)"
}

# Dedup collision check
$dedupHash = @{}
foreach ($r in $a) {
    $state = ($r.stateName -replace '\s+$','')
    $key = "$state-$($r.disasterName)-$($r.declarationRequestDate)"
    if (-not $dedupHash.ContainsKey($key)) { $dedupHash[$key] = [System.Collections.ArrayList]@() }
    [void]$dedupHash[$key].Add($r.disasterNumber)
}
Write-Host "After state+title+requestDate dedup: $($dedupHash.Count)"
$collisions = 0
foreach ($entry in $dedupHash.GetEnumerator()) {
    $uniqueNums = $entry.Value | Select-Object -Unique
    if (@($uniqueNums).Count -gt 1) {
        $collisions++
        Write-Host "  WARNING merges different disasters: $($entry.Key) -> $($uniqueNums -join ', ')"
    }
}
if ($collisions -eq 0) { Write-Host "  No dedup collisions found" }

Write-Host ""
Write-Host "=== DENIED (2025+) ==="
Write-Host "Total records: $($d.Count)"

$dNoReq = @($d | Where-Object { [string]::IsNullOrEmpty($_.declarationRequestDate) })
Write-Host "Missing declarationRequestDate: $($dNoReq.Count)"

$dNoStatus = @($d | Where-Object { [string]::IsNullOrEmpty($_.requestStatusDate) })
Write-Host "Missing requestStatusDate: $($dNoStatus.Count)"
foreach ($r in $dNoStatus) {
    $state = ($r.state -replace '\s+$','')
    $name = ($r.incidentName -replace '\s+$','')
    Write-Host "  - #$($r.declarationRequestNumber) $name [$state]"
}

$dTimes = @()
foreach ($r in $d) {
    if ($r.declarationRequestDate -and $r.requestStatusDate) {
        $req = [datetime]$r.declarationRequestDate
        $stat = [datetime]$r.requestStatusDate
        $days = ($stat - $req).Days
        $state = ($r.state -replace '\s+$','')
        $name = ($r.incidentName -replace '\s+$','')
        $dTimes += [PSCustomObject]@{
            Number = $r.declarationRequestNumber
            Name = $name
            State = $state
            Days = $days
            ReqDate = $r.declarationRequestDate.Substring(0,10)
            StatusDate = $r.requestStatusDate.Substring(0,10)
            Status = $r.currentRequestStatus
        }
    }
}

$dNeg = @($dTimes | Where-Object { $_.Days -lt 0 })
Write-Host "Negative processing time: $($dNeg.Count)"
foreach ($r in $dNeg) {
    Write-Host "  - #$($r.Number) $($r.Name) [$($r.State)] req:$($r.ReqDate) status:$($r.StatusDate) = $($r.Days) days"
}

$dZero = @($dTimes | Where-Object { $_.Days -eq 0 })
Write-Host "Zero-day processing: $($dZero.Count)"

# Status breakdown
$statuses = @{}
foreach ($r in $d) {
    $s = $r.currentRequestStatus
    if ($statuses.ContainsKey($s)) { $statuses[$s]++ } else { $statuses[$s] = 1 }
}
Write-Host "Status breakdown:"
foreach ($entry in $statuses.GetEnumerator()) {
    Write-Host "  $($entry.Key): $($entry.Value)"
}

Write-Host ""
Write-Host "=== SUMMARY ==="
$avgApproved = ($times | Measure-Object -Property Days -Average).Average
$avgDenied = ($dTimes | Measure-Object -Property Days -Average).Average
Write-Host "Avg processing days (approved): $([math]::Round($avgApproved, 1))"
Write-Host "Avg processing days (denied): $([math]::Round($avgDenied, 1))"
Write-Host "Records that would show in dashboard (after approved dedup): $($dedupHash.Count + $d.Count)"
