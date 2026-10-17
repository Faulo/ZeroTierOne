$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reports = Join-Path $PSScriptRoot 'reports'
$buildDirectory = Join-Path $repoRoot 'build-windows-x64'
$ctestReport = Join-Path $reports 'CTestResults.xml'
$smokeReport = Join-Path $reports 'SmokeTestResults.xml'
$binary = Join-Path $buildDirectory 'zerotier-one.exe'
$stdoutPath = Join-Path $reports 'version.stdout.txt'
$stderrPath = Join-Path $reports 'version.stderr.txt'

Remove-Item -LiteralPath $reports -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $reports | Out-Null

& ctest `
	--test-dir $buildDirectory `
	-C Release `
	--output-on-failure `
	--output-junit $ctestReport
$ctestExitCode = $LASTEXITCODE

$timer = [System.Diagnostics.Stopwatch]::StartNew()
$process = Start-Process `
	-FilePath $binary `
	-ArgumentList '-v' `
	-NoNewWindow `
	-PassThru `
	-Wait `
	-RedirectStandardOutput $stdoutPath `
	-RedirectStandardError $stderrPath
$timer.Stop()

$output = @(
	Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
	Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
) -join ''

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Encoding = [System.Text.UTF8Encoding]::new($false)
$settings.Indent = $true
$writer = [System.Xml.XmlWriter]::Create($smokeReport, $settings)
try {
	$failed = $process.ExitCode -ne 0
	$duration = $timer.Elapsed.TotalSeconds.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
	$writer.WriteStartDocument()
	$writer.WriteStartElement('testsuites')
	$writer.WriteAttributeString('tests', '1')
	$writer.WriteAttributeString('failures', $(if ($failed) { '1' } else { '0' }))
	$writer.WriteAttributeString('errors', '0')
	$writer.WriteAttributeString('time', $duration)
	$writer.WriteStartElement('testsuite')
	$writer.WriteAttributeString('name', 'ZeroTier smoke tests')
	$writer.WriteAttributeString('tests', '1')
	$writer.WriteAttributeString('failures', $(if ($failed) { '1' } else { '0' }))
	$writer.WriteAttributeString('errors', '0')
	$writer.WriteAttributeString('time', $duration)
	$writer.WriteStartElement('testcase')
	$writer.WriteAttributeString('classname', 'zerotier-one')
	$writer.WriteAttributeString('name', 'reports its version')
	$writer.WriteAttributeString('time', $duration)
	if ($failed) {
		$writer.WriteStartElement('failure')
		$writer.WriteAttributeString('message', "zerotier-one -v exited with code $($process.ExitCode)")
		$writer.WriteString($output)
		$writer.WriteEndElement()
	}
	$writer.WriteElementString('system-out', $output)
	$writer.WriteEndElement()
	$writer.WriteEndElement()
	$writer.WriteEndElement()
	$writer.WriteEndDocument()
} finally {
	$writer.Dispose()
}

if ($ctestExitCode -ne 0) {
	throw "ctest failed with exit code $ctestExitCode"
}
if ($process.ExitCode -ne 0) {
	throw "zerotier-one -v failed with exit code $($process.ExitCode)"
}
