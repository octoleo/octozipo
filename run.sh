#! /bin/bash

# set the defaults
ORG="octoleo"
ROOTDIR="$PWD"
REMOTESYSTEM="git.vdm.dev"
PUSH_CREATE=false

# add env to system
if [ -f ".env" ]; then
	source .env
fi

# catch the values passed
ORG="${1:-$ORG}"
ROOTDIR="${2:-$ROOTDIR}"
REMOTESYSTEM="${3:-$REMOTESYSTEM}"

# show globals if needed
# echo "$ORG"
# echo "$ROOTDIR"
# echo "$REMOTESYSTEM"
# exit

main() {
	# make sure the root dir exist
	if [ -d "$ROOTDIR" ]; then
		# go to folder where zip files are placed
		cd "$ROOTDIR"
		# check that the folder has zip files
		[ $( ls -1 *.zip 2>/dev/null | wc -l ) == 0 ] && showerror "looking for zip files, since no zip files in the folder $ROOTDIR ERROR-NR" 6
		# get all zip files
		for z in *.zip; do
			# get folder and repo name
			repo=$(getreponame "$z")
			# get folder and repo name
			version=$(getversion "$z")
			echo "${repo} - v${version}"
			# check if the repo exist on our system
			git ls-remote "git@${REMOTESYSTEM}:${ORG}/${repo}.git" -q >/dev/null 2>&1 && updaterepo "$repo" "${version:-0}" "$z" || setuprepo "$repo" "${version:-0}" "$z"
		done
	else
		showerror "opening of folder $ROOTDIR as it does not exist ERROR-NR" 5
	fi
}

# get repository name
getreponame() {
	local name
	name=$(rstrip "$1" "-v*")
	name=$(rstrip "$name" "_v*")
	name=$(rstrip "$name" ".zip")
	echo "$name"
}

# get current version
getversion() {
	local version
	version=$(lstrip "$1" "*-v")
	version=$(lstrip "$version" "*_v")
	version=$(rstrip "$version" ".zip")
	version=${version//-/\.}
	version=${version//_/\.}
	version=$(rstrip "$version" "..*")
	echo "$version"
}

# Strip pattern from end of string
rstrip() {
	# Usage: rstrip "string" "pattern"
	printf '%s\n' "${1%%$2}"
}

# Strip pattern from start of string
lstrip() {
	# Usage: lstrip "string" "pattern"
	printf '%s\n' "${1##$2}"
}

# setup new repository
setuprepo() {
	echo "New repository (${REMOTESYSTEM}:${ORG}/$1)"
	# set repo path
	repopath="$ROOTDIR/$1"
	# set zip path
	zippath="$ROOTDIR/$3"
	# we creat the repo dir
	mkdir -p "$repopath"
	# change to this directory and make sure its empty
	cd "$repopath" >/dev/null 2>&1 && rm -rf * || showerror "$1" 3
	# we unzip the data to this new folder
	unzip "$zippath" -d "$repopath" >/dev/null 2>&1 && echo "Succefuly unzipped the package" || showerror "$1" 4
	# we inistialize the git repo localy
	makegitinit "$1" "$2"
	# check if push create is allowed
	if ( $PUSH_CREATE ); then
		# we push to create this repo
		git push -u origin master
		# always move back to root folder
		cd "$ROOTDIR"
		# we remove the ZIP file
		rm "$zippath"
		# we can also remove the folder
		rm -rf "$repopath"
	else
		# give action info
		echo "When ready link and push changes to remote"
		# always move back to root folder
		cd "$ROOTDIR"
		# we remove the ZIP file
		# rm "$zippath" (don't remove since we may need to run this again if a name of the zip has changed)
	fi
}

# show an error
showerror() {
	echo "We encounterd and error on $1:$2"
	exit $2
}

# make git commit of the update and set the new tag
makegitinit(){
	# check if this is an existing local repo
	if [ -d ".git" ]; then
		[[ -z $(git status --porcelain) ]] && echo "No changes found in repository" || makegitcommit "$2" "update - v$2"
	else
		git init
		makegitcommit "$2" "first commit - v$2"
		git remote add origin "git@${REMOTESYSTEM}:${ORG}/${1}.git"
	fi
}

# make git commit of the update and set the new tag
makegitcommit(){
	git add .
	git commit -am"$2"
	git tag "v$1"
}

# make git commit of the update and set the new tag
pushchanges(){
	git push
	git push --tags
}

# update repository repository
updaterepo() {
	echo "Update ($1-v$2) repository"
	# set repo path
	repopath="$ROOTDIR/$1"
	# set zip path
	zippath="$ROOTDIR/$3"
	# check if repo is localy found
	cd "$repopath" >/dev/null 2>&1 || git clone git@${REMOTESYSTEM}:${ORG}/${1}.git
	# make sure we are in the correct dir
	cd "$repopath" >/dev/null 2>&1 && rm -rf * || showerror "$1" 1
	# now lets unzip the new data to this repo
	unzip "$zippath" -d "$repopath" >/dev/null 2>&1 && echo "Succefuly unzipped the package" || showerror "$1" 2
	# lets check if there are changes
	[[ -z $(git status --porcelain) ]] && echo "No changes found in ($1-v$2) repository" || (makegitcommit "$2" "update - v$2" && pushchanges)
	# always move back to root folder
	cd "$ROOTDIR"
	# we remove the ZIP file
	rm "$zippath"
	# we can also remove the folder
	rm -rf "$repopath"
}

# run main
main
