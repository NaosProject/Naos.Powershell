# PASTE THIS INTO APPVEYOUR

###########################################################
###       Setup variables from Appveyor                 ###
###########################################################
$version = $env:appveyor_build_version
$branchName = $env:appveyor_repo_branch
$galleryUrl = $env:appveyor_account_nuget_url
$galleryApiKey = $env:appveyor_account_nuget_key
$artifactScriptBlock = { param([string] $fileName) Push-AppveyorArtifact $fileName }
$repoPath = Resolve-Path .

###########################################################
###    Download and dot source tools to use             ###
###########################################################
$TempBuildPackagesDir = "../BuildToolsFromNuGet/packages"
if (-not (Test-Path $TempBuildPackagesDir)) { md $TempBuildPackagesDir | Out-Null }
$TempBuildPackagesDir = Resolve-Path $TempBuildPackagesDir
NuGet install Naos.Build -OutputDirectory $TempBuildPackagesDir

$nuSpecTemplateFile = Join-Path (Join-Path (ls $TempBuildPackagesDir/Naos.Build.*).FullName 'scripts') 'NaosNuSpecTemplate.template-nuspec'

$nugetFunctionsScriptPath = $(ls $TempBuildPackagesDir -Recurse | ?{$_.Name -eq 'NuGet-Functions.ps1'}).FullName

. $nugetFunctionsScriptPath


###########################################################
###       Run steps to process recipes repo             ###
###########################################################

# if we are in a branch then create a pre-release version for nuget
$preReleaseSupportVersion = Nuget-CreatePreReleaseSupportedVersion -version $version -branchName $branchName

# discover the distinct recipes
$recipes = ls $repoPath | ?{ -not $_.Name.StartsWith('.') } | %{$_}

# create the nuspec files in place
$recipes | %{
	$recipePath = $_.FullName
	Write-Output ''
	Write-Output "Creating NuSpec for '$recipePath'"
	NuGet-CreateRecipeNuSpecInFolder -recipeFolderPath $recipePath -authors 'Naos Project' -nuSpecTemplateFilePath $nuSpecTemplateFile
}

# push the nuspecs as artifacts
ls . *.nuspec -Recurse | %{&$artifactScriptBlock($_.FullName)}

# create the nupkgs in place
$recipes | %{
	$recipePath = $_.FullName
	$nuspecFilePath = $(ls $recipePath -Filter '*.nuspec').FullName
	$packageFile = Nuget-CreatePackageFromNuspec -nuspecFilePath $nuspecFilePath -version $version -throwOnError $true -outputDirectory $recipePath
}

# push the nupkgs as artifacts
ls . *.nupkg -Recurse | %{&$artifactScriptBlock($_.FullName)}

# push the nupkgs to gallery
$recipes | %{
	$recipePath = $_.FullName
	$nuPkgFilePath = $(ls $recipePath -Filter '*.nupkg').FullName
	Write-Output "Pushing package $nuPkgFilePath"
	Nuget-PublishPackage -packagePath $nuPkgFilePath -apiUrl $galleryUrl -apiKey $galleryApiKey
}
