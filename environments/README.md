# Environments

## Introduction

These scripts are designed to be run in GitHub workflows. Though some scripts may be runnable locally.
The idea is to contain common setups which will be required by multiple repositories. For example, a build tool that
is needed for a certain language, but is not present byu default.

## MSBuild

**Script: `setup-msbuild.ps1`**

This is limited to Windows images.

It installs VSWhere, and runs it to find the location of the MSBuild executable. Once found, it is added to the path.
Specifically, it uses `GITHUB_PATH` so that the tool is available in subsequent jobs.

## Multilib

**Script: `setup-multilib.ps1`**

This is limited to Linux images, and within those to x86_64.

It installs `gcc-multilib` and `g++-multilib`, the 32 bit libraries an x86 build links
against. Pass `-Packages` to install a different set, which common-cxx does because it
needs only `gcc-multilib`.

Neither package exists for arm64 under any name, so on an ARM runner apt answers "has no
installation candidate" and the script returns without installing anything rather than
failing. Repositories should call this instead of apt directly, because each copy of that
call carried the same fault.
