# monorepo-version-manager

GitHub Action for managing versions (and creating corresponding Git tags) in monorepos. Inspired by [anothrNick/github-tag-action](https://github.com/anothrNick/github-tag-action).

[![Build Status](https://github.com/mpmcroy/monorepo-version-manager/workflows/Test/badge.svg)](https://github.com/mpmcroy/monorepo-version-manager/workflows/Test/badge.svg)
[![Latest Release](https://img.shields.io/github/v/release/mpmcroy/gmonorepo-version-manager?color=%233D9970)](https://img.shields.io/github/v/release/mpmcroy/monorepo-version-manager?color=%233D9970)

## Usage
```yaml
# Bump semver version (main component)
- uses: mpmcroy/monorepo-version-manager@0.1.0
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

# Bump semver version (foobar component)
- uses: mpmcroy/monorepo-version-manager@0.1.0
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    COMPONENT_NAME: foobar
    COMPONENT_DIR: foobar

# Bump build_number version (main component)
- uses: mpmcroy/monorepo-version-manager@0.1.0
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    COMPONENT_NAME: config
    COMPONENT_DIR: config
    VERSIONING_SCHEME: build_number
    INITIAL_VERSION: 0
```

## Options

| Name               | Required | Description                                                                                                                                                                                                                                                                  | Default          |
|:-------------------|:---------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:-----------------|
| GITHUB_TOKEN       | required |                                                                                                                                                                                                                                                                              |                  |
| DEFAULT_BUMP       | optional | Type of bump to use when none explicitly provided                                                                                                                                                                                                                            | minor            |
| DEFAULT_BRANCH     | optional | Overwrite the default branch its read from Github Runner env var but can be overwritten (default: $GITHUB_BASE_REF). Strongly recommended to set this var if using anything else than master or main as default branch otherwise in combination with history full will error | $GITHUB_BASE_REF |
| COMPONENT_NAME     | optional | Name of the component to version                                                                                                                                                                                                                                             | main             |
| COMPONENT_DIR      | optional | Directory path to component                                                                                                                                                                                                                                                  | .                |
| VERSIONING_SCHEME  | optional | Versioning scheme to use (valid values are 'semver' and 'build_number')                                                                                                                                                                                                      | semver           |
| WITH_V             | optional | Prefix version tag with `v`                                                                                                                                                                                                                                                  | false            |
| RELEASE_BRANCHES   | optional | Comma separated list of branches (bash reg exp accepted) that will generate the release tags. Other branches and pull-requests generate versions postfixed with the commit hash and do not generate any tag (e.g. `master` or `.*` or `release.*,hotfix.*,master`)           | master,main      |
| CUSTOM_TAG         | optional | Set a custom tag, useful when generating tag based on f.ex FROM image in a docker image. **Setting this tag will invalidate any other settings set!**                                                                                                                        |                  |
| SOURCE             | optional | Operate on a relative path under $GITHUB_WORKSPACE                                                                                                                                                                                                                           | .                |
| DRY_RUN            | optional | Determine the next version without tagging the branch                                                                                                                                                                                                                        | false            |
| GIT_API_TAGGING    | optional | Set if using git cli or git api calls for tag push operations                                                                                                                                                                                                                | true             |
| INITIAL_VERSION    | optional | Initial version before bump. **Required when using build_number versioning scheme (e.g. 0)**                                                                                                                                                                                 | 0.0.0            |
| TAG_CONTEXT        | optional | Set the context of the previous tag (valid values 'repo' and 'branch')                                                                                                                                                                                                       | repo             |
| PRERELEASE         | optional | Define if workflow runs in prerelease mode. Note this will be overwritten if using complex suffix release branches. Use it with checkout `ref: ${{ github.sha }}` for consistency see [issue 266](https://github.com/anothrNick/github-tag-action/issues/266)                | false            |
| PRERELEASE_SUFFIX  | optional | Suffix for your prerelease versions. Note this will only be used if a prerelease branch                                                                                                                                                                                      | beta             |
| VERBOSE            | optional | Enable verbose logging                                                                                                                                                                                                                                                       | false            |
| MAJOR_STRING_TOKEN | optional | String in commit log to search for to bump major version                                                                                                                                                                                                                     | #major           |
| MINOR_STRING_TOKEN | optional | String in commit log to search for to bump minor version                                                                                                                                                                                                                     | #minor           |
| PATCH_STRING_TOKEN | optional | String in commit log to search for to bump patch version                                                                                                                                                                                                                     | #patch           |
| NONE_STRING_TOKEN  | optional | String in commit log to search for to prevent version bump                                                                                                                                                                                                                   | #none            |
| BRANCH_HISTORY     | optional | Set the history of the branch for finding '#bumps' (valid values are Possible values 'last' (single last commit), 'full' (all history, although semi-broken, do-not-use) and 'compare' (all commits since previous))                                                         | compare          |

## Outputs

| Name    | Description                                                                         |
|:--------|:------------------------------------------------------------------------------------|
| old_tag | Version tag before GitHub action run                                                |
| new_tag | Version tag after GitHub action run                                                 |
| part    | Version part that was bumped (not relevant when VERSIONING_SCHEME is 'build_number' |

## Version Bump

**Explicit:** Any commit message that includes `#major`, `#minor`, `#patch`, or `#none` will trigger the respective version bump. If two or more are present, the highest-ranking one will take precedence.
If `#none` is contained in the merge commit message, it will skip bumping regardless `DEFAULT_BUMP`.

**Implicit:** If no `#major`, `#minor` or `#patch` tag is contained in the merge commit message, it will bump whichever `DEFAULT_BUMP` is set to (which is `minor` by default). Disable this by setting `DEFAULT_BUMP` to `none`.

> **_Note:_** Version will not be bumped if there is no code difference since the last tagged version. Code difference is checked using `git diff`.
