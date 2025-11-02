#! /bin/bash
# Expects Environment variables:
# REPOSITORIES_JSON: json array of repositories and their ref
# MERGE_DIRECTORY: The working / base directory repos will be merged into
# GITHUB_URL: The base url of the repository, usually https://github.com/
# track shell's errorexit status and switch it back if we have an error in case this file is being sourced
[[ ! -o errexit ]] && errorexit_off=true || true
set -e
on_exit() {
    if [ $errorexit_off ]; then set +e; fi
}
trap 'on_exit' EXIT

declare TMP_REPO_DIRECTORY=''

main() {
    assert_inputs_are_valid "$@"
    echo "✔ Checking Out Repositories"
    checkout_repos
    echo "⛙ Combining Repositories"
    merge_repos
}

assert_inputs_are_valid() {
    if [[ -z ${REPOSITORIES_JSON+x} ]]; then
        echo "No repositories have been set. Input \`repositories\` must be set to a list of repositories to merge."
        exit 1
    fi
    if ! jq -e . >/dev/null 2>&1 <<<"$REPOSITORIES_JSON"; then
        echo "Failed to parse REPOSITORIES_JSON. Not valid JSON."
        echo "REPOSITORIES_JSON:"
        echo "$REPOSITORIES_JSON"
    fi
    if [[ -z ${MERGE_DIRECTORY+x} ]]; then
        echo "Unexpected error: Merge directory not set. Input \`merge-directory\` must be set to a valid directory."
        exit 1
    fi
}

checkout_repos() {
    local _checkout_owner
    local _checkout_repo
    local _checkout_ref
    
    TMP_REPO_DIRECTORY=$(mktemp -d "tmp_repos.XXXXXXXXXXXXXXXX" -p .)
    trap 'rm -rf "$TMP_REPO_DIRECTORY"' EXIT

    if [[ -d "$MERGE_DIRECTORY" ]]; then
        echo "Cleaning '$MERGE_DIRECTORY'."
        rm -rf "$MERGE_DIRECTORY"
    fi
    mkdir -p "$MERGE_DIRECTORY"
    
    while IFS=$'\t' read -r _checkout_owner _checkout_repo _checkout_ref _; do
        # Cleanup any older / existing repo folders
        if [[ -d "$_checkout_repo" ]]; then
            echo "Cleaning up existing repository: $(realpath "$_checkout_repo")"
            rm -rf "$_checkout_repo"
        fi
        # Setup args and clone the repo
        local _clone_args=()
        [ -n "$_checkout_ref" ] && _clone_args+=(--branch "$_checkout_ref")
        _clone_args+=(--single-branch)
        # Set the url to clone from
        if [[ -n "${GITHUB_ACTIONS}" ]]; then
            _clone_args+=("${GH_PROTOCOL}x-access-token:${GH_TOKEN}@${GH_HOSTNAME}/${_checkout_owner}/${_checkout_repo}.git")
        else
            _clone_args+=("${GH_PROTOCOL}${GH_HOSTNAME}/${_checkout_owner}/${_checkout_repo}.git")
        fi
        # set the output folder
        _clone_args+=("${TMP_REPO_DIRECTORY}/${_checkout_repo}")
        # Clone the repo with the args from above
        echo "git clone ${_clone_args[@]}"
        git clone "${_clone_args[@]}"
    done < <(jq -r '.[] | [.owner, .repository, .ref] | @tsv' <<< "$REPOSITORIES_JSON")
}

merge_repos() {
    local _checkout_repo
    local _checkout_ref
    local _repo_name
    local _repo_path

    shopt -s dotglob
    while IFS=$'\t' read -r _repo_name _repo_path _; do
        local _repo_tmp_dir="${TMP_REPO_DIRECTORY}/${_repo_name}"
        # Test to make sure the repo_folder exists, and if it does remove the .git directory from it.
        if [[ ! -d "${_repo_tmp_dir}" ]]; then
            echo "Unexpected error. Expected to find a \"$_repo_name\" repository directory at $_repo_tmp_dir but none was found."
            exit 1
        elif [[ -d "${_repo_tmp_dir}/.git" ]]; then
            echo "Remove .git directory from repository $_repo_name."
            rm -rf "${_repo_tmp_dir}/.git"
        fi
        # copy the contents of the repo back to the working directory
        echo "Merging contents of '${_repo_tmp_dir}/${_repo_path}/' to '$(realpath "$MERGE_DIRECTORY")'"
        # cp -RT "${_repo_tmp_dir}/${_repo_path}/" "$MERGE_DIRECTORY/"
        (cd "${_repo_tmp_dir}/${_repo_path}" && tar c .) | (cd "$MERGE_DIRECTORY" && tar xf -)
    done < <(jq -r '.[] | [.repository, .path] | @tsv' <<< "$REPOSITORIES_JSON")
    shopt -u dotglob
    rm -rf "${TMP_REPO_DIRECTORY}"
    echo "All repositories merged to merge directory $(realpath "$MERGE_DIRECTORY")"
}

main "$@"