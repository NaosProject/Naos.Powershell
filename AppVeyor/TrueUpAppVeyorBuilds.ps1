<#
.SYNOPSIS 
Takes the project configuration of a provided reference project and updates all of the other projects (besides build) to those settings.

.DESCRIPTION
Takes the project configuration of a provided reference project and updates all of the other projects (besides build) to those settings.

.PARAMETER ReferenceProjectName
The name of the project to use as a reference for configuration.

.PARAMETER TargetProjectName
The name of a single project to true up to reference (optional, default is ALL projects in account).

.PARAMETER ApiToken
The AppVeyor provided API Token.

.PARAMETER BlackList
A collection of project names to exclude from.

.PARAMETER RunForTarget
Switch to initiate execution, will only work on a target project.

.PARAMETER RunForAll
Switch to initiate execution, will only work without a target project.

.EXAMPLE
.\TrueUpAppVeyorBuilds.ps1 -ReferenceProjectName 'Naos.Utils.Database' -Run

#>
param(
	[string] $ReferenceProjectName = $(throw 'Must provide a ReferenceProjectName'),
	[string] $TargetProjectName = $null,
	[string] $ApiToken = $(throw 'Must provide an ApiToken'),
	[Array]  $BlackList = @('asdfasdfasdf'),
	[switch] $RunForTarget,
	[switch] $RunForAll
)
try
{
	$BlackList | %{
		if ($ReferenceProjectName -eq $_)
		{
			throw "Can't use a blacklist project ($_) as a reference project..."
		}
		
		if ($TargetProjectName -eq $_)
		{
			throw "Can't use a blacklist project ($_) as a target project..."
		}
	}
	
	if ($RunForAll -and (-not [String]::IsNullOrEmpty($TargetProjectName)))
	{
		throw "Can't run as 'RunForAll'  with a target project name"
	}
	
	if ($RunForTarget -and [String]::IsNullOrEmpty($TargetProjectName))
	{
		throw "Can't run as 'RunForTarget'  without a target project name"
	}

	if ($RunForAll -or $RunForTarget)
	{
		$headers = @{
		  "Authorization" = "Bearer $ApiToken"
		  "Content-type" = "application/json"
		  "Accept" = "application/json"
		}

		$projects = Invoke-RestMethod -Uri 'https://ci.appveyor.com/api/projects' -Headers $headers -Method Get
		$projects = $projects | ?{ -not $BlackList.Contains($_.name) }
		
		$referenceProject = $projects | ?{ $_.name -eq $ReferenceProjectName }
		$referenceProjectSettingsUrl = "https://ci.appveyor.com/api/projects/$($referenceProject.accountName)/$($referenceProject.slug)/settings/yaml"
		$referenceProjectYaml = Invoke-RestMethod -Uri $referenceProjectSettingsUrl -Headers $headers -Method Get -ContentType "plain/text"
        $referenceBuild = $referenceProjectYaml.Split([Environment]::NewLine)[0]
		
		Write-Host -ForegroundColor Magenta ">BEGIN Reference Project YAML ($ReferenceProjectName)"
		Write-Host $referenceProjectYaml
		Write-Host -ForegroundColor Magenta "<END Reference Project YAML ($ReferenceProjectName)"

		$projects | ?{ $_.name -ne $ReferenceProjectName } | %{
			if ([String]::IsNullOrEmpty($TargetProjectName) -or ($TargetProjectName -eq $_.name))
			{
                # Make sure that we do not overwrite unique settings (like the build version pattern which could have been manually manipulated)
                $existingProjectSettingsUrl = "https://ci.appveyor.com/api/projects/$($_.accountName)/$($_.slug)/settings/yaml"
                $existingProjectYaml = Invoke-RestMethod -Uri $existingProjectSettingsUrl -Headers $headers -Method Get -ContentType "plain/text"
                $existingBuild = $existingProjectYaml.Split([Environment]::NewLine)[0]

                $newYaml = $referenceProjectYaml.Replace($referenceBuild, $existingBuild)
            
				$settingsUrl = "https://ci.appveyor.com/api/projects/$($_.accountName)/$($_.slug)/settings/yaml"

                Write-Host -ForegroundColor Magenta ">BEGIN Updating $($_.name) with new YAML; updated from ($referenceProjectName)"

                Write-Host -ForegroundColor Magenta "-> START updated YAML"
                Write-Output $newYaml
                Write-Host -ForegroundColor Magenta "<-END updated YAML"

				$putResponse = Invoke-WebRequest -Uri $settingsUrl -Headers $headers -Method Put -ContentType "plain/text" -Body $newYaml
				$responseCode = $putResponse.StatusCode

				Write-Host "<Response was '$responseCode' (204 is expected if successful)"

				if ($responseCode -ne '204')
				{
					throw "Expected a response code of 204 and instead got $responseCode, please investigate..."
				}
				
                Write-Host -ForegroundColor Magenta "<END Updating $($_.name) with new YAML; updated from ($referenceProjectName)"
				Write-Host ''
			}
		}
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
