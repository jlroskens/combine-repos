#! /bin/bash
# Expects Environment variables:
# MERGE_REPOSITORIES: ${{ inputs.repositories }}
# Optional:
# MERGE_DIRECTORY: ${{ inputs.merge-directory }}

# Writes github outputs if GITHUB_ACTIONS is set (this is set automatically by github actions)
# Outputs:
# repositories-json: Json of the repositories and their ref

# track shell's errorexit status and switch it back if we have an error in case this file is being sourced
[[ ! -o errexit ]] && errorexit_off=true || true
set -e
on_exit() {
    if [ $errorexit_off ]; then set +e; fi
}
trap 'on_exit' EXIT


main() {
    echo "🔬 Validating and Reading Inputs"
    assert_inputs_are_valid "$@"
    assign_outputs
}

assert_inputs_are_valid() {
    if [[ -z ${MERGE_REPOSITORIES+x} ]]; then
        echo "No repositories have been set. Input \`repositories\` must be set to a list of repositories to merge."
        exit 1
    fi
}

trim() {
    local _var_to_trim="$*"
    # remove leading whitespace characters
    var="${_var_to_trim#"${_var_to_trim%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${_var_to_trim%"${_var_to_trim##*[![:space:]]}"}"
    printf '%s' "$_var_to_trim"
}

output_value() {
    local _output_name="$1"
    local _output_value="${@:2}"
    if [[ -z ${GITHUB_ACTIONS+x} ]]; then
        # If not in a workflow, replace the dashes and export with an uppercase variable name
        export_name="${_output_name/-/_}"
        export ${export_name^^}="$_output_value"
    else
        echo $_output_name="$_output_value" >> $GITHUB_OUTPUT
    fi
}

assign_outputs() {
    local _repos_json=''
    local _repo_part=''
    local _repo_path=''
    local _repo_owner_and_name=''
    local _repository=''
    local _owner=''
    local _repo_name=''
    local _repo_ref=''
    # local _repos=0    
    if [[ -n "${MERGE_REPOSITORIES}" ]]; then
        while read _repository; do
            # let "_repos++"
            _repository=$(trim "$_repository")
            IFS=' ' read -r _repo_part _repo_path <<< $_repository
            # Remove slash from the beginning and/or end of the path
            _repo_path="${_repo_path#/}"
            _repo_path="${_repo_path%/}"
            if [[ -z "${_repo_path}" ]]; then _repo_path='.'; fi
            # Extract the repository path and ref from the input string
            IFS=':' read -r _repo_owner_and_name _repo_ref <<< $_repo_part
            # Extract the repo name and owner from the combined _repo_owner_and_name from above
            IFS='/' read -r _repo_owner _repo_name <<< $_repo_owner_and_name
            # strip the .git extension if they added it
            _repo_name="${_repo_name%/.git/}"
            # Create an array of an object with owner, repository and ref fields
            _repo_json=$(jq -cn --arg owner "$_repo_owner" \
                                --arg repository "$_repo_name" \
                                --arg ref "$_repo_ref" \
                                --arg path "$_repo_path" '[$ARGS.named]')
            # Append new element to the existing array if it exists, otherwise set the json to the new array
            if [[ -n "$_repos_json" ]]; then
                _repos_json=$(jq -cn --argjson repos "$_repos_json" --argjson repo "$_repo_json" '$repos + $repo')
            else
                _repos_json=$_repo_json
            fi
        done <<< "$MERGE_REPOSITORIES"
        output_value 'repositories-json' "${_repos_json}"
        # output_value 'repositories-count' $_repos
    fi

    if [[ -z ${MERGE_DIRECTORY+x} ]]; then
        output_value 'merge-directory' '_merged_repos'
    else
        output_value 'merge-directory' "$MERGE_DIRECTORY"
    fi

    if [[ -z ${GITHUB_URL+x} ]]; then
        output_value 'gh-hostname' 'github.com'
        output_value 'gh-protocol' 'https://'
        output_value 'github-url' 'https://github.com'
    else
        _url_regex='^(http[s]:\/\/)([^\s][^\/]+)(\/(\w+\/?)*)?'
        if [[ $GITHUB_URL =~ $_url_regex ]]; then
            output_value 'gh-protocol' "${BASH_REMATCH[1]}"
            output_value 'gh-hostname' "${BASH_REMATCH[2]}"
        else
            echo "Warn: Invalid Github URL: ${GITHUB_URL}. Updating to https://gitub.com/"
            output_value 'gh-hostname' 'github.com'
            output_value 'gh-protocol' 'https://'
            output_value 'github-url' 'https://github.com'
        fi
    fi
}

main "$@"
on_exit