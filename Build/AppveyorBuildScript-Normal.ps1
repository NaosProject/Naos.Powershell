# PASTE THIS INTO APPVEYOUR
Write-Host $env:APPVEYOR_JOB_ID
Write-Host $env:APPVEYOR_API_URL
$TempBuildPackagesDir = "../BuildToolsFromNuGet/packages"
if (-not (Test-Path $TempBuildPackagesDir)) { md $TempBuildPackagesDir | Out-Null }
$TempBuildPackagesDir = Resolve-Path $TempBuildPackagesDir

NuGet install Naos.Build -OutputDirectory $TempBuildPackagesDir
NuGet install StyleCop.MSBuild -OutputDirectory $TempBuildPackagesDir

$styleCopTargetsPath = (ls "$TempBuildPackagesDir/*/*/*" -Filter 'StyleCop.MSBuild.Targets').FullName

$nuSpecTemplateFile = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Build.*).FullName 'scripts') 'NaosNuSpecTemplate.nuspec'

$ourStyleCopSettingsFile = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Build.*).FullName 'scripts') 'Settings.StyleCop'
$theirStyleCopSettingsFileLocation = Join-Path (ls $TempBuildPackagesDir/StyleCop.MSBuild.*).FullName 'tools'
cp $ourStyleCopSettingsFile $theirStyleCopSettingsFileLocation -Force

$artifactScriptBlock = { param([string] $fileName) 
#Push-AppveyorArtifact $fileName 
}

$initScripts = (ls "$TempBuildPackagesDir/*/*/*" -Filter 'init.ps1')
foreach ($initScript in $initScripts) {
	write-host "Running: " $initScript.FullName
	$parentDir = Split-Path -parent $initScript.FullName
	$parentDir = Split-Path -parent $parentDir
	&$initScript.FullName -installPath $parentDir
}

$customMsBuildLogger = 'C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll'

$buildScript = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Powershell.Build.*).FullName 'scripts') 'Build.ps1'

&$buildScript -Version $env:appveyor_build_version -SourceDirectory (Resolve-Path '.') -BuildPackagesDirectory $TempBuildPackagesDir -BuildExtensionsDirectory (Resolve-Path '../BuildToolsFromNuGet/.build') -PackagesOutputDirectory (Resolve-Path '.') -BranchName $env:appveyor_repo_branch -GalleryUrl $env:nuget_gallery_url -GalleryApiKey $env:nuget_api_key  -PackageUpdateStrategyPrivateGallery 'None' -PackageUpdateStrategyPublicGallery $env:appveyor_nuget_update_strategy_public -StyleCopTargetsPath $styleCopTargetsPath -TreatBuildWarningsAsErrors ($env:treatBuildWarningsAsErrors -eq 'true') -RunCodeAnalysis ($env:runCodeAnalysis -eq 'true')  -RunJavaScriptTests ($env:runJavaScriptTests -eq 'true') -NuSpecTemplateFilePath $nuSpecTemplateFile -Authors 'Naos Project' -SaveFileAsBuildArtifact $artifactScriptBlock -CustomMsBuildLogger $customMsBuildLogger -Run