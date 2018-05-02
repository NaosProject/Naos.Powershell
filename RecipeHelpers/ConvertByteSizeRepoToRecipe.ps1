$workingDir = 'D:\Temp\ByteSize'
if (Test-Path $workingDir)
{
	Remove-Item $workingDir -Force -Recurse
}
md $workingDir | Out-Null

. ../Build/Nuget-Functions.ps1
. ../Build/Version-Functions.ps1

$templateNuspec = 'D:\SourceCode\Naos\Naos.Build\Packaging\NaosNuSpecTemplate.template-nuspec'
$packageId = 'Naos.Recipes.ByteSize'
$repositoryZipUrl = 'https://github.com/omar/ByteSize/archive/master.zip'
$sourceSubPath = 'ByteSize-master\src\ByteSizeLib'
$scrubList = @()

Nuget-CreateRecipeFromRepository -packageId $packageId -templateNuspec $templateNuspec -workingDir $workingDir -repositoryZipUrl $repositoryZipUrl -sourceSubPath $sourceSubPath -scrubList $scrubList
