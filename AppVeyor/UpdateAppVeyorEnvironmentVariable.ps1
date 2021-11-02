<#
.SYNOPSIS 
Takes the new environment variable value and updates all projects.

.DESCRIPTION
Takes the new environment variable value and updates all projects.

.PARAMETER EnvVarName
The name of the environment variable to update.

.PARAMETER EnvVarValue
The new environment variable value to use.

.PARAMETER ApiToken
The AppVeyor provided API Token.

.PARAMETER RunForAll
Run the udpate for every build project.

.EXAMPLE
.\UpdateAppVeyorEnvironmentVariable.ps1 -NewNuGetKey 'Naos.Utils.Database' -RunForAll

#>
param(
	[string] $EnvVarName = $(throw 'Must provide an environment variable name.'),
	[string] $EnvVarValue = $(throw 'Must provide an environment variable value'),
	[string] $ApiToken = $(throw 'Must provide an ApiToken'),
	[switch] $RunForAll)
try
{	
	if (-not $RunForAll)
	{
		throw "Specify the 'RunForAll' switch to run the logic."
	}

	if ($RunForAll)
	{
		$headers = @{
		  "Authorization" = "Bearer $ApiToken"
		  "Content-type" = "application/json"
		  "Accept" = "application/json"
		}

        $scriptBackupFileTimeStamp = [DateTime]::UtcNow.ToString('yyyyMMdd_HHmm')

		$projects = Invoke-RestMethod -Uri 'https://ci.appveyor.com/api/projects' -Headers $headers -Method Get

		$projects | %{
            $settingsUrl = "https://ci.appveyor.com/api/projects/$($_.accountName)/$($_.slug)/settings/environment-variables"
            $existingJson = Invoke-WebRequest -UseBasicParsing -Uri $settingsUrl -Headers $headers -Method Get -ContentType "application/json"
            $existing = ConvertFrom-Json $existingJson
            $existing | %{
                if ($_.name -eq $EnvVarName)
                {
                    $_.value.value = $EnvVarValue
                }
            }
            
            #$newJson = ConvertTo-Json $existing #does a double nested value thing...
            $newjson = '['
            $existing | %{
               $newjson = $newjson + "{ `"name`": `"$($_.name)`", `"value`": {`"isencrypted`": `"$($_.value.isencrypted)`", `"value`": `"$($_.value.value)`" } },"
            }
            $newjson = $newjson + ']'
            
            $envSettingsUrl = "https://ci.appveyor.com/api/projects/$($_.accountName)/$($_.slug)/settings/environment-variables/"
            Write-Host -ForegroundColor Magenta ">BEGIN Updating $($_.name) with new NuGet API Key"

            $putResponse = Invoke-WebRequest -UseBasicParsing -Uri $envSettingsUrl -Headers $headers -Method Put -ContentType "application/json" -Body $newJson
            $responseCode = $putResponse.StatusCode

            Write-Host "-- Response was '$responseCode' (204 is expected if successful)"

            if ($responseCode -ne '204')
            {
                throw "Expected a response code of 204 and instead got $responseCode, please investigate..."
            }
            
            Write-Host -ForegroundColor Magenta "<END Updating $($_.name) with new NuGet key"
            Write-Host ''
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
