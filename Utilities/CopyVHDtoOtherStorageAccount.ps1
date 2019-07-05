##############################################################################################
# CopyVHDtoOtherStorageAccounts.ps1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
    This script copies VHD file to another storage account.

.PARAMETER

.INPUTS

.NOTES
    Creation Date:
    Purpose/Change:

.EXAMPLE
#>
###############################################################################################

param
(
    [string]$sourceLocation,
    [string]$destinationLocations,
    [string]$destinationAccountType,
    [string]$sourceVHDName,
    [string]$destinationVHDName,
    [string]$LogFileName = "CopyVHDtoOtherStorageAccount.log"
)
if (!$global:LogFileName){
    Set-Variable -Name LogFileName -Value $LogFileName -Scope Global -Force
}
Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force -Global -DisableNameChecking }

try
{
    if (!$destinationVHDName)
    {
        $destinationVHDName = $sourceVHDName
    }
    if (!$destinationAccountType)
    {
        $destinationAccountType="Standard,Premium"
    }

    $RegionName = $sourceLocation.Replace(" ","").Replace('"',"").ToLower()
    $RegionStorageMapping = [xml](Get-Content .\XML\RegionAndStorageAccounts.xml)
    $SourceStorageAccountName = $RegionStorageMapping.AllRegions.$RegionName.StandardStorage

    #region Collect current VHD, Storage Account and Key
    $saInfoCollected = $false
    $retryCount = 0
    $maxRetryCount = 999
    while(!$saInfoCollected -and ($retryCount -lt $maxRetryCount))
    {
        try
        {
            $retryCount += 1
            Write-LogInfo "[Attempt $retryCount/$maxRetryCount] : Getting Storage Account details ..."
            $GetAzureRMStorageAccount = $null
            $GetAzureRMStorageAccount = Get-AzStorageAccount
            if ($GetAzureRMStorageAccount -eq $null)
            {
                $saInfoCollected = $false
            }
            else
            {
                $saInfoCollected = $true
            }
        }
        catch
        {
            Write-LogErr "Error in fetching Storage Account info. Retrying in 10 seconds."
            sleep -Seconds 10
            $saInfoCollected = $false
        }
    }
    #endregion

    $currentVHDName = $sourceVHDName
    $testStorageAccount = $SourceStorageAccountName
    $testStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $(($GetAzureRmStorageAccount  | Where {$_.StorageAccountName -eq "$testStorageAccount"}).ResourceGroupName) -Name $testStorageAccount)[0].Value

    $targetRegions = (Get-AzLocation).Location
    if ($destinationLocations)
    {
        $targetRegions = $destinationLocations.Split(",")
    }
    else
    {
        $targetRegions = (Get-AzLocation).Location
    }
    $targetStorageAccounts = @()
    foreach ($newRegion in $targetRegions)
    {
        if ( $destinationAccountType -imatch "Standard")
        {
            $targetStorageAccounts +=  $RegionStorageMapping.AllRegions.$newRegion.StandardStorage
        }
        if ( $destinationAccountType -imatch "Premium")
        {
            $targetStorageAccounts +=  $RegionStorageMapping.AllRegions.$newRegion.PremiumStorage
        }
    }
    $destContextArr = @()
    foreach ($targetSA in $targetStorageAccounts)
    {
        #region Copy as Latest VHD
        [string]$SrcStorageAccount = $testStorageAccount
        [string]$SrcStorageBlob = $currentVHDName
        $SrcStorageAccountKey = $testStorageAccountKey
        $SrcStorageContainer = "vhds"

        [string]$DestAccountName =  $targetSA
        [string]$DestBlob = $destinationVHDName
        $DestAccountKey= (Get-AzStorageAccountKey -ResourceGroupName $(($GetAzureRmStorageAccount  | Where {$_.StorageAccountName -eq "$targetSA"}).ResourceGroupName) -Name $targetSA)[0].Value
        $DestContainer = "vhds"
        $context = New-AzStorageContext -StorageAccountName $srcStorageAccount -StorageAccountKey $srcStorageAccountKey
        $expireTime = Get-Date
        $expireTime = $expireTime.AddYears(1)
        $SasUrl = New-AzStorageBlobSASToken -container $srcStorageContainer -Blob $srcStorageBlob -Permission R -ExpiryTime $expireTime -FullUri -Context $Context

        #
        # Start Replication to DogFood
        #

        $destContext = New-AzStorageContext -StorageAccountName $destAccountName -StorageAccountKey $destAccountKey
        $testContainer = Get-AzStorageContainer -Name $destContainer -Context $destContext -ErrorAction Ignore
        if ($testContainer -eq $null) {
            New-AzStorageContainer -Name $destContainer -context $destContext
        }
        # Start the Copy
        if (($SrcStorageAccount -eq $DestAccountName) -and ($SrcStorageBlob -eq $DestBlob))
        {
            Write-LogInfo "Skipping copy for : $DestAccountName as source storage account and VHD name is same."
        }
        else
        {
            Write-LogInfo "Copying $SrcStorageBlob as $DestBlob from and to storage account $DestAccountName/$DestContainer"
            $null = Start-AzStorageBlobCopy -AbsoluteUri $SasUrl  -DestContainer $destContainer -DestContext $destContext -DestBlob $destBlob -Force
            $destContextArr += $destContext
        }
    }
    #
    # Monitor replication status
    #
    $CopyingInProgress = $true
    while($CopyingInProgress)
    {
        $CopyingInProgress = $false
        $newDestContextArr = @()
        foreach ($destContext in $destContextArr)
        {
            $status = Get-AzStorageBlobCopyState -Container $destContainer -Blob $destBlob -Context $destContext
            if ($status.Status -eq "Success")
            {
                Write-LogInfo "$DestBlob : $($destContext.StorageAccountName) : Done : 100 %"
            }
            elseif ($status.Status -eq "Failed")
            {
                Write-LogInfo "$DestBlob : $($destContext.StorageAccountName) : Failed."
            }
            elseif ($status.Status -eq "Pending")
            {
                sleep -Milliseconds 100
                $CopyingInProgress = $true
                $newDestContextArr += $destContext
                $copyPercent = [math]::Round((($status.BytesCopied/$status.TotalBytes) * 100),2)
                Write-LogInfo "$DestBlob : $($destContext.StorageAccountName) : Running : $copyPercent %"
            }
        }
        if ($CopyingInProgress)
        {
            Write-LogInfo "--------$($newDestContextArr.Count) copy operations still in progress.-------"
            $destContextArr = $newDestContextArr
            Sleep -Seconds 10
        }
        $ExitCode = 0
    }
    Write-LogInfo "All Copy Operations completed successfully."
}
catch
{
    $ExitCode = 1
    Raise-Exception ($_)
}
finally
{
    Write-LogInfo "Exiting with code: $ExitCode"
    exit $ExitCode
}
#endregion
