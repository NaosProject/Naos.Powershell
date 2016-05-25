nuget pack ./Build/Naos.Powershell.Build.nuspec -Version $env:APPVEYOR_BUILD_VERSION
$nupkgFile = (ls . -Filter *.nupkg).FullName
nuget push $nupkgFile $env:nuget_api_key -Source $env:nuget_gallery_url