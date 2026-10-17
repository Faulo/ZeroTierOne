$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-NativeCommand {
	param(
		[Parameter(Mandatory)]
		[string] $FilePath,

		[Parameter(ValueFromRemainingArguments)]
		[string[]] $ArgumentList
	)

	& $FilePath @ArgumentList
	if ($LASTEXITCODE -ne 0) {
		throw "$FilePath failed with exit code $LASTEXITCODE"
	}
}

function Get-CMakeCacheValue {
	param(
		[Parameter(Mandatory)]
		[string] $Path,

		[Parameter(Mandatory)]
		[string] $Name
	)

	$pattern = '^' + [regex]::Escape($Name) + ':[^=]+=(.*)$'
	foreach ($line in Get-Content -LiteralPath $Path) {
		$match = [regex]::Match($line, $pattern)
		if ($match.Success) {
			return $match.Groups[1].Value
		}
	}
	return $null
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifacts = Join-Path $PSScriptRoot 'artifacts'
$cacheRoot = Join-Path $PSScriptRoot 'cache'
$buildDirectory = Join-Path $repoRoot 'build-windows-x64'

$env:CARGO_HOME = Join-Path $cacheRoot 'cargo'
$env:VCPKG_DEFAULT_BINARY_CACHE = Join-Path $cacheRoot 'vcpkg-binaries'
$env:VCPKG_DOWNLOADS = Join-Path $cacheRoot 'vcpkg-downloads'

Remove-Item -LiteralPath $artifacts -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $artifacts | Out-Null
New-Item -ItemType Directory -Path $env:VCPKG_DEFAULT_BINARY_CACHE -Force | Out-Null
New-Item -ItemType Directory -Path $env:VCPKG_DOWNLOADS -Force | Out-Null
New-Item -ItemType Directory -Path $env:CARGO_HOME -Force | Out-Null

Push-Location $repoRoot
try {
	Invoke-NativeCommand -FilePath powershell -ArgumentList @(
		'-ExecutionPolicy', 'Bypass',
		'-NonInteractive',
		'-NoProfile',
		'-File', 'scripts\bootstrap-deps.ps1',
		'-Arch', 'x64'
	)

	Invoke-NativeCommand -FilePath cmake -ArgumentList @('--preset', 'windows-x64', '-DBUILD_TESTING=ON')
	Invoke-NativeCommand -FilePath cmake -ArgumentList @('--build', '--preset', 'windows-x64-release', '--parallel')
	Invoke-NativeCommand -FilePath ctest -ArgumentList @(
		'--test-dir', $buildDirectory,
		'-C', 'Release',
		'--output-on-failure',
		'--output-junit', (Join-Path $artifacts 'TestResults.xml')
	)

	$sourceBinary = Join-Path $buildDirectory 'Release\zerotier-one.exe'
	$artifactBinary = Join-Path $artifacts 'zerotier-one_x64.exe'
	Copy-Item -LiteralPath $sourceBinary -Destination $artifactBinary

	$sourcePdb = Join-Path $buildDirectory 'Release\zerotier-one.pdb'
	if (Test-Path -LiteralPath $sourcePdb -PathType Leaf) {
		Copy-Item -LiteralPath $sourcePdb -Destination (Join-Path $artifacts 'zerotier-one_x64.pdb')
	}

	$binaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactBinary).Hash.ToLowerInvariant()
	Set-Content `
		-LiteralPath (Join-Path $artifacts 'SHA256SUMS') `
		-Value "$binaryHash  zerotier-one_x64.exe" `
		-Encoding ascii

	$cmakeCache = Join-Path $buildDirectory 'CMakeCache.txt'
	$manifest = [ordered]@{
		artifact = 'zerotier-one_x64.exe'
		sha256 = $binaryHash
		sourceCommit = (& git rev-parse HEAD).Trim()
		buildImage = $env:ZT_BUILD_IMAGE
		cmakePreset = 'windows-x64'
		configuration = 'Release'
		ztNonfree = Get-CMakeCacheValue -Path $cmakeCache -Name 'ZT_NONFREE'
		cmake = (& cmake --version | Select-Object -First 1)
		cxxCompiler = Get-CMakeCacheValue -Path $cmakeCache -Name 'CMAKE_CXX_COMPILER'
		cxxCompilerVersion = Get-CMakeCacheValue -Path $cmakeCache -Name 'CMAKE_CXX_COMPILER_VERSION'
		platformToolset = Get-CMakeCacheValue -Path $cmakeCache -Name 'CMAKE_VS_PLATFORM_TOOLSET'
		windowsSdk = Get-CMakeCacheValue -Path $cmakeCache -Name 'CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION'
		rustc = (& rustc --version)
		cargo = (& cargo --version)
		vcpkgCommit = (& git -C $env:VCPKG_ROOT rev-parse HEAD).Trim()
	}
	$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $artifacts 'build-manifest.json') -Encoding utf8
} finally {
	Pop-Location
}
