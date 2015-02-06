$sleepTimeInSeconds = 60
$destination = '10.23.12.18'
$sourceComputer = $env:computername
Write-Output "SourceComputer,Time,Destination,Result,Command"
1..2147483647 | %{
	$command = 'Test-Connection -ComputerName $destination -BufferSize 16 -Count 5 -ErrorAction 0 -Quiet'
	$pingResult = Test-Connection -ComputerName $destination -BufferSize 16 -Count 5 -ErrorAction 0 -Quiet
	Write-Output "$sourceComputer,$([DateTime]::Now),$destination,$pingResult,$command"
	Start-Sleep $sleepTimeInSeconds
}
