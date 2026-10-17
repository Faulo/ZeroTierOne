$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$cmakeVersion = '3.31.6'
$cmakeSha256 = 'd163cd3ab4959b0a53fa8988f2ddbd2e6c501658201e6a154386bad9dbe4f836'
$rustVersion = '1.89.0'
$vcpkgCommit = 'a7acc4f979f2afde60757e0f9b572b5710ac08b1'

$cmakeArchive = 'C:\cmake.zip'
$cmakeExtract = 'C:\cmake-extract'
Invoke-WebRequest `
	-UseBasicParsing `
	-Uri "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip" `
	-OutFile $cmakeArchive
$actualCmakeSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $cmakeArchive).Hash.ToLowerInvariant()
if ($actualCmakeSha256 -ne $cmakeSha256) {
	throw "CMake archive checksum mismatch: $actualCmakeSha256"
}
Expand-Archive -LiteralPath $cmakeArchive -DestinationPath $cmakeExtract
Move-Item -LiteralPath "$cmakeExtract\cmake-$cmakeVersion-windows-x86_64" -Destination 'C:\cmake'
Remove-Item -LiteralPath $cmakeArchive, $cmakeExtract -Recurse -Force

$env:CARGO_HOME = 'C:\cargo'
$env:RUSTUP_HOME = 'C:\rustup'
$rustupInstaller = 'C:\rustup-init.exe'
$rustupBaseUri = 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc'
Invoke-WebRequest -UseBasicParsing -Uri "$rustupBaseUri/rustup-init.exe" -OutFile $rustupInstaller
$rustupChecksumContent = (Invoke-WebRequest -UseBasicParsing -Uri "$rustupBaseUri/rustup-init.exe.sha256").Content
$rustupChecksumText = if ($rustupChecksumContent -is [byte[]]) {
	[Text.Encoding]::ASCII.GetString($rustupChecksumContent)
} else {
	[string] $rustupChecksumContent
}
$expectedRustupSha256 = ([regex]::Match($rustupChecksumText, '[0-9a-fA-F]{64}')).Value.ToLowerInvariant()
if (-not $expectedRustupSha256) {
	throw 'rustup checksum response did not contain a SHA-256 digest'
}
$actualRustupSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $rustupInstaller).Hash.ToLowerInvariant()
if ($actualRustupSha256 -ne $expectedRustupSha256) {
	throw "rustup installer checksum mismatch: $actualRustupSha256"
}
$rustup = Start-Process `
	-FilePath $rustupInstaller `
	-ArgumentList @('-y', '--no-modify-path', '--profile', 'minimal', '--default-toolchain', $rustVersion, '--default-host', 'x86_64-pc-windows-msvc') `
	-NoNewWindow -PassThru -Wait
if ($rustup.ExitCode -ne 0) {
	throw "rustup failed with exit code $($rustup.ExitCode)"
}
Remove-Item -LiteralPath $rustupInstaller -Force

& 'C:\Git\cmd\git.exe' clone --filter=blob:none https://github.com/microsoft/vcpkg.git C:\vcpkg
if ($LASTEXITCODE -ne 0) {
	throw 'vcpkg clone failed'
}
& 'C:\Git\cmd\git.exe' -C C:\vcpkg checkout --detach $vcpkgCommit
if ($LASTEXITCODE -ne 0) {
	throw 'vcpkg checkout failed'
}
& C:\vcpkg\bootstrap-vcpkg.bat -disableMetrics
if ($LASTEXITCODE -ne 0) {
	throw 'vcpkg bootstrap failed'
}
