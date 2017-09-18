# PASTE THIS INTO APPVEYOUR - Normal

Write-Host $env:APPVEYOR_JOB_ID
Write-Host $env:APPVEYOR_API_URL

#######################################################################
###     Setup variables from Appveyor                               ###
#######################################################################
$repoPath = Resolve-Path .
$buildVersion = $env:appveyor_build_version
$branchName = $env:appveyor_repo_branch
$repoName = $env:appveyor_repo_name
$nugetUrl = $env:nuget_gallery_url
$nugetKey = $env:nuget_api_key
$mygetUrl = $env:myget_gallery_url
$mygetKey = $env:myget_api_key

# normal build specific
$treatBuildWarningsAsErrors = $env:treatBuildWarningsAsErrors
$runCodeAnalysis = $env:runCodeAnalysis
$appveyorNugetUpdateStrategyPrivate = $env:appveyor_nuget_update_strategy_private
$appveyorNugetUpdateStrategyPublic = $env:appveyor_nuget_update_strategy_public

#######################################################################
###     Download and dot source tools to use                        ###
#######################################################################
NuGet sources add -Name NaosMyGet -Source https://www.myget.org/F/naos-nuget/api/v3/index.json
NuGet sources add -Name ObcMyGet -Source https://www.myget.org/F/obeautifulecode-nuget/api/v3/index.json
$TempBuildPackagesDir = "../TempTools/packages"
if (-not (Test-Path $TempBuildPackagesDir)) { md $TempBuildPackagesDir | Out-Null }
$TempBuildPackagesDir = Resolve-Path $TempBuildPackagesDir
NuGet install 'Naos.Powershell.Build' -Prerelease -OutputDirectory $TempBuildPackagesDir
NuGet install 'Naos.Build.Packaging' -Prerelease -OutputDirectory $TempBuildPackagesDir
NuGet install 'Naos.Build.Conventions.RepoConfig' -Prerelease -OutputDirectory $TempBuildPackagesDir

$repoConfigFile = (ls $TempBuildPackagesDir -Filter 'RepoConfig.ps1' -Recurse).FullName
if ($repoConfigFile -eq $null) {
	ls $TempBuildPackagesDir -Recurse | %{ $_.FullName }
	throw "Could not find 'RepoConfig.ps1' in $TempBuildPackagesDir"
}
&$repoConfigFile -ThrowOnPendingUpdate -PreRelease -RepositoryPath $repoPath

$nuSpecTemplateFile = Join-Path (ls $TempBuildPackagesDir/Naos.Build.Packaging.*).FullName 'NaosNuSpecTemplate.template-nuspec'

$nugetFunctionsScriptPath = $(ls $TempBuildPackagesDir -Recurse | ?{$_.Name -eq 'NuGet-Functions.ps1'}).FullName

. $nugetFunctionsScriptPath

#######################################################################
###     Setup NuGet/Artifact scriptblocks                           ###
#######################################################################
$nugetScriptblock = { param([string] $fileName) 
   Write-Host "Pushing $fileName to Build Artifacts"
   Push-AppveyorArtifact $fileName

   Write-Host "Pushing $fileName to AppVeyor Gallery"
   Nuget-PublishPackage -packagePath $fileName -apiUrl $nugetUrl -apiKey $nugetKey

   Write-Host "Pushing $fileName to MyGet Gallery"
   Nuget-PublishPackage -packagePath $fileName -apiUrl $mygetUrl -apiKey $mygetKey
}

$artifactScriptBlock = { param([string] $fileName) 
   Write-Host "Pushing $fileName to Build Artifacts"
   Push-AppveyorArtifact $fileName
}

#######################################################################
###     Setup Prerequistes and run build                            ###
#######################################################################
&$artifactScriptBlock($nuSpecTemplateFile)

$customMsBuildLogger = 'C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll'

$buildScript = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Powershell.Build.*).FullName 'scripts') 'Build.ps1'

&$buildScript -Version $buildVersion -SourceDirectory (Resolve-Path '.') -BuildPackagesDirectory $TempBuildPackagesDir -PackagesOutputDirectory (Resolve-Path '.') -BranchName $branchName -GalleryUrl $appveyorNugetUrl -PackageUpdateStrategyPrivateGallery $appveyorNugetUpdateStrategyPrivate -PackageUpdateStrategyPublicGallery $appveyorNugetUpdateStrategyPublic -TreatBuildWarningsAsErrors ($treatBuildWarningsAsErrors -eq 'true') -RunCodeAnalysis ($runCodeAnalysis -eq 'true') -NuSpecTemplateFilePath $nuSpecTemplateFile -Authors 'Naos Project' -PushNuGetPackageFile $nugetScriptblock -SaveFileAsBuildArtifact $artifactScriptBlock -CustomMsBuildLogger $customMsBuildLogger -Run
