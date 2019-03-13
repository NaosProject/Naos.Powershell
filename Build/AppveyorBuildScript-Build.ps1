# PASTE THIS INTO APPVEYOUR - Build

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

#######################################################################
###     Download NuGet tools & Setup NuGet/Artifact scriptblocks    ###
#######################################################################
NuGet sources add -Name NaosMyGet -Source https://www.myget.org/F/naos-nuget/api/v3/index.json
NuGet sources add -Name ObcMyGet -Source https://www.myget.org/F/obeautifulcode-nuget/api/v3/index.json
$TempBuildPackagesDir = "../TempTools/packages"
if (-not (Test-Path $TempBuildPackagesDir)) { md $TempBuildPackagesDir | Out-Null }
$TempBuildPackagesDir = Resolve-Path $TempBuildPackagesDir
NuGet install 'Naos.Powershell.Build' -OutputDirectory $TempBuildPackagesDir
$nugetFunctionsScriptPath = $(ls $TempBuildPackagesDir -Recurse | ?{$_.Name -eq 'NuGet-Functions.ps1'}).FullName
. $nugetFunctionsScriptPath

$nugetScriptblock = { param([string] $fileName) 
   Write-Host "Pushing $fileName to Build Artifacts"
   Push-AppveyorArtifact $fileName

   Write-Host "Pushing $fileName to NuGet Gallery"
   Nuget-PublishPackage -packagePath $fileName -apiUrl $nugetUrl -apiKey $nugetKey

   Write-Host "Pushing $fileName to MyGet Gallery"
   Nuget-PublishPackage -packagePath $fileName -apiUrl $mygetUrl -apiKey $mygetKey
}

$artifactScriptBlock = { param([string] $fileName) 
   Write-Host "Pushing $fileName to Build Artifacts"
   Push-AppveyorArtifact $fileName
}

#######################################################################
###     Pack and push build                                         ###
#######################################################################
$createdPackagePaths = New-Object 'System.Collections.Generic.List[String]'
$informationalVersion = Nuget-CreatePreReleaseSupportedVersion -version $buildVersion -branchName $branchName

$nuSpecFileAnalyzer = Resolve-Path ./Analyzers/Naos.Build.Analyzers.nuspec
$nuSpecFilePackaging = Resolve-Path ./Packaging/Naos.Build.Packaging.nuspec
$nuSpecFileConventionsRepoConfig = Resolve-Path ./Conventions/Naos.Build.Conventions.RepoConfig.nuspec
$nuSpecFileConventionsReSharper = Resolve-Path ./Conventions/Naos.Build.Conventions.ReSharper.nuspec

,$nuSpecFileAnalyzer,$nuSpecFilePackaging,$nuSpecFileConventionsRepoConfig,$nuSpecFileConventionsReSharper | %{
	&$artifactScriptBlock($_)
	$packageFile = Nuget-CreatePackageFromNuspec -nuspecFilePath $_ -version $informationalVersion -throwOnError $true -outputDirectory $TempBuildPackagesDir
	$createdPackagePaths.Add($packageFile)
}

$createdPackagePaths | %{
	&$nugetScriptblock($_)
}
