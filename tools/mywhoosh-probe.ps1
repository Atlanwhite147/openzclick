# Reads what MyWhoosh actually ships, without changing anything.
#
# The question this answers: could a modified build carry the controller
# connection itself, so a rider installs one thing instead of two? That depends
# on facts that are visible in the installation and nowhere else — whether the
# game is Mono or IL2CPP, whether the OpenBikeControl client is already inside it,
# and whether the files are checked. This script prints those facts.
#
# It never writes to the game's directory and never launches it.
#
#   powershell -ExecutionPolicy Bypass -File tools\mywhoosh-probe.ps1

$ErrorActionPreference = 'Stop'

function Find-MyWhoosh {
    $roots = @(
        "$env:LOCALAPPDATA\Programs",
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:LOCALAPPDATA"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $hit = Get-ChildItem -Path $root -Filter 'MyWhoosh*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

$exe = Find-MyWhoosh
if (-not $exe) {
    Write-Output 'MyWhoosh introuvable: rien a lire.'
    exit 1
}

$dir = $exe.Directory.FullName
Write-Output "installation : $dir"
Write-Output "executable  : $($exe.Name)  version $($exe.VersionInfo.FileVersion)"

# Mono ships managed assemblies; IL2CPP ships a native GameAssembly.dll plus a
# global-metadata.dat. The two answer the patching question differently.
$mono = Join-Path $dir '*_Data\Managed\Assembly-CSharp.dll'
$il2cpp = Join-Path $dir 'GameAssembly.dll'
$metadata = Get-ChildItem -Path $dir -Filter 'global-metadata.dat' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
    Select-Object -First 1

$managed = Get-ChildItem -Path $mono -ErrorAction SilentlyContinue | Select-Object -First 1
if ($managed) {
    Write-Output "runtime     : Mono (.NET) - Assembly-CSharp.dll present, $([math]::Round($managed.Length/1MB,1)) Mo"
} elseif (Test-Path $il2cpp) {
    $size = [math]::Round((Get-Item $il2cpp).Length / 1MB, 1)
    Write-Output "runtime     : IL2CPP - GameAssembly.dll, $size Mo"
    if ($metadata) {
        Write-Output "metadata    : $($metadata.FullName), $([math]::Round($metadata.Length/1MB,1)) Mo"
    }
} else {
    Write-Output 'runtime     : ni Mono ni IL2CPP trouve (build differente de ce qui est connu)'
}

# Does the game already speak OpenBikeControl? If the string and the service UUID
# are in the binaries, the integration exists and a patch would only be replacing
# the transport.
$needles = @('openbikecontrol', '_openbikecontrol._tcp', 'd273f680', '47123', '36867')
$targets = @()
$targets += Get-ChildItem -Path $dir -Filter '*.dll' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 20KB -and $_.Length -lt 400MB } |
    Select-Object -First 400
if ($metadata) { $targets += $metadata }

Write-Output ''
Write-Output "recherche de chaines dans $($targets.Count) fichier(s)"
foreach ($needle in $needles) {
    $found = @()
    foreach ($file in $targets) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($text.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $found += $file.Name
        }
    }
    if ($found.Count -gt 0) {
        Write-Output ("  {0,-24} trouve dans : {1}" -f $needle, (($found | Select-Object -Unique) -join ', '))
    } else {
        Write-Output ("  {0,-24} absent" -f $needle)
    }
}

# A manifest carrying the executable's hash, or a signature file beside it, is the
# sign of a self-check: mywhoosh-linux reports that the game stops using files it
# finds modified.
Write-Output ''
foreach ($marker in @('*.manifest', '*.sig', 'checksums*', '*.sha256', '*.md5')) {
    $hits = Get-ChildItem -Path $dir -Filter $marker -Recurse -Depth 2 -ErrorAction SilentlyContinue
    foreach ($hit in $hits) { Write-Output "controle d'integrite possible : $($hit.FullName)" }
}

Write-Output ''
Write-Output 'Rien n a ete modifie. Ce rapport dit seulement ce que le jeu contient.'
