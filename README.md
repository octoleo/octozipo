## Convert Zip Packages to Repositories

The idea of this script is to update a bunch of respositories at once with simple zip packages.

## Install

Clone this repository
```shell
$ git clone https://git.vdm.dev/octoleo/zip-to-repo.git
```

Then setup your own **environment** file `.env` with the following values:
```txt
ORG="octoleo"
ROOTDIR="/home/user/path/to/zip/files/"
REMOTESYSTEM="git.vdm.dev"
PUSH_CREATE=true
```

- ORG: git.vdm.dev/[ORG] in the repository path
- ROOTDIR: the full path to where you have placed all the zipped files
- REMOTESYSTEM: the base URI of your gitea system
- PUSH_CREATE: switch to push-create repositories that don't already exist

## Run the script

Make the script executable
```shell
$ sudo chmod +x run.sh
```

Execute the script
```shell
$ ./run.sh
```

### Free Software License
```txt
@copyright  Copyright (C) 2021 Llewellyn van der Merwe. All rights reserved.
@license    GNU General Public License version 2 or later; see LICENSE.txt
```

