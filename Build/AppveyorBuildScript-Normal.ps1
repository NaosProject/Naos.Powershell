# PASTE THIS INTO APPVEYOUR - Normal

Write-Host $env:APPVEYOR_JOB_ID
Write-Host $env:APPVEYOR_API_URL
$TempBuildPackagesDir = "../BuildToolsFromNuGet/packages"
if (-not (Test-Path $TempBuildPackagesDir)) { md $TempBuildPackagesDir | Out-Null }
$TempBuildPackagesDir = Resolve-Path $TempBuildPackagesDir

NuGet install Naos.Build -OutputDirectory $TempBuildPackagesDir
NuGet install StyleCop.MSBuild -OutputDirectory $TempBuildPackagesDir

$nuSpecTemplateFile = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Build.*).FullName 'scripts') 'NaosNuSpecTemplate.template-nuspec'
$nugetFunctionsScriptPath = $(ls $TempBuildPackagesDir -Recurse | ?{$_.Name -eq 'NuGet-Functions.ps1'}).FullName

. $nugetFunctionsScriptPath

$nugetScriptblock = { param([string] $fileName) 
   Nuget-PublishPackage -packagePath $fileName -apiUrl $env:nuget_gallery_url -apiKey $env:nuget_api_key
   Nuget-PublishPackage -packagePath $fileName -apiUrl $env:myget_gallery_url -apiKey $env:myget_api_key
}

$artifactScriptBlock = { param([string] $fileName) 
#   Push-AppveyorArtifact $fileName 
}


$styleCopTargetsPath = (ls "$TempBuildPackagesDir/*/*/*" -Filter 'StyleCop.MSBuild.Targets').FullName

$ourStyleCopSettingsFile = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Build.*).FullName 'scripts') 'Settings.StyleCop'
$theirStyleCopSettingsFileLocation = Join-Path (ls $TempBuildPackagesDir/StyleCop.MSBuild.*).FullName 'tools'
cp $ourStyleCopSettingsFile $theirStyleCopSettingsFileLocation -Force

&$artifactScriptBlock($ourStyleCopSettingsFile)
&$artifactScriptBlock($nuSpecTemplateFile)

$initScripts = (ls "$TempBuildPackagesDir/*/*/*" -Filter 'init.ps1')
foreach ($initScript in $initScripts) {
	write-host "Running: " $initScript.FullName
	$parentDir = Split-Path -parent $initScript.FullName
	$parentDir = Split-Path -parent $parentDir
	&$initScript.FullName -installPath $parentDir
}

$customMsBuildLogger = 'C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll'

$buildScript = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Powershell.Build.*).FullName 'scripts') 'Build.ps1'

&$buildScript -Version $env:appveyor_build_version -SourceDirectory (Resolve-Path '.') -BuildPackagesDirectory $TempBuildPackagesDir -BuildExtensionsDirectory (Resolve-Path '../BuildToolsFromNuGet/.build') -PackagesOutputDirectory (Resolve-Path '.') -BranchName $env:appveyor_repo_branch -GalleryUrl $env:nuget_gallery_url -PackageUpdateStrategyPrivateGallery 'None' -PackageUpdateStrategyPublicGallery $env:appveyor_nuget_update_strategy_public -StyleCopTargetsPath $styleCopTargetsPath -TreatBuildWarningsAsErrors ($env:treatBuildWarningsAsErrors -eq 'true') -RunCodeAnalysis ($env:runCodeAnalysis -eq 'true')  -RunJavaScriptTests ($env:runJavaScriptTests -eq 'true') -NuSpecTemplateFilePath $nuSpecTemplateFile -Authors 'Naos Project' -PushNuGetPackageFile $nugetScriptblock -SaveFileAsBuildArtifact $artifactScriptBlock -CustomMsBuildLogger $customMsBuildLogger -Run