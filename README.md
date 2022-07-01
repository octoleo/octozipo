# Octozipo

Convert Zip packages to repositories and if they exist update and tag them.

## Install

## Get needed access token

Get a token from [https://git.vdm.dev/user/settings/applications](https://git.vdm.dev/user/settings/applications)

```shell
$ export SETUP_TOKEN="xxxxxxxxxxtokenxxxxxxxxxxxxxxxxxxxxxxxx"
$ sudo curl -L "https://git.vdm.dev/api/v1/repos/octoleo/octozipo/raw/src/octozipo?access_token=${SETUP_TOKEN}" -o /usr/local/bin/octozipo
$ sudo chmod +x /usr/local/bin/octozipo
```
- Global **environment** file can be set at: `/home/$USER/.config/octozipo/.env`
- OR/And Per projects **environment** file `.octozipo` inside the _same_ directory as the zip files

**Options:**
```txt
VDM_ORG="octoleo"
VDM_ZIP_DIR="/home/user/path/to/zip/files"
VDM_GIT_URL="git.vdm.dev"
VDM_PUSH_CREATE=true
```

- VDM_ORG: git.vdm.dev/[ORG] in the repository path (default: joomla)
- VDM_ZIP_DIR: the full path to where you have placed all the zipped files (default: current dir)
- VDM_GIT_URL: the base URI of your gitea system (default: git.vdm.dev)
- VDM_PUSH_CREATE: switch to push-create repositories that don't already exist (default: false)

## Usage

> To see the help menu
```shell
$ octozipo -h
```
---

> To update
```shell
$ octozipo --update
```

### Help Menu (Octozipo)
```txt
Usage: octozipo [OPTION...]
        Options
        ======================================================
   -o | --org=[ORG]
        directory of the org/user repository
        default: joomla
        example: octozipo -o=joomla
        example: octozipo --org=joomla
        ======================================================
   -z | --zip-dir=<full-path-to-directory>
        full path to directory of the zip files
        default: $PWD
        example: octozipo -z=/home/username/zipfiles
        example: octozipo --zip-dir=/home/username/zipfiles
        ======================================================
   -g | --git-url=<url>
        git remote repository base url
        default: git.vdm.dev
        example: octozipo -g=git.vdm.dev
        example: octozipo --git-url=git.vdm.dev
        ======================================================
   -m | --mapper=<file>
        load the mapping file
        that convert zip names to repo names
        example: octozipo --mapper=/src/.mapper
        ======================================================
   -e | --env=<file>
        load the environment variables file
        example: octozipo --env=/src/.env
        ======================================================
   -p | --push-create
        switch to try push create new repositories
        this may not work with github
        example: octozipo -p
        example: octozipo --push-create
        ======================================================
   -s | --spacer=<char>
        set the spacer used in repo name
        default: -
        example: octozipo -s _
        example: octozipo --spacer=_
        ======================================================
   --git-date=<date>
        set the git commit date
        default: Actual Date
        example: octozipo --git-date="Feb 14 03:18:31"
        ======================================================
   --keep-repo
        switch to keep the repository directory
        example: octozipo --keep-repo
        ======================================================
   --keep-zip
        switch to keep the zip file
        example: octozipo --keep-zip
        ======================================================
   --use-xml-name
        use the name found in the xml as the repository name
        example: octozipo --use-xml-name
        ======================================================
   -d | --dry
        dry run of the program
        example: octozipo --dry
        ======================================================
   -q | --quiet
        mute all output messages
        example: octozipo --quiet
        ======================================================
   --debug
        tp print out all config details
        example: octozipo --debug
        ======================================================
   --update
        to update your install
        example: octozipo --update
        ======================================================
   --uninstall
        to uninstall this script
        example: octozipo --uninstall
        ======================================================
   -h|--help
        display this help menu
        example: octozipo -h
        example: octozipo --help
        ======================================================
                        Octozipo v2.0.0
        ======================================================
```
### Example

Execute the script in the directory where your zip files are found
```shell
$ octozipo -o joomla -p
```

This will target the git.vdm.dev/joomla organization and if a package is unzipped and not found it will push to create that repository.

### Uninstall

```shell
$ octozipo --uninstall
```

### Free Software License
```txt
@copyright  Copyright (C) 2021 Llewellyn van der Merwe. All rights reserved.
@license    GNU General Public License version 2; see LICENSE.txt
```
