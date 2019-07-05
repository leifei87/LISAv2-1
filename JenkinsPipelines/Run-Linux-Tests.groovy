// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the Apache License.

def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
    //powershell (psCmd)
}

def GetFinalVHDName (CustomVHD)
{
    def FinalVHDName = ""
    if (CustomVHD.endsWith("vhd.xz"))
    {
        FinalVHDName = UpstreamBuildNumber + "-" + CustomVHD.replace(".vhd.xz",".vhd")
    }
    else if (CustomVHD.endsWith("vhdx.xz"))
    {
        FinalVHDName = UpstreamBuildNumber + "-" + CustomVHD.replace(".vhdx.xz",".vhd")
    }
    else if (CustomVHD.endsWith("vhdx"))
    {
        FinalVHDName = UpstreamBuildNumber + "-" + CustomVHD.replace(".vhdx",".vhd")
    }
    else if (CustomVHD.endsWith("vhd"))
    {
        FinalVHDName = UpstreamBuildNumber + "-" + CustomVHD
    }
    return FinalVHDName
}

def ExecuteTest( JenkinsUser, UpstreamBuildNumber, ImageSource, OverrideVMSize, CustomVHD, CustomVHDURL,
                    Kernel, CustomKernelFile, CustomKernelURL, StorageAccount, DiskType, GitUrlForAutomation,
                    GitBranchForAutomation, TestByTestname, TestByCategorisedTestname, TestByCategory, TestByTag,
                    Email, debug, TiPCluster, TipSessionId )
{
    if( (TestByTestname != "" && TestByTestname != null) || (TestByCategorisedTestname != "" && TestByCategorisedTestname != null) || (TestByCategory != "" && TestByCategory != null) || (TestByTag != "" && TestByTag != null) )
    {
        node('azure')
        {
            //Define Varialbles
            def FinalVHDName = ""
            def FinalImageSource = ""
            def EmailSubject = ""

            //Select ARM Image / Custom VHD
            if ((CustomVHD != "" && CustomVHD != null) || (CustomVHDURL != "" && CustomVHDURL != null))
            {
                unstash 'CustomVHD'
                FinalVHDName = readFile 'CustomVHD.azure.env'
                FinalImageSource = " -OsVHD '${FinalVHDName}'"
                EmailSubject = FinalVHDName
            }
            else
            {
                FinalImageSource = " -ARMImageName '${ImageSource}'"
                EmailSubject = ImageSource
            }

            if ( (CustomKernelFile != "" && CustomKernelFile != null) || (CustomKernelURL != "" && CustomKernelURL != null) || (Kernel != "default") )
            {
                unstash "CapturedVHD.azure.env"
                FinalImageSource = readFile "CapturedVHD.azure.env"
                FinalImageSource = " -OsVHD ${FinalImageSource}"
            }

            if ((OverrideVMSize != "" && OverrideVMSize != null)) {
                FinalVMSize = " -OverrideVMSize '${OverrideVMSize}'"
            } else {
                FinalVMSize = " -OverrideVMSize ''"
            }

            if (TestByTestname != "" && TestByTestname != null && (!(TestByTestname ==~ "Select a.*")))
            {
                def CurrentTests = [failFast: false]
                for ( i = 0; i < TestByTestname.split(",").length; i++)
                {
                    def CurrentCounter = i
                    def CurrentExecution = TestByTestname.split(",")[CurrentCounter]
                    def CurrentExecutionName = CurrentExecution.replace(">>"," ")
                    CurrentTests["${CurrentExecutionName}"] =
                    {
                        try
                        {
                            timeout (10800)
                            {
                                stage ("${CurrentExecutionName}")
                                {
                                    node('azure')
                                    {
                                        println(CurrentExecution)
                                        def TestPlatform = CurrentExecution.split(">>")[0]
                                        def Testname = CurrentExecution.split(">>")[1]
                                        def TestRegion = CurrentExecution.split(">>")[2]
                                        Prepare()
                                        withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
                                        {
                                            RunPowershellCommand(".\\Run-LisaV2.ps1" +
                                            " -ExitWithZero" +
                                            " -XMLSecretFile '${Azure_Secrets_File}'" +
                                            " -TestLocation '${TestRegion}'" +
                                            " -RGIdentifier '${JenkinsUser}'" +
                                            " -TestPlatform '${TestPlatform}'" +
                                            " -StorageAccount '${StorageAccount}'" +
                                            " -CustomParameters 'DiskType=${DiskType};TiPCluster=${TiPCluster};TipSessionId=${TipSessionId}'" +
                                            FinalImageSource +
                                            FinalVMSize +
                                            " -TestNames '${Testname}'"
                                            )
                                            archiveArtifacts '*-TestLogs.zip'
                                            junit "Report\\*-junit.xml"
                                            emailext body: '${SCRIPT, template="groovy-html.template"}', replyTo: '$DEFAULT_REPLYTO', subject: "${ImageSource}", to: "${Email}"
                                        }
                                    }
                                }
                            }
                        }
                        catch (exc)
                        {
                            currentBuild.result = 'FAILURE'
                            println "STAGE_FAILED_EXCEPTION."
                        }
                        finally
                        {
                        }
                    }
                }
                parallel CurrentTests
            }
            if (TestByCategorisedTestname != "" && TestByCategorisedTestname != null && (!(TestByCategorisedTestname ==~ "Select a.*")))
            {
                def CurrentTests = [failFast: false]
                for ( i = 0; i < TestByCategorisedTestname.split(",").length; i++)
                {
                    def CurrentCounter = i
                    def CurrentExecution = TestByCategorisedTestname.split(",")[CurrentCounter]
                    def CurrentExecutionName = CurrentExecution.replace(">>"," ")
                    CurrentTests["${CurrentExecutionName}"] =
                    {
                        try
                        {
                            timeout (10800)
                            {
                                stage ("${CurrentExecutionName}")
                                {
                                    node('azure')
                                    {
                                        println(CurrentExecution)
                                        def TestPlatform = CurrentExecution.split(">>")[0]
                                        def TestCategory = CurrentExecution.split(">>")[1]
                                        def TestArea = CurrentExecution.split(">>")[2]
                                        def TestName = CurrentExecution.split(">>")[3]
                                        def TestRegion = CurrentExecution.split(">>")[4]
                                        Prepare()
                                        withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
                                        {
                                            RunPowershellCommand(".\\Run-LisaV2.ps1" +
                                            " -ExitWithZero" +
                                            " -XMLSecretFile '${Azure_Secrets_File}'" +
                                            " -TestLocation '${TestRegion}'" +
                                            " -RGIdentifier '${JenkinsUser}'" +
                                            " -TestPlatform '${TestPlatform}'" +
                                            " -StorageAccount '${StorageAccount}'" +
                                            " -CustomParameters 'DiskType=${DiskType};TiPCluster=${TiPCluster};TipSessionId=${TipSessionId}'" +
                                            FinalImageSource +
                                            FinalVMSize +
                                            " -TestNames '${TestName}'"
                                            )
                                            archiveArtifacts '*-TestLogs.zip'
                                            junit "Report\\*-junit.xml"
                                            emailext body: '${SCRIPT, template="groovy-html.template"}', replyTo: '$DEFAULT_REPLYTO', subject: "${ImageSource}", to: "${Email}"
                                        }
                                    }
                                }
                            }
                        }
                        catch (exc)
                        {
                            currentBuild.result = 'FAILURE'
                            println "STAGE_FAILED_EXCEPTION."
                        }
                        finally
                        {
                        }
                    }
                }
                parallel CurrentTests
            }
            if (TestByCategory != "" && TestByCategory != null && (!(TestByCategory ==~ "Select a.*")))
            {
                def CurrentTests = [failFast: false]
                for ( i = 0; i < TestByCategory.split(",").length; i++)
                {
                    def CurrentCounter = i
                    def CurrentExecution = TestByCategory.split(",")[CurrentCounter]
                    def CurrentExecutionName = CurrentExecution.replace(">>"," ")
                    CurrentTests["${CurrentExecutionName}"] =
                    {
                        try
                        {
                            timeout (10800)
                            {
                                stage ("${CurrentExecutionName}")
                                {
                                    node('azure')
                                    {
                                        println(CurrentExecution)
                                        def TestPlatform = CurrentExecution.split(">>")[0]
                                        def TestCategory = CurrentExecution.split(">>")[1]
                                        def TestArea = CurrentExecution.split(">>")[2]
                                        def TestRegion = CurrentExecution.split(">>")[3]
                                        Prepare()
                                        withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
                                        {
                                            RunPowershellCommand(".\\Run-LisaV2.ps1" +
                                            " -ExitWithZero" +
                                            " -XMLSecretFile '${Azure_Secrets_File}'" +
                                            " -TestLocation '${TestRegion}'" +
                                            " -RGIdentifier '${JenkinsUser}'" +
                                            " -TestPlatform '${TestPlatform}'" +
                                            " -TestCategory '${TestCategory}'" +
                                            " -TestArea '${TestArea}'" +
                                            " -StorageAccount '${StorageAccount}'" +
                                            " -CustomParameters 'DiskType=${DiskType};TiPCluster=${TiPCluster};TipSessionId=${TipSessionId}'" +
                                            FinalImageSource +
                                            FinalVMSize
                                            )
                                            archiveArtifacts '*-TestLogs.zip'
                                            junit "Report\\*-junit.xml"
                                            emailext body: '${SCRIPT, template="groovy-html.template"}', replyTo: '$DEFAULT_REPLYTO', subject: "${ImageSource}", to: "${Email}"
                                        }
                                    }
                                }
                            }
                        }
                        catch (exc)
                        {
                            currentBuild.result = 'FAILURE'
                            println "STAGE_FAILED_EXCEPTION."
                        }
                        finally
                        {
                        }
                    }
                }
                parallel CurrentTests
            }
            if (TestByTag != "" && TestByTag != null && (!(TestByTag ==~ "Select a.*")))
            {
                def CurrentTests = [failFast: false]
                for ( i = 0; i < TestByTag.split(",").length; i++)
                {
                    def CurrentCounter = i
                    def CurrentExecution = TestByTag.split(",")[CurrentCounter]
                    def CurrentExecutionName = CurrentExecution.replace(">>"," ")
                    CurrentTests["${CurrentExecutionName}"] =
                    {
                        try
                        {
                            timeout (10800)
                            {
                                stage ("${CurrentExecutionName}")
                                {
                                    node('azure')
                                    {
                                        println(CurrentExecution)
                                        def TestPlatform = CurrentExecution.split(">>")[0]
                                        def TestTag = CurrentExecution.split(">>")[1]
                                        def TestRegion = CurrentExecution.split(">>")[2]
                                        Prepare()
                                        withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
                                        {
                                            RunPowershellCommand(".\\Run-LisaV2.ps1" +
                                            " -ExitWithZero" +
                                            " -XMLSecretFile '${Azure_Secrets_File}'" +
                                            " -TestLocation '${TestRegion}'" +
                                            " -RGIdentifier '${JenkinsUser}'" +
                                            " -TestPlatform '${TestPlatform}'" +
                                            " -TestTag '${TestTag}'" +
                                            " -StorageAccount '${StorageAccount}'" +
                                            " -CustomParameters 'DiskType=${DiskType};TiPCluster=${TiPCluster};TipSessionId=${TipSessionId}'" +
                                            FinalImageSource +
                                            FinalVMSize
                                            )
                                            archiveArtifacts '*-TestLogs.zip'
                                            junit "Report\\*-junit.xml"
                                            emailext body: '${SCRIPT, template="groovy-html.template"}', replyTo: '$DEFAULT_REPLYTO', subject: "${ImageSource}", to: "${Email}"
                                        }
                                    }
                                }
                            }
                        }
                        catch (exc)
                        {
                            currentBuild.result = 'FAILURE'
                            println "STAGE_FAILED_EXCEPTION."
                        }
                        finally
                        {
                        }
                    }
                }
                parallel CurrentTests
            }
        }
    }
}

def Prepare()
{
    retry(5)
    {
        cleanWs()
        unstash 'LISAv2'
    }
}

stage ("Prerequisite")
{
    node ("azure")
    {
        cleanWs()
        git branch: GitBranchForAutomation, url: GitUrlForAutomation
        stash includes: '**', name: 'LISAv2'
        cleanWs()
    }
}

stage ("Inspect VHD")
{
    if ((CustomVHD != "" && CustomVHD != null) || (CustomVHDURL != "" && CustomVHDURL != null))
    {
        node ("vhd")
        {
            Prepare()
            println "Running Inspect file"
            withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
            {
                RunPowershellCommand (".\\JenkinsPipelines\\Scripts\\InspectVHD.ps1 -XMLSecretFile '${Azure_Secrets_File}'")
            }
            stash includes: 'CustomVHD.azure.env', name: 'CustomVHD'
        }
    }
}

stage('Upload VHD to Azure')
{
    def FinalVHDName = ""
    if ((CustomVHD != "" && CustomVHD != null) || (CustomVHDURL != "" && CustomVHDURL != null))
    {
        node ("vhd")
        {
            Prepare()
            unstash 'CustomVHD'
            FinalVHDName = readFile 'CustomVHD.azure.env'
            withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
            {
                RunPowershellCommand (".\\Utilities\\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath '${Azure_Secrets_File}';" +
                ".\\Utilities\\UploadVHDtoAzureStorage.ps1 -Region westus2 -VHDPath 'Q:\\Temp\\${FinalVHDName}' -DeleteVHDAfterUpload -NumberOfUploaderThreads 64"
                )
            }
        }
    }
}

stage('Capture VHD with Custom Kernel')
{
    def KernelFile = ""
    def FinalImageSource = ""
    //Inspect the kernel
    if ( (CustomKernelFile != "" && CustomKernelFile != null) || (CustomKernelURL != "" && CustomKernelURL != null) )
    {
        node("azure")
        {
            if ((CustomVHD != "" && CustomVHD != null) || (CustomVHDURL != "" && CustomVHDURL != null))
            {
                unstash 'CustomVHD'
                FinalVHDName = readFile 'CustomVHD.azure.env'
                FinalImageSource = " -OsVHD '${FinalVHDName}'"
            }
            else
            {
                FinalImageSource = " -ARMImageName '${ImageSource}'"
            }
            Prepare()
            withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
            {
                RunPowershellCommand (".\\Utilities\\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath '${Azure_Secrets_File}';" +
                ".\\JenkinsPipelines\\Scripts\\InspectCustomKernel.ps1 -RemoteFolder 'J:\\ReceivedFiles' -LocalFolder '.'"
                )
                KernelFile = readFile 'CustomKernel.azure.env'
                stash includes: KernelFile, name: 'CustomKernelStash'
                RunPowershellCommand(".\\Run-LisaV2.ps1" +
                " -XMLSecretFile '${Azure_Secrets_File}'" +
                " -TestLocation 'westus2'" +
                " -RGIdentifier '${JenkinsUser}'" +
                " -TestPlatform 'Azure'" +
                " -CustomKernel 'localfile:${KernelFile}'" +
                " -StorageAccount '${StorageAccount}'" +
                FinalImageSource +
                " -TestNames 'CAPTURE-VHD-BEFORE-TEST'"
                )
                CapturedVHD = readFile 'CapturedVHD.azure.env'
                stash includes: 'CapturedVHD.azure.env', name: 'CapturedVHD.azure.env'
            }
            println("Captured VHD : ${CapturedVHD}")
        }
    }
}

stage('Copy VHD to other regions')
{
    def CurrentTestRegions = ""
    if ((CustomVHDURL != "" && CustomVHDURL != null)  || (CustomVHD != "" && CustomVHD != null) || (CustomKernelFile != "" && CustomKernelFile != null) || (CustomKernelURL != "" && CustomKernelURL != null) || (Kernel != "default"))
    {
        node ("vhd")
        {
            Prepare()
            def FinalVHDName = ""
            if ((CustomKernelFile != "" && CustomKernelFile != null) || (CustomKernelURL != "" && CustomKernelURL != null) || (Kernel != "default"))
            {
                unstash "CapturedVHD.azure.env"
                FinalVHDName = readFile "CapturedVHD.azure.env"
            }
            else
            {
                unstash 'CustomVHD'
                FinalVHDName = readFile 'CustomVHD.azure.env'
            }
            withCredentials([file(credentialsId: 'Azure_Secrets_TESTONLY_File', variable: 'Azure_Secrets_File')])
            {
                RunPowershellCommand ( ".\\JenkinsPipelines\\Scripts\\DetectTestRegions.ps1 -TestByTestName '${TestByTestname}' -TestByCategorizedTestName '${TestByCategorisedTestname}' -TestByCategory '${TestByCategory}' -TestByTag '${TestByTag}'" )
                CurrentTestRegions = readFile 'CurrentTestRegions.azure.env'
                RunPowershellCommand (".\\Utilities\\AddAzureRmAccountFromSecretsFile.ps1  customSecretsFilePath '${Azure_Secrets_File}';" +
                ".\\Utilities\\CopyVHDtoOtherStorageAccount.ps1 -SourceLocation westus2 -destinationLocations '${CurrentTestRegions}' -sourceVHDName '${FinalVHDName}' -DestinationAccountType Standard"
                )
            }
        }
    }
}


stage("TestByTestname")
{
    ExecuteTest ( JenkinsUser, UpstreamBuildNumber, ImageSource, OverrideVMSize, CustomVHD, CustomVHDURL, Kernel,
        CustomKernelFile, CustomKernelURL, StorageAccount, DiskType, GitUrlForAutomation, GitBranchForAutomation,
        TestByTestname, null, null, null, Email, debug, TiPCluster, TipSessionId )
}
stage("TestByCategorisedTestname")
{
    ExecuteTest ( JenkinsUser, UpstreamBuildNumber, ImageSource, OverrideVMSize, CustomVHD, CustomVHDURL, Kernel,
        CustomKernelFile, CustomKernelURL, StorageAccount, DiskType, GitUrlForAutomation, GitBranchForAutomation,
        null, TestByCategorisedTestname, null, null, Email, debug, TiPCluster, TipSessionId )
}
stage("TestByCategory")
{
    ExecuteTest ( JenkinsUser, UpstreamBuildNumber, ImageSource, OverrideVMSize, CustomVHD, CustomVHDURL, Kernel,
        CustomKernelFile, CustomKernelURL, StorageAccount, DiskType, GitUrlForAutomation, GitBranchForAutomation,
        null, null, TestByCategory, null, Email, debug, TiPCluster, TipSessionId )
}
stage("TestByTag")
{
    ExecuteTest ( JenkinsUser, UpstreamBuildNumber, ImageSource, OverrideVMSize, CustomVHD, CustomVHDURL, Kernel,
        CustomKernelFile, CustomKernelURL, StorageAccount, DiskType, GitUrlForAutomation, GitBranchForAutomation,
        null, null, null, TestByTag, Email, debug, TiPCluster, TipSessionId )
}
