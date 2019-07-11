# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Description
	This is a script that performs a cleanup on LISAv2 Azure Storage Blobs.
#>

param(
	[String] $customSecretsFilePath,
	[String] $storageAccountPrefixes,
	[String] $blobPrefixes,
	[int] $CleanupAgeInDays,
	[switch] $Remove
)

if (!$blobPrefixes) {
	$secretsFile = $env:Azure_Secrets_File
	Write-Host "ERROR: The param 'blobPrefixes' is undefined or null, please specify a value."
	exit 1
}
if ( $customSecretsFilePath ) {
	$secretsFile = $customSecretsFilePath
	Write-Host "INFO: Using provided secrets file: $($secretsFile | Split-Path -Leaf)"
}
if ($env:Azure_Secrets_File) {
	$secretsFile = $env:Azure_Secrets_File
	Write-Host "INFO: Using predefined secrets file: $($secretsFile | Split-Path -Leaf) in Jenkins Global Environments."
}
if ( $null -eq $secretsFile ) {
	Write-Host "ERROR: Azure Secrets file not found in Jenkins / user not provided -customSecretsFilePath" -ForegroundColor Red -BackgroundColor Black
	exit 1
}
if ( Test-Path $secretsFile) {
	Write-Host "INFO: $($secretsFile | Split-Path -Leaf) found."
	.\Utilities\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath $secretsFile
}
else {
	Write-Host "ERROR: $($secretsFile | Split-Path -Leaf) file is not added in Jenkins Global Environments OR it is not bound to 'Azure_Secrets_File' variable." -ForegroundColor Red -BackgroundColor Black
	Write-Host "Aborting." -ForegroundColor Red -BackgroundColor Black
	exit 1
}

$currentTimeStamp = Get-Date
$fileName = [System.IO.Path]::GetFileNameWithoutExtension($customSecretsFilePath)
$cleanUpBlobsFileName = "$fileName-Blobs.txt"
if ([System.IO.File]::Exists($cleanUpBlobsFileName)) {
	Remove-Item $cleanUpBlobsFileName
}

$allStorageAccounts = Get-AzStorageAccount
if( $storageAccountPrefixes ){
	$allCleanupStorageAccounts = $allStorageAccounts | where { $_.StorageAccountName -match "^($storageAccountPrefixes)" }
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
	#$containers = Get-AzStorageContainer -Context $context
	$containerName = 'vhds'
	Get-AzStorageContainer -Context $context -Container $containerName -ErrorAction SilentlyContinue | Out-Null
	if( !$? ){
		Write-Host "INFO: Can't find the container `'$containerName`' in storage account `'$StorageAccountName`'"
		continue
	}
	Write-Host "INFO: Scanning blobs in container `'$containerName`' in storage account `'$StorageAccountName`' in resource group `'$ResourceGroupName`'"
	$blobs = Get-AzStorageBlob -Context $context -Container $containerName | where { $_.Name.ToLower().EndsWith('.vhd') -and ($_.Name -match "^($blobPrefixes)")}
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
				Write-Host "INFO: $counter. Remove blob `'$blobName`'"
				Remove-AzStorageBlob -Context $context -Container $containerName -Blob $blobName -Verbose -Force
			}
		}
	}
}

if ( $counter -gt 0 ){
	if ( $Remove ){
		Write-Host "INFO: Totally $counter blobs have been deleted, please browse file `'$cleanUpBlobsFileName`' for details"
	}
	else{
		Write-Host "INFO: Totally $counter blobs need to be deleted, please browse file `'$cleanUpBlobsFileName`' for details"
	}
	Out-String -InputObject $cleanupBlobs -Width 4096 | Out-File $cleanUpBlobsFileName
}
else{
	Write-Host "INFO: Not found matching blobs"
}
