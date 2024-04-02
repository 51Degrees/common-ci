# Introduction

This repository contains all the common scripts and documentation associated with continuous integration and deployment (CI/CD) used across the organisation.

The subfolders with language names contain an equivalent document detailing language specific detail that is common across all repositories using the language.

The reader should be familiar with PowerShell and common Git based CI/CD techniques.

# Principles

The following rules are common across the organisation.

-   Minimal dependency between stages.
-   Relevant integration tests must be run against packages before they are released to the relevant package manager.
-   PowerShell scripts contain the implementation as they operate consistently across platform and avoid duplicating logic associated with a mixed environment.
-   PowerShell scripts contain all the necessary documentation at the top of the script.
-   PowerShell scripts have defined input parameters and outputs following PowerShell conventions.
-   All parameters are GitHub secrets, or options defined in the repo, and passed by the YAML script as parameters to the PowerShell script.
-   YAML scripts simply call the top level PowerShell scripts within the GitHub actions. Each YAML script will have a corresponding PowerShell script which can be used to test all the steps on any environment. These scripts must have the same name with only the file extension being different.
-   Orchestration of the PowerShell step scripts is handled by the top level PowerShell scripts as much as possible. There are some exceptions to this, e.g. running on multiple VM images needs to be handled in YAML.
-   GitHub triggers initiate the stages.
-   Use of GitHub actions and other platform specific features are minimised to enable portability of CI/CD. For example, cloning a repository is performed in PowerShell via a generic command line that works on Linux, Windows, and Mac rather than in a GitHub action. This ensures the PowerShell script can be tested outside a CI/CD deployment environment.
-   C/C++ is compiled using CMake on all platforms.
-   Versioning is performed using the most appropriate method for the target language. For example, GitVersion used for .NET
-   Common PowerShell scripts are contained in this repository. Repository specific scripts are contained under the root `ci` folder.
-   Code that is in the `main` branch has passed all relevant tests. This is a critical gate to avoid repeating tests.
-   The package output from a repository in the organisation is used as the input to other packages in the same organisation via the relevant package manager. This ensures that the organisations published packages are treated just like any other dependency and are not given special treatment.
-   Branching strategy is covered in the relevant CONTRIBUTIONS.md for the repository and not covered here. All organisation repositories must have a `main` branch which can accept pull requests via automated tasks.

# Design

When implementing changes, see the [Design Document](/DESIGN.md) for detailed descriptions of how each part works.

# Contributing

For info on contributing to this, and other 51Degrees projects, see [Contributing](/CONTRIBUTING.md).

# Workflows

## Common Setup Steps
``` mermaid
flowchart
subgraph com[Common Setup]
  style com fill:green;
  C1[Checkout Common]
  C2[Configure Git]
  C3[Clone Repo]
  C1-->C2-->C3
end
```

## Nightly Publish Main

``` mermaid
flowchart LR;

subgraph Nightly Publish Main
  conf -- Once per config where 'PackageRequirement'=true --> pbuild
  pbuild -- Combine pre-build files --> build
  build -- Once per config --> test
  test --> pub
end

subgraph conf[Configure]
  direction LR
  style conf fill:#00C5,stroke:#00C9,stroke-width:2px;
  A([Common Setup])
  style A fill:green;
  B[Get Next Package Version]
  C[Package Update Required]
  D[Get Build Options]
  A-->B-->C-->D

end

subgraph pbuild[Pre-Build]
  direction LR
  style pbuild fill:#00C5,stroke: #00C9,stroke-width:2px;
  style PB1 fill:green;
  PB1([Common Setup])
  PB2[Setup Environment]
  PB3[Build Package Requirements]
  PB4[Upload Package Artifact]
  PB1-->PB2-->PB3-->PB4
end

subgraph build[Build Package]
  direction LR
  style build fill:#00C5,stroke: #00C9,stroke-width:2px;
  style B1 fill:green;
  B1([Common Setup])
  B2[Setup Environment]
  B3[Download Package Artifacts]
  B4[Build Package]
  B5[Upload Package Artifact]
  B1-->B2-->B3-->B4-->B5
end

subgraph test[Test]
  direction LR
  style test fill:#00C5,stroke:#00C9,stroke-width:2px;
  style T1 fill:green;
  T1([Common Setup])
  T2[Fetch Assets]
  T3[Setup Environment]
  T4[Download Package Artifact]
  T5[Install Package From Artifact]
  T6[Run Integration Tests]
  T1-->T2-->T3-->T4-->T5-->T6
end

subgraph pub[Publish Package]
  direction LR
  style pub fill:#00C5,stroke:#00C9,stroke-width:2px;
  style P1 fill:green;
  P1([Common Setup])
  P2[Setup Environment]
  P3[Download Package Artifact]
  P4[Install Package From Artifact]
  P5[Publish Package]
  P6[Update Tag]
  P1-->P2-->P3-->P4-->P5-->P6
end

```
## Nightly PR to Main 

``` mermaid
flowchart LR
  classDef green fill:green;

  subgraph "Nightly PR to Main"
    subgraph prs[Get Pull Requests]
      style prs fill:#00C5,stroke:#00C9,stroke-width:2px;
      X([Common Setup]):::green
      Y[Get Pull Requests]
      X-->Y
    end
    subgraph main[PR to Main]
      direction TB
      subgraph conf[Configure]
        direction LR
        style conf fill:#00C5,stroke:#00C9,stroke-width:2px;
        A([Common Setup]):::green
        B[Checkout Pull Request]
        C[Get Build Options]
        A-->B-->C
      end
      subgraph bat[Build and Test]
        direction LR
        F([Common Setup]):::green
        G[Checkout Pull Request]
        H[Fetch Assets]
        I[Setup Environment]
        J[Build Project]
        K[Run Unit Tests]
        L[Run Integration Tests]
        M[Run Performance Tests]
        F-->G-->H-->I-->J-->K-->L-->M
      end
      conf-- Once Per Config -->bat
    end
    prs-- Once Per PR -->main
  end
  ```

  ## Nightly Submodule Update
``` mermaid
  graph LR
  classDef green fill:green;
  subgraph "Nightly Submodule Update"
    direction LR
    A([Common Setup]):::green
    B[Update Sub Modules]
    C[Check for Changes]
    D[Commit Changes]
    E[Push Changes]
    F[Create Pull Request]
    A-->B-->C-->D-->E-->F
  end
  
```
## Nightly Package Update

``` mermaid
graph LR
classDef green fill:green;
  subgraph "Nightly Package Update"
    direction LR
    A([Common Setup]):::green
    B[Update Packages]
    C[Check for Changes]
    D[Commit Changes]
    E[Push Changes]
    F[Create Pull Request]
    A-->B-->C-->D-->E-->F
  end
```

## Nightly Data File Update

``` mermaid
graph LR
classDef green fill:green;
  subgraph "Nightly Data File Update"
    direction LR
    A([Common Setup]):::green
    B[Fetch Assets]
    C[Generate Accessors]
    D[Check For Changes]
    E[Commit Changes]
    F[Push Changes]
    G[PR to Main]
    A-->B-->C-->D-->E-->F-->G
  end
```

## Nightly Documentation Update

``` mermaid
graph LR
classDef green fill:green;
  subgraph "Nightly Documentation Update"
    direction LR
    A([Common Setup]):::green
    B[Clone Tools Repo]
    C[Clone Documentation Repo]
    D[Generate Documentation]
    E[Check For Changes]
    F[Commit Changes]
    G[Push Changes]
    A-->B-->C-->D-->E-->F-->G
  end
```

## Monthly Copyright Update

``` mermaid
graph LR
classDef green fill:green;
  subgraph "Monthly Copyright Update"
    direction LR
    A([Common Setup]):::green
    B[Clone Tools Repo]
    C[Update Copyright Messages]
    D[Check For Changes]
    E[Commit Changes]
    F[PR To Main]
    A-->B-->C-->D-->E-->F
  end
```

# Triggers

Each of the triggers shown is described at a high level. More detail is provided in the associated scripts and the following summary.

### Nightly Data File Change

When data files used by the packages change new properties might be added or current ones deprecated. The strongly type accessors for the language might therefore need to change resulting in a new version of the resulting package. Every night, data files are fetched, and the auto generated strongly typed accessor code is updated. Any changes are then committed to a branch and a pull request to `main` is created.

### Nightly Package Dependency Update and Nightly Sub-Module Update

Every night any dependencies of the package are updated automatically to the latest patch version of that package or `main` branch commit of the sub-module. This includes any dependencies on packages within the organisation. Where changes are identified a branch is created and a PR to `main` is initiated. The tests associated with any PR to `main` will identify any failures for engineers to address before the updated versions can be used.

### PR to Main

All tests associated with the repository are run only at this point to avoid repetition. Code can only be present in the main branch of the repository if all tests have passed.

PRs to `main` can only be initiated by a project Contributor, Administrator, or GitHub actions.

### Nightly Main Package Publish

**This job should only be run once all the other nightly jobs have completed.**

Any changes to the `main` branch are published automatically on a nightly basis as a new package at the target package manager environment.

This can also be run manually against any branch. If the branch is not the main branch, then the generated version for the package will be a prerelease version, following semantic versioning.

### Nightly Documentation Update

Any changes to the `main` branch are used to generate the latest documentation. This is then published to the `gh-pages` branch of the reposiory.

### Monthly Copyright Update

If the copyright is updated, the source code files are all updated with the latest copyright in the header of the file.

This does no happen often, so the workflow can be run monthly rather than nightly.

### Common Scenarios

#### New property in data file

The Data File Change trigger creates new auto generated code for the strongly typed accessors. These are pushed to a branch and a PR to main commenced. All the tests associated with the repository will then be run. If they fail, then the engineers will be alerted to a problem. If they pass, then the PR will be approved and main branch updated. When the next nightly publish of packages occurs then the new property will be included in the package.

#### Update dependency

A package that the organisation uses is updated to a new version within the same `major.minor` version. The nightly dependency check will pick up on the new version and create a branch and associated PR to main. The changes will then propagate to the published packages if the tests executed for any PR to main pass.

#### Organisation package update

Packages associated with the organisation are treated like any other package dependency. Once the package manager has the new version the dependent packages will be updated automatically.

# Common Steps

For details of the common scripts, see [Common Steps](./steps/README.md).

# Prerequisites

To run these PowerShell scripts, either locally, or in a CI/CD pipeline, the following prerequisites must be set up.

- [Git CLI](https://git-scm.com/downloads)
- [Hub CLI](https://hub.github.com/)
- `GITHUB_TOKEN` environment variable (this is automatically set if using GitHub actions)
- Some repositories require a cloud resource key. This can be obtained on the [Configurator](https://configure.51degrees.com)

# Secrets

CI workflows that need secrets accept a [superset of all possible secrets](https://github.com/51Degrees/common-ci/blob/2badf94c075c4a73b188d6647fcd88df69ca8ce1/.github/workflows/nightly-pr-to-main.yml#L38-L64). During workflow execution non-null secrets get [combined into a JSON string](https://github.com/51Degrees/common-ci/blob/2badf94c075c4a73b188d6647fcd88df69ca8ce1/.github/workflows/nightly-pr-to-main.yml#L145), and [parsed as a PowerShell object](https://github.com/51Degrees/common-ci/blob/2badf94c075c4a73b188d6647fcd88df69ca8ce1/.github/workflows/nightly-pr-to-main.yml#L149), which is then passed to all build scripts that require secrets.

This flow modifies the old one, where the JSON string was passed in by the caller directly as a single secret. The rationale for the new flow is making sure that in case secrets leak to CI logs, they get hidden by GitHub (replaced with `***`). This was not possible when all secrets were passed as a single JSON string - GitHub has to know about every single secret to be able to hide them.
