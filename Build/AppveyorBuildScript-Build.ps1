# PASTE THIS INTO APPVEYOUR - Build

rm *.nupkg # make sure one doesnt get checked in by accident and used...
nuget pack ./Naos.Build.nuspec -Version $env:APPVEYOR_BUILD_VERSION
$nupkgFile = (ls . -Filter *.nupkg).FullName
nuget push $nupkgFile $env:nuget_api_key -Source $env:nuget_gallery_url
nuget push $nupkgFile $env:myget_api_key -Source $env:myget_gallery_url