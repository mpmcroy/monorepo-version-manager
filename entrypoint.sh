#!/bin/bash

set -eo pipefail

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
default_branch=${DEFAULT_BRANCH:-$GITHUB_BASE_REF} # get the default branch from github runner env vars
component_name=${COMPONENT_NAME:-main}
component_dir=${COMPONENT_DIR:-.}
versioning_scheme=${VERSIONING_SCHEME:-semver} # valid values (semver, build_number)
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG:-}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
git_api_tagging=${GIT_API_TAGGING:-true}
initial_version=${INITIAL_VERSION:-0.0.0} #TODO: Add initial_version for build_number versioning scheme
tag_context=${TAG_CONTEXT:-repo}
prerelease=${PRERELEASE:-false}
suffix=${PRERELEASE_SUFFIX:-beta}
verbose=${VERBOSE:-false}
major_string_token=${MAJOR_STRING_TOKEN:-#major}
minor_string_token=${MINOR_STRING_TOKEN:-#minor}
patch_string_token=${PATCH_STRING_TOKEN:-#patch}
none_string_token=${NONE_STRING_TOKEN:-#none}
branch_history=${BRANCH_HISTORY:-compare}
# since https://github.blog/2022-04-12-git-security-vulnerability-announced/ runner uses?
git config --global --add safe.directory /github/workspace

cd "${GITHUB_WORKSPACE}/${source}" || exit 1

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tDEFAULT_BRANCH: ${default_branch}"
echo -e "\tCOMPONENT_NAME: ${component_name}"
echo -e "\tCOMPONENT_DIR: ${component_dir}"
echo -e "\tVERSIONING_SCHEME: ${versioning_scheme}"
echo -e "\tWITH_V: ${with_v}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tGIT_API_TAGGING: ${git_api_tagging}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tPRERELEASE: ${prerelease}"
echo -e "\tPRERELEASE_SUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"
echo -e "\tMAJOR_STRING_TOKEN: ${major_string_token}"
echo -e "\tMINOR_STRING_TOKEN: ${minor_string_token}"
echo -e "\tPATCH_STRING_TOKEN: ${patch_string_token}"
echo -e "\tNONE_STRING_TOKEN: ${none_string_token}"
echo -e "\tBRANCH_HISTORY: ${branch_history}"

if [[ "${versioning_scheme}" != @(semver|build_number) ]]
then
    echo "::error::Invalid versioning_scheme. Must be one of (semver, build_number)."
    exit 1
fi
if [[ "${versioning_scheme}" == build_number && ${prerelease} == "true" ]]
then
    echo "::error::Pre-release not supported for versioning_scheme build_number"
    exit 1
fi

# verbose, show everything
if $verbose
then
    set -x
fi

setOutput() {
    echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
}

bumpVersion() {
    local versioning_scheme="${1}"
    local bump_type="${2}"
    local version_tag="${3}"
    local result

    case $versioning_scheme in
        semver )
            result=$(semver -i "${bump_type}" "${version_tag}")
            ;;
        build_number )
            build_number_value=$((version_tag))
            ((build_number_value++))
            result="${build_number_value}"
            ;;
        * )
            echo "Unsupported versioning_scheme: ${versioning_scheme}"
            exit 1
            ;;
    esac

    echo "${result}"
}

current_branch=$(git rev-parse --abbrev-ref HEAD)

pre_release="$prerelease"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    # check if ${current_branch} is in ${release_branches} | exact branch match
    if [[ "$current_branch" == "$b" ]]
    then
        pre_release="false"
    fi
    # verify non specific branch names like  .* release/* if wildcard filter then =~
    if [ "$b" != "${b//[\[\]|.? +*]/}" ] && [[ "$current_branch" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

# fetch tags
git fetch --tags

semverTagFmt="^(${component_name}-)v?[0-9]+\.[0-9]+\.[0-9]+$"
semverPreTagFmt="^(${component_name}-)v?[0-9]+\.[0-9]+\.[0-9]+(-${suffix}\.[0-9]+)$"
buildNumberTagFmt="^(${component_name}-)v?[0-9]+$"
buildNumberPreTagFmt="^(${component_name}-)v?[0-9]+(-${suffix}\.[0-9]+)$"

component_tags=$(git tag -l "${component_name}-*" --sort=-v:refname)

case $versioning_scheme in
    semver )
        matching_component_tag_refs=$( (grep -E "${semverTagFmt}" <<< "${component_tags}") || true)
        matching_component_pre_tag_refs=$( (grep -E "${semverPreTagFmt}" <<< "${component_tags}") || true)
        ;;
    build_number )
        matching_component_tag_refs=$( (grep -E "${buildNumberTagFmt}" <<< "${component_tags}") || true)
        matching_component_pre_tag_refs=$( (grep -E "${buildNumberPreTagFmt}" <<< "${component_tags}") || true)
        ;;
    * )
        echo "Unsupported versioning_scheme: ${versioning_scheme}"
        exit 1
        ;;
esac

component_tag=$(head -n 1 <<< "${matching_component_tag_refs}")
component_pre_tag=$(head -n 1 <<< "${matching_component_pre_tag_refs}")
tag=${component_tag#"${component_name}-"}
pre_tag=${component_pre_tag#"${component_name}-"}

# if there are none, start tags at INITIAL_VERSION
if [ -z "$tag" ]
then
    if $with_v
    then
        tag="v$initial_version"
    else
        tag="$initial_version"
    fi
    if [ -z "$pre_tag" ] && $pre_release
    then
        if $with_v
        then
            pre_tag="v$initial_version"
        else
            pre_tag="$initial_version"
        fi
    fi
    tag_initialized=true
fi

# get current commit hash for tag
tag_commit=$(git rev-list -n 1 "${component_name}-${tag}" || true )
# get current commit hash
commit=$(git rev-parse HEAD)

if [ -z "$tag_initialized" ]
then
  component_diff=$(git diff "${component_tag:-HEAD}" HEAD -- "${component_dir}")
  if [ -z "${component_diff}" ]
  then
      echo "No new commits since previous tag. Skipping..."
      setOutput "old_tag" "${component_name}-${tag}"
      setOutput "new_tag" "${component_name}-${tag}"
      exit 0
  fi
fi

# sanitize that the default_branch is set (via env var when running on PRs) else find it natively
if [ -z "${default_branch}" ] && [ "$branch_history" == "full" ]
then
    echo "The DEFAULT_BRANCH should be autodetected when tag-action runs on on PRs else must be defined, See: https://github.com/anothrNick/github-tag-action/pull/230, since is not defined we find it natively"
    default_branch=$(git branch -rl '*/master' '*/main' | cut -d / -f2)
    echo "default_branch=${default_branch}"
    # re check this
    if [ -z "${default_branch}" ]
    then
        echo "::error::DEFAULT_BRANCH must not be null, something has gone wrong."
        exit 1
    fi
fi

# get the merge commit message looking for #bumps
declare -A history_type=(
    ["last"]="$(git show -s --format=%B)" \
    ["full"]="$(git log "${default_branch}"..HEAD --format=%B)" \
    ["compare"]="$(git log "${tag_commit}".."${commit}" --format=%B)" \
)
log=${history_type[${branch_history}]}
printf "History:\n---\n%s\n---\n" "$log"

case "$log" in
    *$major_string_token* )
        new=$(bumpVersion "${versioning_scheme}" major "${tag}")
        part="major"
        ;;
    *$minor_string_token* )
        new=$(bumpVersion "${versioning_scheme}" minor "${tag}")
        part="minor"
        ;;
    *$patch_string_token* )
        new=$(bumpVersion "${versioning_scheme}" patch "${tag}")
        part="patch"
        ;;
    *$none_string_token* )
        echo "Default bump was set to none. Skipping..."
        setOutput "old_tag" "${component_name}-${tag}"
        setOutput "new_tag" "${component_name}-${tag}"
        setOutput "part" "$default_semvar_bump"
        exit 0;;
    * )
        if [ "$default_semvar_bump" == "none" ]
        then
            echo "Default bump was set to none. Skipping..."
            setOutput "old_tag" "${component_name}-${tag}"
            setOutput "new_tag" "${component_name}-${tag}"
            setOutput "part" "$default_semvar_bump"
            exit 0
        else
            new=$(bumpVersion "${versioning_scheme}" "${default_semvar_bump}" "${tag}")
            part=$default_semvar_bump
        fi
        ;;
esac

if $pre_release
then
    # get current commit hash for tag
    pre_tag_commit=$(git rev-list -n 1 "${component_name}-${pre-tag}" || true)
    # skip if there are no new commits for pre_release
    if [ "$pre_tag_commit" == "$commit" ]
    then
        echo "No new commits since previous pre_tag. Skipping..."
        setOutput "old_tag" "${component_name}-${pre-tag}"
        setOutput "new_tag" "${component_name}-${pre-tag}"
        exit 0
    fi
    # already a pre-release available, bump it
    if [[ "$pre_tag" =~ $new ]] && [[ "$pre_tag" =~ $suffix ]]
    then
        if $with_v
        then
            new=v$(semver -i prerelease "${pre_tag}" --preid "${suffix}")
        else
            new=$(semver -i prerelease "${pre_tag}" --preid "${suffix}")
        fi
        echo -e "Bumping ${suffix} pre-tag ${pre_tag}. New pre-tag ${new}"
    else
        if $with_v
        then
            new="v$new-$suffix.0"
        else
            new="$new-$suffix.0"
        fi
        echo -e "Setting ${suffix} pre-tag ${pre_tag} - With pre-tag ${new}"
    fi
    part="pre-$part"
else
    if $with_v
    then
        new="v$new"
    fi
    echo -e "Bumping tag ${component_name}-${tag} - New tag ${component_name}-${new}"
fi

# as defined in readme if CUSTOM_TAG is used any semver calculations are irrelevant.
if [ -n "$custom_tag" ]
then
    new="$custom_tag"
fi

# set outputs
setOutput "old_tag" "${component_name}-${tag}"
setOutput "new_tag" "${component_name}-${new}"
setOutput "part" "${component_name}-${part}"

# dry run exit without real changes
if $dryrun
then
    exit 0
fi

echo "EVENT: creating local tag ${component_name}-${new}"
# create local git tag
git tag -f "${component_name}-${new}" || exit 1
echo "EVENT: pushing tag ${component_name}-${new} to origin"

if $git_api_tagging
then
    # use git api to push
    dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
    full_name=$GITHUB_REPOSITORY
    git_refs_url=$(jq .repository.git_refs_url "$GITHUB_EVENT_PATH" | tr -d '"' | sed 's/{\/sha}//g')

    echo "$dt: **pushing tag ${component_name}-${new} to repo $full_name"

    git_refs_response=$(
    curl -s -X POST "$git_refs_url" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d @- << EOF
{
    "ref": "refs/tags/${component_name}-${new}",
    "sha": "$commit"
}
EOF
)

    git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

    echo "::debug::${git_refs_response}"
    if [ "${git_ref_posted}" = "refs/tags/${component_name}-${new}" ]
    then
        exit 0
    else
        echo "::error::Tag was not created properly."
        exit 1
    fi
else
    # use git cli to push
    git push -f origin "${component_name}-${new}" || exit 1
fi
