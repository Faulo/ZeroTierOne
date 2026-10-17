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

function Import-VisualStudioEnvironment {
	$devCommand = 'C:\BuildTools\2022\Common7\Tools\VsDevCmd.bat'
	$environment = & $env:ComSpec /s /c "`"$devCommand`" -arch=x64 -host_arch=x64 >nul && set"
	if ($LASTEXITCODE -ne 0) {
		throw "Visual Studio developer environment failed with exit code $LASTEXITCODE"
	}
	foreach ($entry in $environment) {
		$separator = $entry.IndexOf('=')
		if ($separator -gt 0) {
			Set-Item -LiteralPath "Env:$($entry.Substring(0, $separator))" -Value $entry.Substring($separator + 1)
		}
	}
}

function Initialize-OpenTelemetryApi {
	param(
		[Parameter(Mandatory)]
		[string] $RepoRoot
	)

	$version = 'v1.27.0'
	$source = Join-Path $RepoRoot '.deps-build\opentelemetry-cpp-src'
	$build = Join-Path $RepoRoot '.deps-build\otel-x64-ninja'
	$prefix = Join-Path $RepoRoot '.deps\x64'
	$packages = @(
		(Join-Path $prefix 'lib\cmake\opentelemetry-cpp'),
		(Join-Path $prefix 'lib64\cmake\opentelemetry-cpp')
	)
	if ($packages | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) {
		return
	}
	if (-not (Test-Path -LiteralPath (Join-Path $source '.git') -PathType Container)) {
		Invoke-NativeCommand -FilePath git -ArgumentList @('clone', '--depth', '1', '--branch', $version, 'https://github.com/open-telemetry/opentelemetry-cpp.git', $source)
	}
	Invoke-NativeCommand -FilePath cmake -ArgumentList @(
		'-S', $source,
		'-B', $build,
		'-G', 'Ninja',
		'-DCMAKE_MAKE_PROGRAM=C:/ninja/ninja.exe',
		'-DCMAKE_BUILD_TYPE=Release',
		"-DCMAKE_INSTALL_PREFIX=$prefix",
		'-DBUILD_TESTING=OFF',
		'-DOPENTELEMETRY_INSTALL=ON',
		'-DWITH_API_ONLY=ON'
	)
	Invoke-NativeCommand -FilePath cmake -ArgumentList @('--build', $build, '--parallel')
	Invoke-NativeCommand -FilePath cmake -ArgumentList @('--install', $build)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifacts = Join-Path $PSScriptRoot 'artifacts'
$cacheRoot = Join-Path $PSScriptRoot 'cache'
$buildDirectory = Join-Path $repoRoot 'build-windows-x64'
$gitRepoRoot = $repoRoot.Replace('\', '/')

$env:CARGO_HOME = Join-Path $cacheRoot 'cargo'
$env:VCPKG_DEFAULT_BINARY_CACHE = Join-Path $cacheRoot 'vcpkg-binaries'
$env:VCPKG_FORCE_SYSTEM_BINARIES = '1'
$env:VCPKG_KEEP_ENV_VARS = 'PATH'

Remove-Item -LiteralPath $artifacts -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $artifacts | Out-Null
New-Item -ItemType Directory -Path $env:VCPKG_DEFAULT_BINARY_CACHE -Force | Out-Null
New-Item -ItemType Directory -Path $env:CARGO_HOME -Force | Out-Null

Invoke-NativeCommand -FilePath git -ArgumentList @('config', '--global', '--add', 'safe.directory', $gitRepoRoot)
Invoke-NativeCommand -FilePath git -ArgumentList @('config', '--global', '--add', 'safe.directory', "$gitRepoRoot/*")

Push-Location $repoRoot
try {
	Import-VisualStudioEnvironment
	Initialize-OpenTelemetryApi -RepoRoot $repoRoot

	Invoke-NativeCommand -FilePath cmake -ArgumentList @(
		'-S', $repoRoot,
		'-B', $buildDirectory,
		'-G', 'Ninja',
		'-DCMAKE_MAKE_PROGRAM=C:/ninja/ninja.exe',
		'-DCMAKE_BUILD_TYPE=Release',
		"-DCMAKE_TOOLCHAIN_FILE=$env:VCPKG_ROOT\scripts\buildsystems\vcpkg.cmake",
		'-DVCPKG_TARGET_TRIPLET=x64-windows-static',
		"-DCMAKE_PREFIX_PATH=$repoRoot\.deps\x64",
		'-DBUILD_TESTING=ON'
	)
	Invoke-NativeCommand -FilePath cmake -ArgumentList @('--build', $buildDirectory, '--parallel')
	Invoke-NativeCommand -FilePath ctest -ArgumentList @(
		'--test-dir', $buildDirectory,
		'-C', 'Release',
		'--output-on-failure',
		'--output-junit', (Join-Path $artifacts 'TestResults.xml')
	)

	$sourceBinary = Join-Path $buildDirectory 'zerotier-one.exe'
	$artifactBinary = Join-Path $artifacts 'zerotier-one_x64.exe'
	Copy-Item -LiteralPath $sourceBinary -Destination $artifactBinary

	$sourcePdb = Join-Path $buildDirectory 'zerotier-one.pdb'
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
		cmakeGenerator = 'Ninja'
		configuration = 'Release'
		ztNonfree = Get-CMakeCacheValue -Path $cmakeCache -Name 'ZT_NONFREE'
		cmake = (& cmake --version | Select-Object -First 1)
		cxxCompiler = Get-CMakeCacheValue -Path $cmakeCache -Name 'CMAKE_CXX_COMPILER'
		cxxCompilerVersion = Get-CMakeCacheValue -Path $cmakeCache -Name 'CMAKE_CXX_COMPILER_VERSION'
		platformToolset = $env:VCToolsVersion.TrimEnd('\')
		windowsSdk = $env:WindowsSDKVersion.TrimEnd('\')
		rustc = (& rustc --version)
		cargo = (& cargo --version)
		vcpkgCommit = (& git -C $env:VCPKG_ROOT rev-parse HEAD).Trim()
	}
	$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $artifacts 'build-manifest.json') -Encoding utf8
} finally {
	Pop-Location
}
