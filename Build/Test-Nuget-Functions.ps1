function Test-NuGet-CreateRecipeNuSpecInFolder()
{
	throw "Not Implemented"
#[string] $recipeFolderPath, [string] $authors, [string] $nuSpecTemplateFilePath = $null
}

function Test-NuGet-OverrideNuSpec()
{
	throw "Not Implemented"
#[xml] $nuSpecFileXml, [xml] $overrideNuSpecFileXml, [string] $autoPackageId
}

function Test-NuGet-CreateNuSpecExternalWrapper()
{
	throw "Not Implemented"
#[string] $externalId, [string] $version, [string] $outputFile, [string] $packagePrefix = 'ExternallyWrapped'
}

function Test-NuGet-UpdateVersionOnNuSpecExternalWrapper()
{
	throw "Not Implemented"
#[string] $version, [string] $nuspecFile
}

function Test-NuGet-GetNuSpecFilePath()
{
	throw "Not Implemented"
#[string] $projFilePath
}

function Test-NuGet-CreateNuSpecFileFromProject()
{
	throw "Not Implemented"
#[string] $projFilePath, [System.Array] $projectReferences, [System.Collections.HashTable] $filesToPackageFolderMap, [string] $authors, [bool] $throwOnError = $true, [string] $maintainSubpathFrom = $null, [string] $nuSpecTemplateFilePath = $null
}

function Test-Nuget-CreatePreReleaseSupportedVersion()
{
	throw "Not Implemented"
#[string] $version, [string] $branchName
}

function Test-Nuget-ConstrainVersionToCurrent()
{
	throw "Not Implemented"
#[string] $packageFilePath
}

. ./Nuget-Functions.ps1
. ./Test-Functions.ps1
Test-RunTestFunctions -testFunctionPrefix 'Test-Nuget'