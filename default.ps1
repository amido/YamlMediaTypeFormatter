# Copyright 2015 Amido Limited

Framework 4.6

Include "Scripts/Initialize-SharedAssemblyInfo.ps1";
Include "Scripts/Set-AssemblyVersion.ps1";
Include "Scripts/Compress-ToArchive.ps1";

properties {
  $release = $false;
  $buildSequenceNumber = [int]$ENV:APPVEYOR_BUILD_NUMBER;
  $packageVersion = "1.0.0";
  $rev = $(git rev-parse --short HEAD);
  if ($release) {
    $metadata = [String]::Empty;
  }
  else {
    if ($buildSequenceNumber -eq 0) {
      $metadata = "-Local";
    }
    else {
      $metadata = "-PreRelease{0}" -f $buildSequenceNumber;
    }
  }
  $toolsVersion = "14.0";
  $buildConfiguration = "Release";
  $targetProject = "Amido.Net.Http.Formatting.YamlMediaTypeFormatter";
  $solution = "Solutions/$targetProject.sln";
  $sharedAssemblyInfo = "Solutions/SharedAssemblyInfo.cs";
  $nugetDownload = "https://nuget.org/nuget.exe";
}

task default -depends Compile

task GitClean -preCondition { (git status | Where-Object { $_ -match 'nothing to commit' } | Measure-Object).Count -eq 1 } {
  & git clean -df;
}

task SetupTools -depends GitClean -preCondition { -Not (Test-Path "$PSScriptRoot\Tools") } {
  New-Item -Type Container Tools | Out-Null;
}

task SetupNuGet -depends SetupTools, GitClean -preCondition { -Not (Test-Path "$PSScriptRoot\Tools\Nuget.exe") } {
  $toolsFolder = Resolve-Path "Tools";
  $nugetExecutable = Join-Path -Path $toolsFolder -ChildPath "nuget.exe";
  Invoke-WebRequest -Uri $nugetDownload -OutFile $nugetExecutable;
}

task NugetPackageRestore -depends SetupNuGet {
  & Tools/nuget.exe restore Solutions;
}

task CleanBuild {
  if(Test-Path "C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll") {
    msbuild $solution /m /t:clean /p:VisualStudioVersion=$toolsVersion /p:Configuration=$buildConfiguration /logger:"C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll";
  } else {
    msbuild $solution /m /t:clean /p:VisualStudioVersion=$toolsVersion /p:Configuration=$buildConfiguration
  }
}

task CleanFileSystem {
  Get-ChildItem .\Solutions\ -Recurse -Filter "Bin" | Remove-Item -Recurse -Force;
  Get-ChildItem .\Solutions\ -Recurse -Filter "Obj" | Remove-Item -Recurse -Force;
}

task Clean -depends CleanFileSystem, CleanBuild { }

task SetupSharedAssemblyInfo {
  Initialize-SharedAssemblyInfo -RemoveComments;
}

task SetVersion -depends SetupSharedAssemblyInfo {
  $buildVersion = "+sha.{0}" -f $rev, $buildSequenceNumber;
  $semanticVersion = "$($packageVersion)$($metadata)$($buildVersion)";
  Set-AssemblyVersion -Path $sharedAssemblyInfo -Version $packageVersion -SemanticVersion $semanticVersion;
}

task Compile -depends SetVersion, Clean, NugetPackageRestore { 
  if(Test-Path "C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll") {
    msbuild $solution /m /p:VisualStudioVersion=$toolsVersion /p:Configuration=$buildConfiguration /logger:"C:\Program Files\AppVeyor\BuildAgent\Appveyor.MSBuildLogger.dll";
  } else {
    msbuild $solution /m /p:VisualStudioVersion=$toolsVersion /p:Configuration=$buildConfiguration
  }
  Set-AssemblyVersion -Path $sharedAssemblyInfo -Version $packageVersion -SemanticVersion "From Source";
}

task PackNuget -depends Compile, SetupNuGet {
  $nugetVersion = "$($packageVersion)$($metadata)";
  & Tools/nuget.exe pack "Solutions/$targetProject/$targetProject.nuspec" -OutputDirectory "Artefacts" -Version $nugetVersion -Symbols -NonInteractive;
}

task PackArchive -depends Compile {
  $semanticVersion = "$($packageVersion)$($metadata)$($buildVersion)";
  $destination = "$PSScriptRoot/Artefacts/$($targetProject).$($semanticVersion).zip";
  $source = "$PSScriptRoot/Solutions/$targetProject/bin/$buildConfiguration/";

  if (Test-Path $destination) {
    Remove-Item $destination;
  }

  Compress-ToArchive -Source $source -Destination $destination;
}

task Pack -depends PackNuget, PackArchive { }