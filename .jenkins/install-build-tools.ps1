$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$cmakeArchive = 'C:\cmake.zip'
$cmakeExtract = 'C:\cmake-extract'
$cmakeRelease = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/Kitware/CMake/releases/latest'
$cmakeAsset = @($cmakeRelease.assets | Where-Object { $_.name -match '^cmake-[0-9.]+-windows-x86_64\.zip$' })
if ($cmakeAsset.Count -ne 1) {
	throw "Expected one Windows x64 CMake archive in the latest release, found $($cmakeAsset.Count)"
}
Invoke-WebRequest -UseBasicParsing -Uri $cmakeAsset[0].browser_download_url -OutFile $cmakeArchive
Expand-Archive -LiteralPath $cmakeArchive -DestinationPath $cmakeExtract
$cmakeDirectory = @(Get-ChildItem -LiteralPath $cmakeExtract -Directory)
if ($cmakeDirectory.Count -ne 1) {
	throw "Expected one directory in the CMake archive, found $($cmakeDirectory.Count)"
}
Move-Item -LiteralPath $cmakeDirectory[0].FullName -Destination 'C:\cmake'
Remove-Item -LiteralPath $cmakeArchive, $cmakeExtract -Recurse -Force

$ninjaArchive = 'C:\ninja.zip'
$ninjaRelease = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/ninja-build/ninja/releases/latest'
$ninjaAsset = @($ninjaRelease.assets | Where-Object { $_.name -eq 'ninja-win.zip' })
if ($ninjaAsset.Count -ne 1) {
	throw "Expected one Windows Ninja archive in the latest release, found $($ninjaAsset.Count)"
}
Invoke-WebRequest -UseBasicParsing -Uri $ninjaAsset[0].browser_download_url -OutFile $ninjaArchive
Expand-Archive -LiteralPath $ninjaArchive -DestinationPath 'C:\ninja'
Remove-Item -LiteralPath $ninjaArchive -Force

$env:CARGO_HOME = 'C:\cargo'
$env:RUSTUP_HOME = 'C:\rustup'
$rustupInstaller = 'C:\rustup-init.exe'
Invoke-WebRequest -UseBasicParsing -Uri 'https://win.rustup.rs/x86_64' -OutFile $rustupInstaller
$rustup = Start-Process `
	-FilePath $rustupInstaller `
	-ArgumentList @('-y', '--no-modify-path', '--profile', 'minimal', '--default-toolchain', 'stable', '--default-host', 'x86_64-pc-windows-msvc') `
	-NoNewWindow -PassThru -Wait
if ($rustup.ExitCode -ne 0) {
	throw "rustup failed with exit code $($rustup.ExitCode)"
}
Remove-Item -LiteralPath $rustupInstaller -Force

& 'C:\Git\cmd\git.exe' clone https://github.com/microsoft/vcpkg.git C:\vcpkg
if ($LASTEXITCODE -ne 0) {
	throw 'vcpkg clone failed'
}
& C:\vcpkg\bootstrap-vcpkg.bat -disableMetrics
if ($LASTEXITCODE -ne 0) {
	throw 'vcpkg bootstrap failed'
}

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$toolPaths = @('C:\cmake\bin', 'C:\ninja', 'C:\cargo\bin', 'C:\vcpkg')
[Environment]::SetEnvironmentVariable('Path', (($toolPaths + $machinePath) -join ';'), 'Machine')
