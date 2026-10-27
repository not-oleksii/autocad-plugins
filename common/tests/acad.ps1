# Test helpers for the plugins' tests/run.ps1, which dot-source this file:
#   Check $ok 'what'                     prints ok/FAIL and collects the failures in $script:failures
#   Invoke-Acad $work $name $script $dwg  runs an AutoCAD script in accoreconsole, on $dwg (a .dwg,
#                                         .dxf or .dwt) or an empty drawing, with a throwaway profile,
#                                         and returns its log
# The script is written as UTF-8 with BOM so Cyrillic survives. $Acad and $Seconds are read from
# the caller's scope.

function Check($ok, $what) {
    if ($ok) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what"; $script:failures += $what }
}

function Invoke-Acad($Work, $Name, $ScriptText, $Dwg) {
    $dir = Join-Path $Work $Name
    New-Item $dir -ItemType Directory -Force | Out-Null
    $scrPath = Join-Path $dir 'run.scr'
    [IO.File]::WriteAllText($scrPath, $ScriptText, (New-Object Text.UTF8Encoding($true)))
    $out = Join-Path $dir 'acad.txt'
    $open = if ($Dwg) { "/i `"$Dwg`" " } else { '' }
    $acadArgs = "$($open)/s `"$scrPath`" /l en-US /isolate plugins$Name `"$(Join-Path $dir 'user')`""
    $p = Start-Process $Acad -ArgumentList $acadArgs -WorkingDirectory $dir -RedirectStandardOutput $out -PassThru -NoNewWindow
    # With /isolate, accoreconsole sometimes never exits after QUIT, so stop it once the script is done.
    $deadline = (Get-Date).AddSeconds($Seconds)
    while (-not $p.WaitForExit(2000)) {
        $sofar = try {
            $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
            try { (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
        } catch { '' }
        if ($sofar -match 'Command: QUIT') { Start-Sleep 5; if (-not $p.HasExited) { $p.Kill() }; break }
        if ((Get-Date) -gt $deadline) { $p.Kill(); $script:failures += "accoreconsole timed out ($Name)"; break }
    }
    Start-Sleep -Milliseconds 300
    $log = [IO.File]::ReadAllText($out, [Text.Encoding]::Unicode)
    [IO.File]::WriteAllText($out, $log, (New-Object Text.UTF8Encoding($false)))
    $log
}
