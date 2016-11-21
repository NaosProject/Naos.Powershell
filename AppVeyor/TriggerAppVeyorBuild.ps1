<#
.SYNOPSIS 
Triggers a build for the specified project.

.DESCRIPTION
Triggers a build for the specified project.

.PARAMETER ProjectName
The name of the project to trigger a build on.

.PARAMETER BranchName
The optional name of a the branch to trigger (master is the default).

.PARAMETER ApiToken
The AppVeyor provided API Token

.PARAMETER Run
Switch to initiate execution.

.EXAMPLE
.\TriggerAppVeyorBuild.ps1 -ProjectName 'Naos.Utils.Database' -ApiToken $apiToken -Run

#>
param(
	[string] $ProjectName = $(throw 'Must provide a ProjectName'),
	[string] $BranchName = $null,
	[string] $ApiToken = $(throw 'Must provide an ApiToken'),
	[switch] $Run
)
try
{
	$defaultBranchName = 'master'
	if ([string]::IsNullOrEmpty($BranchName))
	{
		$BranchName = $defaultBranchName
	}
	
	if ($Run)
	{
		$headers = @{
		  "Authorization" = "Bearer $ApiToken"
		  "Content-type" = "application/json"
		  "Accept" = "application/json"
		}

		$projects = Invoke-RestMethod -Uri 'https://ci.appveyor.com/api/projects' -Headers $headers -Method Get
		
		$branch = $BranchName
		$project = $projects | ?{ $_.name -eq $ProjectName }
		if ($project -eq $null)
		{
			throw "Could not find Project: $project in the specified account"
		}
		
		$buildUrl = "https://ci.appveyor.com/api/builds"
		Write-Host ">Building $project for $BranchName"
		$bodyObject = @{ accountName = $project.accountName; projectSlug = $project.slug; branch = $branch } 
		$bodyJson = $bodyObject | ConvertTo-json
		
		$postResponse = Invoke-WebRequest -Uri $buildUrl -Headers $headers -Method Post -ContentType "application/json" -Body $bodyJson
		$responseCode = $postResponse.StatusCode
		$expectedResponseCode = '200'
		if ($responseCode -ne $expectedResponseCode)
		{
			throw "Expected a response code of $expectedResponseCode and instead got $responseCode, please investigate..."
		}
		
		Write-Host "<Response was $responseCode (Expect $expectedResponseCode)"
		Write-Host ''
	}
}
catch
{
    Write-Host ""
    Write-Host -ForegroundColor Red "ERROR DURING EXECUTION @ $([DateTime]::Now.ToString('yyyyMMdd-HHmm'))"
    Write-Host ""
    Write-Host -ForegroundColor Magenta "  BEGIN Error Details:"
    Write-Host ""
    Write-Host "   $_"
    Write-Host "   IN FILE: $($_.InvocationInfo.ScriptName)"
    Write-Host "   AT LINE: $($_.InvocationInfo.ScriptLineNumber) OFFSET: $($_.InvocationInfo.OffsetInLine)"
    Write-Host ""
    Write-Host -ForegroundColor Magenta "  END   Error Details:"
    Write-Host ""
    Write-Host -ForegroundColor Red "ERROR DURING EXECUTION"
    Write-Host ""
    
    throw
}
