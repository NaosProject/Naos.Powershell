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


$nuspecs = New-Object 'System.Collections.Generic.List[String]'
$nuSpecFileAnalyzer = Resolve-Path ./Analyzers/Naos.Build.Analyzers.nuspec
$nuspecs.Add($nuSpecFileAnalyzer)
$nuSpecFilePackaging = Resolve-Path ./Packaging/Naos.Build.Packaging.nuspec
$nuspecs.Add($nuSpecFilePackaging)
$nuSpecFileConventionsRepoConfig = Resolve-Path ./Conventions/Naos.Build.Conventions.RepoConfig.nuspec
$nuspecs.Add($nuSpecFileConventionsRepoConfig)
$nuSpecFileConventionsReSharper = Resolve-Path ./Conventions/Naos.Build.Conventions.ReSharper.nuspec
$nuspecs.Add($nuSpecFileConventionsReSharper)

$nuSpecTemplateFilePath = $(ls . -Recurse | ?{$_.Name -eq 'NaosNuSpecTemplate.template-nuspec'}).FullName

$visualStudioProjectTemplateDirectories = ls ./Conventions/VisualStudioProjectTemplates | ?{$_.PSIsContainer} | %{$_.FullName}
$visualStudioProjectTemplateDirectories | %{
    $projectTemplateDirectory = $_
    $projectTemplateDirectoryName = Split-Path $projectTemplateDirectory -Leaf
    $packageId = "Naos.Build.Conventions.VisualStudioProjectTemplates.$projectTemplateDirectoryName"
    $nuSpecFilePath = "./VisualStudioProjectTemplate_$projectTemplateDirectoryName.nuspec"
	$contents = Nuget-GetMinimumNuSpec -id $packageId -version '$version$' -authors $authors -description $description -isDevelopmentDependency $true
	$contents | Out-File $nuSpecFilePath -Force
	[xml] $nuSpecFileXml = Get-Content $nuSpecFilePath    
	[xml] $nuSpecTemplateFileXml = Get-Content $nuSpecTemplateFilePath
	Nuget-OverrideNuSpec -nuSpecFileXml $nuSpecFileXml -overrideNuSpecFileXml $nuSpecTemplateFileXml -autoPackageId $packageId
    $filesNode = $nuSpecFileXml.CreateElement('files')
	
	$files = ls $projectTemplateDirectory -Recurse | ?{-not $_.PSIsContainer}

	$files | %{
		$fileName = $_.Name
		$filePath = $_.FullName
		$relativeFilePathToTemplateDirectory = $filePath.Replace($projectTemplateDirectory, '')
		if ($relativeFilePathToTemplateDirectory.StartsWith('/') -or $relativeFilePathToTemplateDirectory.StartsWith('\'))
		{
			# strip off the leading / or \ because it will mess things up...
			$relativeFilePathToTemplateDirectory = $relativeFilePathToTemplateDirectory.Substring(1, $relativeFilePathToTemplateDirectory.Length - 1)
		}
		
		$targetPath = Join-Path "$projectTemplateDirectoryName" $relativeFilePathToTemplateDirectory
		
		$fileNode = $nuSpecFileXml.CreateElement('file')
		$fileNode.SetAttribute('src', $filePath)
		$fileNode.SetAttribute('target', $targetPath)
		[void]$filesNode.AppendChild($fileNode)
	}

	[void]$nuSpecFileXml.package.AppendChild($filesNode)	
    $nuSpecFileXml.package.metadata.Description = "Visual Studio Project Template for the '$projectTemplateDirectoryName' project kind (does not install in a project, contents are held in the '$projectTemplateDirectoryName' folder)."
	
	# save updated file (can NOT be relative path)
    $nuSpecFilePath = Resolve-Path $nuSpecFilePath
	$nuSpecFileXml.Save($nuSpecFilePath)
    $nuspecs.Add($nuSpecFilePath)
}

$nuspecs | %{
	&$artifactScriptBlock($_)
	$packageFile = Nuget-CreatePackageFromNuspec -nuspecFilePath $_ -version $informationalVersion -throwOnError $true -outputDirectory $TempBuildPackagesDir
	$createdPackagePaths.Add($packageFile)
}

$createdPackagePaths | %{
	&$nugetScriptblock($_)
}
