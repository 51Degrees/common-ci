# Intro

If there is a bugfix or feature you'd like to see implemented, the best place to start is with a GitHub issue. First check there is not an issue raised already. If the issue has not yet been raised, it is worth raising one before making any changes yourself. That way, we can let you know whether or not this is something we are already working on.

As an open source project, 51Degrees accepts changes from the community. To propose a change:
1. Create a new branch from `main` (see [Branching Strategy](#branching-strategy)),
2. Make changes to your new branch locally,
3. Push to GitHub,
4. Open a pull request to the `main` branch in the 51Degrees GitHub,
5. 51Degrees will assess and update.

The rest of this document goes into more details of what is required.

The reader should be familiar with:
- [Git](https://git-scm.com/doc)
- [GitHub Issues](https://github.com/features/issues)
- [GitHub Pull Requests](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests)

# Contents
- [Issues](#issues)
- [Changes](#changes)
  - [Branching Strategy](#branching-strategy)
  - [Commenting](#commenting)
  - [Code Style](#code-style)
  - [Tests](#tests)
  - [Commit Messages](#commit-messages)
- [Making a Pull Request](#making-a-pull-request)
  - [Merging Policy](#merging-policy)
  - [Pull Request Message](#pull-request-message)
- [Build Process](#build-process)

# Issues

Issues should be raised through the GitHub issues system. These are then reviewed weekly by 51Degrees.

An issue should contain a complete explanation of the problem, including the environment being used.
It should also show the steps needed to recreate the issue.

# Changes

## Branching Strategy

In general, branches should be taken from `main`, and PRs created back to `main` for each feature.
For a more in depth descriptions, see [Feature Branch Workflow](https://www.atlassian.com/git/tutorials/comparing-workflows/feature-branch-workflow").

There are some exceptions to this, which will be stated per repository.

Branch naming should be brief but descriptive, under either `feature/` or `bug/`, and kebab-case is prefered e.g. `feature/ui-example`.

## Commenting

Where code has been changed, there MUST be appropriate comments to make it clear what is happening.
For bugs, the nature of the bug being prevented should be explained to prevent it recurring. For example:
```c
char *str = malloc(10);
// Set the first byte to null, as strlen is called later, so
// the string must be initialized.
str[0] = '\0';
```
An example of a comment that adds no value is:
```c
char *str = malloc(10);
// Set the first byte to null.
str[0] = '\0';
```
Where the comment is just repeating the code.

Guidelines for documenting methods and classes can be found in [Documenting Code](https://github.com/51Degrees/documentation/blob/main/Documenting%20Code.md).

## Code Style

Generally, 51Degrees follows the accepted styleguides for each language, and aims to keep line widths below 120 characters. If you are unsure, see the existing code as an example.

## Tests

All new features and bugfixes MUST include tests. Feature tests must at least test the intended functionality, and ideally test edge cases to a reasonable degree. Bugfix tests must show the original bug to prevent regression i.e. fail on the existing code, but pass with the bugfix.

## Commit Messages

Commit messages should clearly explain the change in the first line. A more detailed description of why a certain design was chosen etc. should be in the body of the commit.

Commits should also be prefixed with a useful tag. Common tags are:

| Prefix | Use |
| ------ | --- |
| FEAT   | A new feature |
| BUG    | Fix for a bug |
| OPTIM  | A performance optimisation |
| TEST   | Addition, or update, of a test |
| REORG  | A restructure of code |
| DOC    | Improvement or addition to documentation |
| REF    | Update to a package or submodule reference |
| BUILD  | Change to a build method |

If the commit relates to an issue, the issue should be linked in the commit.

An example of a good commit message is:
```
BUG: Fixed bug where string was not initialised.
A string was allocated, but the memory was not initialised. This meant that
subsequent calls to strlen had undefined behavior, and could read past the
end of the allocated memory.
The first byte of the string is now set to null, so all calls to strlen return
zero.
See issue #1
```

# Making a Pull Request

Pull requests should be made into the `main` branch on GitHub.

## Merging Policy

The merging policy should adhere to the following rules: 
- All PRs created by a 51degrees contributor should require review and approval from a trusted 51Degrees contributor or 51degrees Engineering member.
- All PRs created by a Github Workflow should be automatically tested and merged *without* need for review.

The implementation of the merge policy currently exists in [Get-pull-requests.ps1](https://github.com/51Degrees/common-ci/blob/main/steps/get-pull-requests.ps1#L62) and should reflect the rules above. 

## Pull Request Message

If the PR aims to resolve an open issue, the issue should be linked and closed using the standard GitHub keywords e.g. `Closes #1`. For more, see [Linking Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword).

# Build Process

The build, test, and publish process is all automated. For details of this, see [common-ci](https://github.com/51degrees/common-ci).

Once a PR has been tested, and is merged into the `main` branch, a release is created on GitHub, and any packages are built and published to the appropriate package manager.

Versioning is carried out automatically, and may vary based on repository. In general, each new release from `main` results in an increment to the patch version i.e. `1.2.3` becomes `1.2.4`. This is tagged in GitHub, updated in any files where a version is required (e.g. pom.xml for Java) and is the version for released packages. For specific details on versioning, see the branching strategy for the repository of interest.

Any other 51Degrees projects which have dependencies on a released package will automatically be updated, and go through the same PR process.

The automated processes run nightly. So any dependencies of an update will be updated the following day. For example, a PR is merged to `main` in the pipeline-dotnet repo. This releases the pipeline packages. The next nightly run will update references to pipeline packages in the device-detection-dotnet repo. This results in a new PR, which is then tested and released in the same way. If a change is urgent, the process can be triggered manually, though this is usually not necessary.
