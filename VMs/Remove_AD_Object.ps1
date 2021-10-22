$vmlist = "ORR-800-V"
$adcred = Get-Credential

foreach ($vm in $vmlist)
{
    $search = Get-ADComputer -Identity $vm -ErrorAction SilentlyContinue

    if ($null -eq $search)
    {
        Write-Host "This object name either doesn't exist in AD, or someone has deleted the object prior to this operation" -ForegroundColor Yellow
    } else {
        Get-ADComputer -Identity $vm | Remove-ADObject -Credential $adcred -Confirm:$false -Recursive
        Write-Host $vm "was successfully taken out of AD" -ForegroundColor Green
    }
}
