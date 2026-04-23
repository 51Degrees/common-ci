# 51Degrees GitHub Actions

This is a set of independent reusable [actions](https://docs.github.com/en/actions/concepts/workflows-and-actions/custom-actions). The main difference from [.github/actions](../.github/actions) is that those actions are created specifically for reusable workflows in [.github/workflows](../.github/workflows) while these are designed to be more library-like, so that any workflow can call them without having to go through the `common-ci` reusable workflow framework.

## Usage

```yaml
# create-pr
- uses: 51Degrees/common-ci/actions/create-pr@main
  with:
    title: 'A Pull Request'

# bump-version
- uses: 51Degrees/common-ci/actions/bump-version@main
  id: bump
- name: Publish
  if: steps.bump.outputs.bumped
  run: publish.ps1 -Version ${{ steps.bump.outputs.version }}
```
