# Octozipo

Convert Zip packages to repositories and if they exist update and tag them.

## Install

```shell
$ sudo curl -L "https://git.vdm.dev/api/v1/repos/octoleo/octozipo/raw/src/octozipo" -o /usr/local/bin/octozipo
$ sudo chmod +x /usr/local/bin/octozipo
```
- Global **environment** file can be set at: `/home/$USER/.config/octozipo/.env`
- OR/And Per projects **environment** file `.octozipo` inside the _same_ directory as the zip files

**Options:**
```txt
VDM_ORG="octoleo"
VDM_ROOT_DIR="/home/user/path/to/zip/files/"
VDM_REMOTE_SYSTEM="git.vdm.dev"
VDM_PUSH_CREATE=true
```

- VDM_ORG: git.vdm.dev/[ORG] in the repository path (default: octoleo)
- VDM_ROOT_DIR: the full path to where you have placed all the zipped files (default: current dir)
- VDM_REMOTE_SYSTEM: the base URI of your gitea system (default: git.vdm.dev)
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
   -e | --env=<file>
	load the environment variables file
	example: octozipo --env=/src/.env
	======================================================
   -q | --quiet
	mute all output messages
	example: octozipo --quiet
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
			Octozipo v1.0.1
	======================================================
```
### Example

Execute the script in the directory where your zip files are found
```shell
$ octozipo joomla true
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
