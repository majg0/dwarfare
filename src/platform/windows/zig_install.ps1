# # Define the target directory for Zig installation
$target = "$env:APPDATA\zig_bin"
if (Test-Path $target) {
    Remove-Item -Recurse -Force $target
}

$version = (Invoke-RestMethod 'https://ziglang.org/download/index.json').master.version
$arch = if ([System.Environment]::Is64BitOperatingSystem) {
    $cpuArch = (Get-WmiObject -Class Win32_Processor).Architecture
    switch ($cpuArch) {
        5 { 'arm' }
        9 { 'x86_64' }
        12 { 'aarch64' }
		default { 'x86_64' }
	}
} else {
	'x86'
}
$os = 'windows'
$name = "zig-$os-$arch-$version"
$zipfile = "$name.zip"

Invoke-WebRequest -Uri "https://ziglang.org/builds/$zipfile" -OutFile $zipfile
Expand-Archive -Path $zipfile -DestinationPath .
Remove-Item $zipfile
Move-Item -Path $name -Destination $target

$zls = "zls.exe"
Invoke-WebRequest -Uri "https://zigtools-releases.nyc3.digitaloceanspaces.com/zls/master/${arch}-${os}/zls.exe" -OutFile $zls
Move-Item -Path $zls -Destination $target

& icacls "$target\$zls" /grant Everyone:F

Write-Host "WARNING: zig + zls may be incompatible"
Write-Host "you should add the following path to PATH:"
Write-Host $target
