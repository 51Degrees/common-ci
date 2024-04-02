# CXX

The common C/C++ scripts in this directory use common build tools to build and test projects.

## Common Parameters

These parameters are common to all the C/C++ scripts:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| ProjectDir |    | The project directory (or full path) to give to the build tool. By default this is `./`. |
| RepoName | &check; | Name of the repo to build. This can be automatically populated for the caller by `run-repo-script`. |
| Name | &check; | The name of the configuration. This comes from `options.json` and can be automatically populated for the caller by `run-repo-script`. |
| Configuration | | The build configuration to give to the build tool. Generally this is either `Debug` or `Release` (default). |
| Arch | | The architecture to build with. by default this is `x64`. |

## Build Project

**Script: `build-project.ps1`**

Takes the following additional parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| BuildMethod |  | The build tool to use. This can be either `cmake` (default) or `msbuild`. |
| BuildDir | | The directory to output the build to. By default this is `build`. |

The project is build in the `./build` directory of the repo, unless the project has steps which explicitly output to a path. See CMake and MSBuild implementations for more info.

## Run Unit Tests

**Script: `run-unit-tests.ps1`**

| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| BuildMethod |  | The build tool to use. This can be either `cmake` (default) or `msbuild`. |

Runs `ctest` in the build directory excluding the patterns `.*Integration.*` and `.*Performance.*`. Test results are output to `./test-results/unit/$Name.xml` relative to the root of the repo.

If the `msbuild` method is used, each executable in the `build` directory which matches the pattern `.*Test.*.exe` is run.
Tests are assumed to be GTest applications.

## Run Performance Tests

**Script: `run-performance-tests.ps1`**

Runs `ctest` in the build directory with the filter `.*Perf.*`. Test results are output to `./test-results/performance/$Name.xml` relative to the root of the repo.


## Run Integration Tests

**Script: `run-integration-tests.ps1`**

Runs `ctest` in the build directory with the filter `.*Integration.*`. Test results are output to `./test-results/integration/$Name.xml` relative to the root of the repo.

