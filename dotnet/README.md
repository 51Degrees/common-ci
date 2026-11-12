# .NET SPECIFIC CI/CD Approach

The CI/CD pipeline in this project adheres to the principles outlined in the common-ci project, with the following exceptions:

## Environment

The script `setup-environment.ps1` is specific for each repository and is responsible for configuring essential environment variables required for running tests. These variables include the location of data files and the resource key. On Linux systems, it may also install multilib, which it should do by calling `environments/setup-multilib.ps1` rather than apt directly, because those packages do not exist on arm64 and asking for them there fails the step. Additionally, in cases where the project is utilizing the msbuild command instead of dotnet, the script ensures that both msbuild and vstest are appropriately added to the PATH variable. 


## Build

Dotnet projects  include two distinct build scripts: one for the core and another for the framework. In cases where projects contain multiple solutions per project, it is necessary to pass the solution name as a parameter to the "ProjectDir."

## Tests

Due to the presence of both core and framework projects in our repositories, both dotnet and msbuild commands may be employed to test different configurations. The BuildMethod parameter, specified in options.json, determines these commands. Instead of testing the solution file, the tests are performed on the assembly, enabling us to exclude framework projects that are not built. This approach helps us avoid the challenge of inconsistent behavior across different dotnet commands and addresses the problem of varying expectations for the bin folder location based on different configurations during the build process.

## Packaging 

The packages are signed in the `build-packages-nuget.ps1` script as they are built in the folder from which they will be ultimately published. The content of the `.pfx` file is defined in the secrets and is passed to the script and written to a file inside the script which is then passed to the pack command.

## Updating Dependencies 

Dependencies are updated by `outdated.ps1`, a thin wrapper around the
[dotnet-outdated](https://github.com/dotnet-outdated/dotnet-outdated) tool. It
restores the target, then runs `dotnet-outdated --recursive --upgrade` with
`--version-lock Minor`, so a package moves to its newest patch but never to a
new minor or major version.

Passing `Target` scopes both commands to one solution or project. That is
required where a repository root holds several solutions, and it also keeps the
recursive upgrade away from projects that belong to a git submodule, which the
commit step cannot stage.

## Common Parameters

These parameters are common to all the C/C++ scripts:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| ProjectDir |    | The project directory (or full path) to give to the build tool. By default this is `./`. |
| RepoName | &check; | Name of the repo to build. This can be automatically populated for the caller by `run-repo-script`. |
| Name | &check; | The name of the configuration. This comes from `options.json` and can be automatically populated for the caller by `run-repo-script`. |
| Configuration | | The build configuration to give to the build tool. Generally this is either `Debug` or `Release` (default). |
| Arch* | | The architecture to build with. by default this is `x64`. ****The only exception is the `build-package-nuget.ps1` script, where the architecture is omitted entirely as the packages are built using `Any CPU` architecture***|


## Build Project

**Script: `build-project.ps1`**

Takes the following additional parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| BuildMethod |  | The build tool to use. This can be either `msbuild` (default) or `dotnet`. |

## Add NuGet Source

**Script: `add-nuget-source.ps1`**

Takes the following additional parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| Source | :check: | URL of the NuGet source to add. |
| UserName | :check: | Username to authenticate with the source. |
| Key | :check: | User key to authenticate with the source. |

## Build Publish Zip

**Script: `build-publish-zip.ps1`**

Takes the following additional parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| Version | :check: | The version of the package being built. |
| Project | | Project file name, if there is more than one in the directory. By default this is `.`. |

## Publish Package NuGet

**Script: `publish-package-nuget.ps1`**

Takes the following additional parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| ApiKey | :check: | Auth key for the NuGet source to publish to. |
| Source | | NuGet source to publish to. By default this is `https://api.nuget.org/v3/index.json`. |

## Publish Package GitHub

**Script: `publish-package-github.ps1`**

Takes the following additional parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| ApiKey | :check: | Auth token for the GitHub repo to publish to. |

## Run Unit Tests

**Script: `run-unit-tests.ps1`**

| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| BuildMethod |  | The build tool to use. This can be either `dotnet` (default) or `msbuild`. If msbuild is specified the `vstest.console.exe` command is used for running the tests. |
| Filter |  |  It applies a regex pattern to the names of files found during recursive traversal of the "RepoPath" directory. The filter is used to test only the files whose names match the filter.  |
| OutputFolder |  |  Specifies the name of the folder where the test results will be stored. This is because the integration and performance test scripts call this script with a filter that specifies integration or performance tests assemblies.  |


## Run Performance Tests

**Script: `run-performance-tests.ps1`**

See [Run Unit Tests](#Run-Unit-Tests)

## Run Integration Tests

**Script: `run-integration-tests.ps1`**

See [Run Unit Tests](#Run-Unit-Tests)

## Update Dependencies

**Script: `outdated.ps1`**

Installs the `dotnet-outdated-tool` and upgrades every package reference it
finds, locked to the current minor version so only patch releases are taken.

Takes the following additional parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| Target | | Solution or project to restore and update. A repository whose root holds more than one solution must set this so `dotnet restore` is not ambiguous, and setting it also keeps the update away from projects a git submodule brings in. When empty, both commands operate on the whole directory. |
| ExtraArgs | | Further arguments passed straight through to `dotnet-outdated`. |
