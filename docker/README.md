# Docker

The common Docker scripts in this directory use docker commands to build, pull, and push images.

By convention, a docker file is expected to exist in the root of the repo which a script is being
run against.

## Build Docker

**Script: `build-docker.ps1`**

Takes the following parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| RepoName  | &check;   | Name of the repo to build. This can be automatically populated for the caller by `run-repo-script`. |
| Version   | &check;   | Version to tag the image with. This will usually match the assembly version. |
| Keys      | &check;   | Hash table of keys which must contain values for `DockerRegistry`, and `DockerContainer`. |
| ImageFile |           | Name of the file to save the image to. By default this is "dockerimage.tar". |

The docker image is built, and saved to the packages directory in order to be uploaded as an artifact.

## Load Docker

**Script: `load-docker.ps1`**

| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| ImageFile |           | Name of the file to load the image from. By default this is "dockerimage.tar". |

Loads a docker image previously saved to the packages directory.

## Publish docker

**Script: `publish-docker.ps1`**

Takes the following parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| RepoName  | &check;   | Name of the repo to build. This can be automatically populated for the caller by `run-repo-script`. |
| Version   | &check;   | Version tag to publish. This will usually match the assembly version. |
| Keys      | &check;   | Hash table of keys which must contain values for `DockerRegistry`, `DockerContainer`, `DockerUser`, and `DockerPassword`. |
| DryRun    | | Determines if a Dry Run is being performed. This prohibits publishing of the docker image. |

Pushes a docker image tag to the specified registry, using the login provided.

## Publish Latest Docker

**Script: `publish-latest-docker.ps1`**

Takes the following parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| RepoName  | &check;   | Name of the repo to build. This can be automatically populated for the caller by `run-repo-script`. |
| Version   | &check;   | Version tag to mark as latest. This will usually match the assembly version. |
| Keys      | &check;   | Hash table of keys which must contain values for `DockerRegistry`, `DockerContainer`, `DockerUser`, and `DockerPassword`. |
| DryRun    | | Determines if a Dry Run is being performed. This prohibits publishing of the docker image. |

Tags the version specified as `latest` and pushes the tag to the specified registry.


## Pull Docker

**Script: `pull-docker.ps1`**

Takes the following parameters:
| Parameter | Mandatory | Description |
| --------- | :-------: | ----------- |
| Version   | &check;   | Version tag pull. This will usually match the assembly version. |
| Keys      | &check;   | Hash table of keys which must contain values for `DockerRegistry`, `DockerContainer`, `DockerUser`, and `DockerPassword`. |

Pulls a docker image tag from the specified registry, using the login provided.

