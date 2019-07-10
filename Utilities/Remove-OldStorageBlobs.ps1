# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Description
        This is a script that performs a cleanup on LISAv2 Azure Storage Blobs.
#>

param(
    [String] $customSecretsFilePath,
    [String] $StorageAccounts = "",
    [int] $CleanupAgeInDays,
    [switch] $Remove,
    [switch] $DryRun
)

if ( $customSecretsFilePath ) {
    $secretsFile = $customSecretsFilePath
    Write-Host "Using provided secrets file: $($secretsFile | Split-Path -Leaf)"
}
if ($env:Azure_Secrets_File) {
    $secretsFile = $env:Azure_Secrets_File
    Write-Host "Using predefined secrets file: $($secretsFile | Split-Path -Leaf) in Jenkins Global Environments."
}
if ( $null -eq $secretsFile ) {
    Write-Host "ERROR: Azure Secrets file not found in Jenkins / user not provided -customSecretsFilePath" -ForegroundColor Red -BackgroundColor Black
    exit 1
}
if ( Test-Path $secretsFile) {
    Write-Host "$($secretsFile | Split-Path -Leaf) found."
    .\Utilities\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath $secretsFile
}
else {
    Write-Host "$($secretsFile | Split-Path -Leaf) file is not added in Jenkins Global Environments OR it is not bound to 'Azure_Secrets_File' variable." -ForegroundColor Red -BackgroundColor Black
    Write-Host "Aborting." -ForegroundColor Red -BackgroundColor Black
    exit 1
}

$currentTimeStamp = Get-Date
$allStorageAccounts = Get-AzStorageAccount

if( $StorageAccounts ){
	$allCleanupStorageAccounts = $allStorageAccounts | where { $_.StorageAccountName -in $StorageAccounts.Split(',') }
}
else{
	$allCleanupStorageAccounts = $allStorageAccounts
}

$counter = 0
$cleanupBlobs = @()
foreach ( $storageAccount in $allCleanupStorageAccounts ) {
	$ResourceGroupName = $storageAccount.ResourceGroupName
	$StorageAccountName = $storageAccount.StorageAccountName
	$storageAccountKey = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
	$context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey.Value[0]
	$containers = Get-AzStorageContainer -Context $context
	foreach ( $container in $containers ){
		$containerName = $container.Name
		$blobs = Get-AzStorageBlob -Context $context -Container $containerName | where { $_.Name.ToLower().EndsWith('.vhd')}		
		foreach ( $blob in $blobs ) {
			$blobName = $blob.Name
			$blobProperties = $blob.ICloudBlob.Properties
			$blobLastModified = $blobProperties.LastModified.UtcDateTime
			$blobLease = $blobProperties.LeaseStatus
			$elaplsedDays = ($($currentTimeStamp - $blobLastModified)).Days			
			if ( ($elaplsedDays -gt $CleanupAgeInDays) -and ($blobLease -ne 'Locked') ){
				$counter ++
				$element = [PSCustomObject]@{ResourceGroup=$ResourceGroupName; StorageAccount=$StorageAccountName; container=$containerName; blob=$blobName}
				$cleanupBlobs += $element
				if( $Remove ){
					if ( -not $DryRun ) {
						Write-Host "Start to remove blob $blobName"
						Remove-AzStorageBlob -Context $context -Container $containerName -Blob $blobName -Verbose -Force
					}
				}
			}
		}
	}
}

if ( $counter -gt 0 )
{
	Write-Host "All the cleanup blobs: "
	$cleanupBlobs | Out-String -Width 4096
}
else
{
	Write-Host "Not found matching blobs"	
}
