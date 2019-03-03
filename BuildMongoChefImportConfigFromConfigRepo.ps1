# EXAMPLE USE: ./BuildMongoChefImportConfigFromConfigRepo.ps1 -configRepoPath 'D:\SourceCode\Naos\Naos.Config'  | out-file 'ExportedConnections.uri' -encoding UTF8

param([string] $configRepoPath)

$configFolderToScan = $configRepoPath

function GetConfigValue([string] $targetValue) {
            $matchString = '("TOKEN": )(")(\w*.*)(")'.Replace('TOKEN', $targetValue)
            $match = [System.Text.RegularExpressions.Regex]::Match($fileContents, $matchString)
            if (-not $match.Success) {
                throw "Could not find 'server' in $file"
            }
            
            $result = $match.Captures.Groups[3].Value
            return $result
}

Write-Output "// Connections Exported from $(Split-Path $configFolderToScan -Leaf) -- $configFolderToScan"
Write-Output "// Exported on $([System.DateTime]::UtcNow.ToString()) UTC"
Write-Output ''

$allConnectionFolders = ls $configFolderToScan -recurse -filter *connection* | ?{$_.PSIsContainer} | %{$_.FullName}
$allConnectionFolders | %{
    $folderName = $_
    $configFolder = Join-Path $folderName '.config'
    $environmentFolders = ls $configFolder | ?{$_.PSIsContainer} | %{$_.FullName}
    $environmentFolders | %{
        $environmentFolder = $_
        $environment = Split-Path $environmentFolder -Leaf
        $files = (ls $environmentFolder).FullName
        if ($files -is [array]) {
            throw "'$environmentFolder' contains more than one file, this is unexpected."
        }
        
        $file = $files # at this point we know this is just a single connection file
        $fileContents = [System.IO.File]::ReadAllText($file)
        if ($fileContents.Contains('"port": 27017')) { # For now this is good enough to detect mongo...
            $server = GetConfigValue -targetValue 'server'
            $user = GetConfigValue -targetValue 'user'
            $password = GetConfigValue -targetValue 'password'
            $escapedPassword = [System.Net.WebUtility]::UrlEncode($password)
            $databaseName = GetConfigValue -targetValue 'database'
            $name = "$databaseName | $environment"
            $escapedName = $name.Replace(' ', '+')
            $connection = "mongodb://$($user):$($escapedPassword)@$($server):27017/$($databaseName)?3t.connection.name=$($escapedName)&3t.uriVersion=2&3t.connectionMode=direct&readPreference=primary"
            Write-Output "// $name"
            Write-Output "$connection"
            Write-Output ''
        }
    }
}