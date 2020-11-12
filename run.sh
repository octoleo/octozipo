#! /bin/bash

# set the defaults
ORG="octoleo"
ROOT_DIR="$PWD"
REMOTE_SYSTEM="git.vdm.dev"
PUSH_CREATE=false

# add env to system
if [ -f ".env" ]; then
  source .env
fi

# catch the values passed
ORG="${1:-$ORG}"
PUSH_CREATE="${2:-$PUSH_CREATE}"
ROOT_DIR="${3:-$ROOT_DIR}"
REMOTE_SYSTEM="${4:-$REMOTE_SYSTEM}"

# show globals if needed
# echo "$ORG"
# echo "$ROOT_DIR"
# echo "$REMOTE_SYSTEM"
# exit

main() {
  # make sure the root dir exist
  if [ -d "$ROOT_DIR" ]; then
    # go to folder where zip files are placed
    cd "$ROOT_DIR" || exit 3
    # check that the folder has zip files
    # shellcheck disable=SC2012
    [ "$(ls -1 ./*.zip 2>/dev/null | wc -l)" == 0 ] && showError "looking for zip files, since no zip files in the folder $ROOT_DIR ERROR-NR" 6
    # get all zip files
    for z in *.zip; do
      # get folder and repo name
      repo=$(getRepoName "$z")
      # get folder and repo name
      version=$(getVersion "$z")
      echo "${repo} - v${version}"
      # check if the repo exist on our system
      if git ls-remote "git@${REMOTE_SYSTEM}:${ORG}/${repo}.git" -q >/dev/null 2>&1; then
        setExistingRepository "$repo" "${version:-0}" "$z" || showError "Update Repo:(${repo}) ERROR-NR" 7
      else
        setNewRepository "$repo" "${version:-0}" "$z" || showError "Setup Repo:(${repo}) ERROR-NR" 7
      fi
    done
  else
    showError "opening of folder $ROOT_DIR as it does not exist ERROR-NR" 5
  fi
}

# get repository name
getRepoName() {
  local name
  name=$(rightStrip "$1" "-v*")
  name=$(rightStrip "$name" "_v*")
  name=$(rightStrip "$name" ".zip")
  echo "$name"
}

# get current version
getVersion() {
  local version
  version=$(leftStrip "$1" "*-v")
  version=$(leftStrip "$version" "*_v")
  version=$(rightStrip "$version" ".zip")
  version=${version//-/\.}
  version=${version//_/\.}
  version=$(rightStrip "$version" "..*")
  echo "$version"
}

# Strip pattern from end of string
rightStrip() {
  # Usage: rightStrip "string" "pattern"
  printf '%s\n' "${1%%$2}"
}

# Strip pattern from start of string
leftStrip() {
  # Usage: leftStrip "string" "pattern"
  printf '%s\n' "${1##$2}"
}

# setup new repository
setNewRepository() {
  echo "New repository (${REMOTE_SYSTEM}:${ORG}/$1)"
  # set repo path
  repo_path="$ROOT_DIR/$1"
  # set zip path
  zip_path="$ROOT_DIR/$3"
  # we creat the repo dir
  mkdir -p "$repo_path"
  # change to this directory and make sure its empty
  if cd "$repo_path" >/dev/null 2>&1; then
    rm -rf ./*
  else
    return 1
  fi
  # we unzip the data to this new folder
  if unzip "$zip_path" -d "$repo_path" >/dev/null 2>&1; then
    echo "Successfully unzipped the package"
  else
    return 1
  fi
  # we initialize the git repo locally
  setGitInit "$1" "$2" || return 1
  # check if push create is allowed
  if ($PUSH_CREATE); then
    # we push to create this repo
    git push -u origin master >/dev/null 2>&1
    # check if we have tags to push
    git push --tags >/dev/null 2>&1
    # always move back to root folder
    cd "$ROOT_DIR" || return 1
    # we remove the ZIP file
    rm "${zip_path:?}"
    # we can also remove the folder
    rm -rf "${repo_path:?}"
    # pushed create
    echo "Push created ($1-v$2) repository"
  else
    # give action info
    echo "When ready link and push changes to remote"
    # always move back to root folder
    cd "$ROOT_DIR" || return 1
    # we remove the ZIP file
    # rm "$zip_path" (don't remove since we may need to run this again if a name of the zip has changed)
  fi
  return 0
}

# show an error
showError() {
  echo "We encountered and error on $1:$2"
  exit "$2"
}

# make git commit of the update and set the new tag
setGitInit() {
  # check if this is an existing local repo
  if [ -d ".git" ]; then
    if [[ -z $(git status --porcelain) ]]; then
      echo "No changes found in repository"
    else
      if [ "$(git tag -l "v$2")" ]; then
        setGitCommit "$2" "update" || return 4
      else
        setGitCommit "$2" "update - v$2" || return 4
      fi
    fi
  else
    git init || return 4
    setGitCommit "$2" "first commit - v$2" || return 4
    git remote add origin "git@${REMOTE_SYSTEM}:${ORG}/${1}.git"
  fi
  return 0
}

# make git commit of the update and set the new tag
setGitCommit() {
  git add . >/dev/null 2>&1 || return 1
  git commit -am"$2" >/dev/null 2>&1 || return 1
  # check if tag exist
  if [ "$(git tag -l "v$1")" ]; then
    return 0
  else
    git tag "v$1" >/dev/null 2>&1 || return 1
  fi
  return 0
}

# make git commit of the update and set the new tag
setPushChanges() {
  git push >/dev/null 2>&1 || return 1
  git push --tags >/dev/null 2>&1 || return 1
  return 0
}

# update repository repository
setExistingRepository() {
  echo "Update ($1-v$2) repository"
  # set repo path
  repo_path="$ROOT_DIR/$1"
  # set zip path
  zip_path="$ROOT_DIR/$3"
  # check if repo is locally found
  cd "$repo_path" >/dev/null 2>&1 || git clone "git@${REMOTE_SYSTEM}:${ORG}/${1}.git"
  # make sure we are in the correct dir
  if cd "$repo_path" >/dev/null 2>&1; then
    rm -rf ./*
  else
    return 1
  fi
  # now lets unzip the new data to this repo
  if unzip "$zip_path" -d "$repo_path" >/dev/null 2>&1; then
    echo "Successfully unzipped the package"
  else
    # break out
    return 1
  fi
  # lets check if there are changes
  if [[ -z $(git status --porcelain) ]]; then
    echo "No changes found in ($1-v$2) repository"
  else
    if [ "$(git tag -l "v$2")" ]; then
      setGitCommit "$2" "update" || return 4
    else
      setGitCommit "$2" "update - v$2" || return 4
    fi
    # push the changes
    setPushChanges || return 1
    # updated the repository
    echo "Pushed update to ($1-v$2) repository"
  fi
  # always move back to root folder
  cd "$ROOT_DIR" || return 1
  # we remove the ZIP file
  rm "${zip_path:?}"
  # we can also remove the folder
  rm -rf "${repo_path:?}"
  # success
  return 0
}

# run main
main
