param (
    [Parameter(Mandatory=$true)] [String] $SrcPackagePath,
    [Parameter(Mandatory=$true)] [String] $ReportDestination,
    [String] $LogPath,
    [String] $TestCategory,
    [String] $ReportName,
    [String] $TestArea,
    [String] $TestNames,
    [Switch] $OverallReport,
    [bool] $RequiredTools = $True,
    [bool] $RequiredDaemons = $True,

    # LISAv2 Params
    [Parameter(Mandatory=$true)] [String] $RGIdentifier,
    [Parameter(Mandatory=$true)] [String] $TestPlatform,
    [Parameter(Mandatory=$true)] [String] $TestLocation,
    [Parameter(Mandatory=$true)] [String] $StorageAccount,
    [Parameter(Mandatory=$true)] [String] $XMLSecretFile
)

$ARM_IMAGE_NAME = "Canonical UbuntuServer 18.04-LTS latest"
$TAR_PATH = "$($env:ProgramFiles)\Git\usr\bin\tar.exe"
$CURRENT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$WORK_DIR = $CURRENT_DIR.Directory.FullName
# VM-HOT-RESIZE is not relevant for coverage
# PCI-DEVICE-DISABLE-ENABLE-SRIOV-NVME is deployed on L80_v2,
# uses too much quota and the same test is run on GPU and SRIOV
# Exclude GPU tests, NA for the kernel used
# Exclude some SR-IOV tests that take a long time to run
$EXCLUDED_TESTS = "VM-HOT-RESIZE,PCI-DEVICE-DISABLE-ENABLE-SRIOV-NVME,SRIOV-DISABLE-ENABLE-AN,SRIOV-IPERF-STRESS,KDUMP-CRASH-SMP,KDUMP-CRASH-AUTO-SIZE,KDUMP-CRASH-DIFFERENT-VCPU,NVME-FILE-SYSTEM-VERIFICATION-XFS,*NVIDIA*"

function Main {
    $SrcPackagePath = Resolve-Path $SrcPackagePath
    if ((-not $SrcPackagePath) -or (-not (Test-Path $SrcPackagePath))) {
        throw "Cannot find kernel source package"
    }

    $reportType = "report"
    if ($ReportName) {
        $reportType = $ReportName
    }elseif ($TestArea) {
        $reportType = $TestArea.ToLower()
    } else {
        $reportType = $TestCategory.ToLower()
    }

    $tests = @{}
    if ($TestArea) {
        $tests += @{"TestArea" = $TestArea}
    }
    if ($TestCategory) {
        $tests += @{"TestCategory" = $TestCategory}
    }
    if ($TestNames) {
        $tests = @{"TestNames" = $TestNames}
    }

    Push-Location $WORK_DIR

    if (-not $OverallReport) {
        Copy-Item -Path $SrcPackagePath "linux-source.deb"

        .\Run-LisaV2.ps1 -RGIdentifier $RGIdentifier -TestPlatform  $TestPlatform `
            -TestNames 'BUILD-GCOV-KERNEL' -TestLocation $TestLocation `
            -ARMImageName $ARM_IMAGE_NAME `
            -TestIterations 1 -StorageAccount $StorageAccount `
            -XMLSecretFile $XMLSecretFile

        $packagesPath = ".\CodeCoverage\artifacts\packages.tar"
        if (-not (Test-Path $packagesPath)) {
            throw "Cannot find kernel artifacts"
        } else {
            $packagesPath = Resolve-Path $packagesPath
            $packagesPath = Get-ChildItem $packagesPath
        }

        # some tests require tools or daemons to be installed
        if ($RequiredDaemons) {
            $LisDebPath=(Get-Item $SrcPackagePath).DirectoryName
            if (-not (Test-Path "$LisDebPath\hyperv-daemons*.deb")) {
                throw "Cannot find daemons for kernel"
            }
            Copy-Item -path "$LisDebPath\hyperv-daemons*.deb"  .\CodeCoverage\artifacts
        }
        if ($RequiredTools) {
            $LisDebPath=(Get-Item $SrcPackagePath).DirectoryName
            if (-not (Test-Path "$LisDebPath\hyperv-tools*.deb")) {
                throw "Cannot find tools for kernel"
            }
            Copy-Item -path "$LisDebPath\hyperv-tools*.deb"  .\CodeCoverage\artifacts
        }
        Push-Location $packagesPath.Directory.FullName
        & $TAR_PATH xf $packagesPath.Name
        Pop-Location

        .\Run-LisaV2.ps1 -RGIdentifier $RGIdentifier -TestPlatform  $TestPlatform `
            @tests -TestLocation $TestLocation `
            -ARMImageName $ARM_IMAGE_NAME `
            -TestIterations 1 -StorageAccount $StorageAccount `
            -XMLSecretFile $XMLSecretFile `
            -EnableCodeCoverage -CustomKernel "localfile:.\CodeCoverage\artifacts\*.deb" `
            -ExcludeTests "${EXCLUDED_TESTS}"

        if ($LogPath) {
            if (-not (Test-Path $LogPath)) {
                New-Item -Path $LogPath -Type Directory
            }
            if (-not (Test-Path "${LogPath}\logs")) {
                New-Item -Path "${LogPath}\logs" -Type Directory
            }

            Copy-Item -Recurse -Path ".\CodeCoverage\logs\*" -Destination "${LogPath}\logs\" -Force
            Copy-Item -Recurse -Path ".\CodeCoverage\artifacts" -Destination "${LogPath}\" -Force
        }
    } else {
        $reportType = "overall"
        if (-not (Test-Path $LogPath)) {
            throw "Cannot find logs dir"
        }

        $artifactsPath = Join-Path $LogPath "artifacts"
        $logsPath = Join-Path $LogPath "logs"

        if ((-not (Test-Path $artifactsPath)) -or (-not (Test-Path $logsPath))) {
            throw "Cannot find logs"
        }
        if (Test-Path ".\CodeCoverage") {
            Remove-Item -Recurse -Path ".\CodeCoverage"
        }
        New-Item -Path ".\CodeCoverage" -Type Directory

        Copy-Item -Recurse -Path $artifactsPath -Destination ".\CodeCoverage"
        Copy-Item -Recurse -Path $logsPath -Destination ".\CodeCoverage"
    }

    .\Run-LisaV2.ps1 -RGIdentifier $RGIdentifier -TestPlatform  $TestPlatform `
        -TestNames "BUILD-GCOV-REPORT" -TestLocation $TestLocation `
        -ARMImageName $ARM_IMAGE_NAME `
        -TestIterations 1 -StorageAccount $StorageAccount `
        -XMLSecretFile $XMLSecretFile `
        -CustomTestParameters "GCOV_REPORT_CATEGORY=${reportType}"

    $reportsPath = ".\CodeCoverage\${reportType}.zip"
    if (-not (Test-Path $reportsPath)) {
        throw "Cannot find GCOV html report archive"
    }

    if (-not (Test-Path $ReportDestination)) {
        New-Item -Path $ReportDestination -Type Directory
    }
    $ReportDestination = Join-Path $ReportDestination $reportType
    if (Test-Path $ReportDestination) {
        Remove-Item -Path $ReportDestination -Recurse -Force
    }
    New-Item -Path $ReportDestination -Type Directory

    Expand-Archive -Path $reportsPath -DestinationPath $ReportDestination
    Pop-Location
}

Main
