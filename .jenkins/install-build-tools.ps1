$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$visualStudioInstaller = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
$visualStudio = Start-Process `
	-FilePath $visualStudioInstaller `
	-ArgumentList @('modify', '--installPath', 'C:\BuildTools\2022', '--add', 'Microsoft.VisualStudio.Component.VC.ATLMFC', '--quiet', '--norestart', '--nocache') `
	-NoNewWindow -PassThru -Wait
if ($visualStudio.ExitCode -ne 0) {
	throw "Visual Studio MFC installation failed with exit code $($visualStudio.ExitCode)"
}

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

$vsDevCommand = 'C:\BuildTools\2022\Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $vsDevCommand -PathType Leaf)) {
	throw "Visual Studio developer command file does not exist: $vsDevCommand"
}
$vcTools = Get-ChildItem 'C:\BuildTools\2022\VC\Tools\MSVC' -Directory |
	Where-Object { Test-Path (Join-Path $_.FullName 'atlmfc\lib\x64\mfcs140.lib') } |
	Sort-Object { [version]$_.Name } |
	Select-Object -Last 1
if (-not $vcTools) {
	throw 'No MSVC toolset with x64 MFC libraries is installed'
}
[Environment]::SetEnvironmentVariable('MSVC_TOOLSET_VERSION', $vcTools.Name, 'Machine')
$developerEnvironment = & $env:ComSpec /s /c "`"$vsDevCommand`" -arch=x64 -host_arch=x64 -vcvars_ver=$($vcTools.Name) >nul && set"
if ($LASTEXITCODE -ne 0) {
	throw "Visual Studio developer environment failed with exit code $LASTEXITCODE"
}
foreach ($entry in $developerEnvironment) {
	$separator = $entry.IndexOf('=')
	if ($separator -gt 0) {
		$name = $entry.Substring(0, $separator)
		$value = $entry.Substring($separator + 1)
		[Environment]::SetEnvironmentVariable($name, $value, 'Machine')
	}
}

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$toolPaths = @('C:\cargo\bin')
[Environment]::SetEnvironmentVariable('Path', (($toolPaths + $machinePath) -join ';'), 'Machine')

& 'C:\Git\cmd\git.exe' config --system --add safe.directory '*'
if ($LASTEXITCODE -ne 0) {
	throw 'Configuring Git safe directories failed'
}
