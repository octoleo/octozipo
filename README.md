<h2><img align="middle" src="https://raw.githubusercontent.com/odb/official-bash-logo/master/assets/Logos/Icons/PNG/64x64.png" >
Octozipo - Convert Zip package to a repository.
</h2>

![Test](https://github.com/octoleo/octozipo/actions/workflows/test.yml/badge.svg)

Written by Llewellyn van der Merwe (@llewellynvdm)

Convert Zip packages to repositories and if they exist update and tag them.

Linted by [#ShellCheck](https://github.com/koalaman/shellcheck)

Octozipo can be used as a command line tool on your own machine, or as a
[GitHub Action](#github-action) that runs downstream of the workflow that builds your packages.

## Install

```shell
$ sudo curl -L "https://raw.githubusercontent.com/octoleo/octozipo/refs/heads/master/src/octozipo" -o /usr/local/bin/octozipo
$ sudo chmod +x /usr/local/bin/octozipo
```
- Global **environment** file can be set at: `$HOME/.config/octozipo/.env`
- OR/And Per projects **environment** file `.octozipo` inside the _same_ directory as the zip files

**Options:**
```txt
VDM_ORG="octoleo"
VDM_ZIP_DIR="/home/user/path/to/zip/files"
VDM_GIT_URL="git.vdm.dev"
VDM_PUSH_CREATE=true
VDM_SPACER="-"
VDM_GIT_DATE=""
VDM_REPORT_FILE=""
```

- VDM_ORG: git.vdm.dev/[ORG] in the repository path (default: joomla)
- VDM_ZIP_DIR: the full path to where you have placed all the zipped files (default: current dir)
- VDM_GIT_URL: the base URI of your gitea system (default: git.vdm.dev)
- VDM_PUSH_CREATE: switch to push-create repositories that don't already exist (default: false)
- VDM_SPACER: the character used between the words of a repository name (default: -)
- VDM_GIT_DATE: the date to use for the git commits (default: now)
- VDM_REPORT_FILE: write a tab separated report line per package to this file (default: none)

The string options (`VDM_ORG`, `VDM_ZIP_DIR`, `VDM_GIT_URL`, `VDM_SPACER`, `VDM_GIT_DATE`, `VDM_REPORT_FILE`,
`VDM_ENV_FILE_PATH` and `VDM_MAPPER_FILE_PATH`) can also be set as environment variables. The command line
options override the environment variables, and the values in an environment file override both.

**Git options:**

Octozipo uses the git user, signing and SSH configuration of the machine it runs on. These optional
environment variables set the details per repository instead:

```txt
GIT_AUTHOR_NAME="Your Name"
GIT_AUTHOR_EMAIL="your@email.tld"
GIT_SIGNING_KEY="GPGKEYID"
GIT_GPG_SIGN=true
GIT_SSH_KEY_PATH="/home/user/.ssh/id_ed25519"
```

When tag signing is enabled in your git configuration (`tag.gpgSign=true`) octozipo creates signed
(annotated) tags, using the commit message as the tag message, so it also works where no editor is available.

**Mapper file:**

The mapper file (`.octozipo.mapper` inside the directory of the zip files, `$HOME/.config/octozipo/.mapper`,
or the file given with `--mapper`) maps the name octozipo derives from a zip file to the repository and branch
that should be used:

```txt
my-package=my-repository
my-package_branch=develop
```

A package can also carry its own `.octozipo` file (at the root of the zip) with `repo_name=` and `repo_branch=`
values, which are looked up in the mapper file as well.

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
   --report=<file>
	write a tab separated report line per package
	(status, zip, git url, org, repo, branch, version)
	example: octozipo --report=/tmp/octozipo.tsv
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
	to print out all config details
	example: octozipo --debug
	======================================================
   --update
	to update your install
	example: octozipo --update
	======================================================
   -t | --access-token [********token**********]
	token needed to access private repo for update
	example: octozipo --access-token='********token**********'
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
			Octozipo v2.3.0
	======================================================
```
### Example

Execute the script in the directory where your zip files are found
```shell
$ octozipo -o joomla -p
```

This will target the git.vdm.dev/joomla organization and if a package is unzipped and not found it will push to create that repository.

### Report file

With `--report=<file>` (or `VDM_REPORT_FILE`) octozipo writes one tab separated line per package, so that
other tools can act on the result:

```txt
status  zip  git url  org  repo  branch  version
```

| Status      | Meaning                                                                       |
|-------------|-------------------------------------------------------------------------------|
| `created`   | the repository did not exist and was push-created                             |
| `updated`   | the existing repository received a new commit (and tag)                       |
| `unchanged` | the existing repository already matched the package                           |
| `pending`   | the repository does not exist and `--push-create` was not set (kept locally)  |
| `dry-run`   | processed with `--dry`, nothing was pushed                                    |
| `skipped`   | the package could not be unzipped                                             |
| `failed`    | the repository could not be cloned, committed or pushed (octozipo exits)      |

Errors are always written to stderr, also with `--quiet`, and the output of a failing git or unzip command
is shown so the reason can be found in automated logs.

## GitHub Action

Octozipo is also a GitHub Action, so it can run right after the workflow (or step) that builds your packages:
the build produces the zip packages in a directory, and octozipo pushes every package to its own repository,
creating, committing and tagging as needed.

Octozipo pushes over SSH (`git@<git-url>:<org>/<repo>.git`), so git must be configured and authenticated before
it runs. The [octoleo/git-user](https://github.com/octoleo/git-user) action does exactly that (git user, GPG
signing, SSH key and known hosts), and octozipo picks up that configuration.

### Workflow

```yaml
name: Publish packages

on:
  workflow_dispatch:
  push:
    branches: [master]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build the packages
        run: |
          # whatever builds your zip packages (for example the JCB compiler)
          mkdir -p "${{ runner.temp }}/packages"
          ./build.sh --output "${{ runner.temp }}/packages"

      - name: Setup Git User
        uses: octoleo/git-user@v2
        with:
          gpg-key: ${{ secrets.GPG_KEY }}
          gpg-user: ${{ secrets.GPG_USER }}
          ssh-key: ${{ secrets.SSH_KEY }}
          ssh-pub: ${{ secrets.SSH_PUB }}
          git-user: ${{ secrets.GIT_USER }}
          git-email: ${{ secrets.GIT_EMAIL }}
          ssh-host: ${{ vars.OCTOZIPO_GIT_URL }}

      - name: Push the packages to their repositories
        id: octozipo
        uses: octoleo/octozipo@master
        with:
          zip-dir: ${{ runner.temp }}/packages
          org: ${{ vars.OCTOZIPO_ORG }}
          git-url: ${{ vars.OCTOZIPO_GIT_URL }}
          push-create: ${{ vars.OCTOZIPO_PUSH_CREATE }}

      - name: Show the result
        run: |
          echo "Updated: ${{ steps.octozipo.outputs.repositories }}"
          echo '${{ steps.octozipo.outputs.report }}'
```

Pin `octoleo/octozipo` to a release tag (for example `@v2.3.0`) once you rely on it in production.

### Settings per repository

Every setting is an input of the action, so it can come from the
[repository or organisation variables](https://docs.github.com/en/actions/learn-github-actions/variables)
(`vars.*`) of the repository the workflow runs in, as in the example above. An empty input falls back to the
matching environment variable and then to the default, so a variable that is not set simply leaves the default
in place.

The examples in this README use these variables (set them under *Settings → Secrets and variables → Actions*):

| Variable               | Example       | Used for                                                     |
|------------------------|---------------|--------------------------------------------------------------|
| `OCTOZIPO_ORG`         | `joomla`      | the `org` input, the organisation that owns the repositories |
| `OCTOZIPO_GIT_URL`     | `git.vdm.dev` | the `git-url` input and the `ssh-host` of `octoleo/git-user` |
| `OCTOZIPO_PUSH_CREATE` | `true`        | the `push-create` input                                      |

`OCTOZIPO_GIT_URL` should always be set, since `octoleo/git-user` falls back to `github.com` for the SSH host
when it is empty, while octozipo falls back to `git.vdm.dev`.

The settings can also be set once as environment variables, on the step, the job or the whole workflow,
instead of (or next to) the inputs:

```yaml
      - name: Push the packages to their repositories
        uses: octoleo/octozipo@master
        env:
          VDM_ZIP_DIR: ${{ runner.temp }}/packages
          VDM_ORG: ${{ vars.OCTOZIPO_ORG }}
          VDM_GIT_URL: ${{ vars.OCTOZIPO_GIT_URL }}
          VDM_PUSH_CREATE: ${{ vars.OCTOZIPO_PUSH_CREATE }}
          VDM_MAPPER_FILE_PATH: .octozipo.mapper
```

Inputs win over environment variables. `zip-dir` and `org` must be given one way or the other.

### Inputs

| Input             | Required | Default       | Environment fallback   | Description                                                                             |
|-------------------|----------|---------------|------------------------|-----------------------------------------------------------------------------------------|
| `zip-dir`         | Yes      |               | `VDM_ZIP_DIR`          | Directory that holds the zip packages (relative to the workspace, or absolute)          |
| `org`             | Yes      |               | `VDM_ORG`              | Organisation/user that owns the repositories                                            |
| `git-url`         | No       | `git.vdm.dev` | `VDM_GIT_URL`          | Host name of the git server                                                             |
| `push-create`     | No       | `false`       | `VDM_PUSH_CREATE`      | Push to create repositories that do not exist yet (Gitea, not GitHub)                   |
| `mapper`          | No       |               | `VDM_MAPPER_FILE_PATH` | Mapper file that maps package names to repository names and branches                    |
| `env-file`        | No       |               | `VDM_ENV_FILE_PATH`    | Octozipo environment file (its values override the inputs)                              |
| `spacer`          | No       | `-`           | `VDM_SPACER`           | Character used between the words of a repository name                                   |
| `git-date`        | No       | now           | `VDM_GIT_DATE`         | Date to use for the git commits                                                         |
| `use-xml-name`    | No       | `false`       | `VDM_USE_XML_NAME`     | Use the name in the package XML manifest as the repository name                         |
| `keep-repo`       | No       | `false`       | `VDM_KEEP_REPO`        | Keep the cloned repository directories after processing                                 |
| `keep-zip`        | No       | `false`       | `VDM_KEEP_ZIP`         | Keep the zip packages after processing                                                  |
| `dry-run`         | No       | `false`       | `VDM_DRY_RUN`          | Do everything except pushing                                                            |
| `quiet`           | No       | `false`       | `VDM_QUIET`            | Mute the octozipo info messages (errors are still shown)                                |
| `debug`           | No       | `false`       | `VDM_DEBUG`            | Only print the resolved octozipo configuration                                          |
| `allow-empty`     | No       | `false`       | `VDM_ALLOW_EMPTY`      | Succeed with a warning when there are no packages, instead of failing                   |
| `report-file`     | No       | runner temp   | `VDM_REPORT_FILE`      | Path of the tab separated report file                                                   |
| `git-user`        | No       |               | `GIT_AUTHOR_NAME`      | Git author name (only when git is not configured yet)                                   |
| `git-email`       | No       |               | `GIT_AUTHOR_EMAIL`     | Git author email (only when git is not configured yet)                                  |
| `git-signing-key` | No       |               | `GIT_SIGNING_KEY`      | GPG key id used to sign the commits (only when git is not configured yet)               |
| `git-gpg-sign`    | No       |               | `GIT_GPG_SIGN`         | Sign the commits, `true` or `false` (only when git is not configured yet)               |
| `ssh-key-path`    | No       |               | `GIT_SSH_KEY_PATH`     | SSH private key used to reach the git server (only when SSH is not configured yet)      |

Boolean inputs accept `true`/`false`, `yes`/`no`, `on`/`off` and `1`/`0`.

The `git-*` and `ssh-key-path` inputs are only needed when you do not use `octoleo/git-user` (or another way
to configure git) before this action. With `ssh-key-path` the host key of the git server must already be
trusted (`~/.ssh/known_hosts`), otherwise git can not reach the server without a terminal.

### Outputs

| Output         | Description                                                                                   |
|----------------|-----------------------------------------------------------------------------------------------|
| `processed`    | Number of zip packages that were processed                                                    |
| `created`      | Number of repositories that were created (push-create)                                        |
| `updated`      | Number of existing repositories that received a new commit                                    |
| `unchanged`    | Number of existing repositories that already matched the package                              |
| `pending`      | Number of new repositories that were prepared but not pushed (`push-create` is off)           |
| `skipped`      | Number of packages that could not be unzipped                                                 |
| `failed`       | Number of packages whose repository could not be updated                                      |
| `dry-run`      | Number of packages processed without pushing (`dry-run`)                                      |
| `repositories` | Comma separated list of the repositories (`org/repo`) that were created or updated            |
| `report`       | JSON array with one object per package: `status`, `zip`, `git_url`, `org`, `repo`, `branch`, `version` |
| `report-file`  | Path of the tab separated [report file](#report-file)                                         |

The same information is added to the job summary of the workflow run. Pending and skipped packages show up as
warnings, and a failed package fails the step with the octozipo exit code (the outputs are still set, so a
later step with `if: always()` can use them).

### Chaining workflows

Octozipo runs after whatever produces the packages. Depending on where that happens, use one of these patterns.

**Same job** — build and publish in one job, as in the [workflow](#workflow) above. The packages are simply
in a directory of the runner.

**Separate jobs** — build in one job, publish in another with `needs:`, and hand the packages over as an
artifact:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build the packages
        run: ./build.sh --output build/packages
      - name: Upload the packages
        uses: actions/upload-artifact@v4
        with:
          name: packages
          path: build/packages/*.zip
          if-no-files-found: error

  publish:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Download the packages
        uses: actions/download-artifact@v4
        with:
          name: packages
          path: ${{ runner.temp }}/packages
      - uses: octoleo/git-user@v2
        with:
          gpg-key: ${{ secrets.GPG_KEY }}
          gpg-user: ${{ secrets.GPG_USER }}
          ssh-key: ${{ secrets.SSH_KEY }}
          ssh-pub: ${{ secrets.SSH_PUB }}
          git-user: ${{ secrets.GIT_USER }}
          git-email: ${{ secrets.GIT_EMAIL }}
          ssh-host: ${{ vars.OCTOZIPO_GIT_URL }}
      - uses: octoleo/octozipo@master
        with:
          zip-dir: ${{ runner.temp }}/packages
          org: ${{ vars.OCTOZIPO_ORG }}
          git-url: ${{ vars.OCTOZIPO_GIT_URL }}
          push-create: ${{ vars.OCTOZIPO_PUSH_CREATE }}
```

**Separate workflows** — a publish workflow that waits for the build workflow to complete, and downloads the
artifact of that run:

```yaml
name: Publish packages

on:
  workflow_run:
    workflows: ["Build"]
    types: [completed]

jobs:
  publish:
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    runs-on: ubuntu-latest
    steps:
      - name: Download the packages built by the Build workflow
        uses: actions/download-artifact@v4
        with:
          name: packages
          path: ${{ runner.temp }}/packages
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
      - uses: octoleo/git-user@v2
        with:
          gpg-key: ${{ secrets.GPG_KEY }}
          gpg-user: ${{ secrets.GPG_USER }}
          ssh-key: ${{ secrets.SSH_KEY }}
          ssh-pub: ${{ secrets.SSH_PUB }}
          git-user: ${{ secrets.GIT_USER }}
          git-email: ${{ secrets.GIT_EMAIL }}
          ssh-host: ${{ vars.OCTOZIPO_GIT_URL }}
      - uses: octoleo/octozipo@master
        with:
          zip-dir: ${{ runner.temp }}/packages
          org: ${{ vars.OCTOZIPO_ORG }}
          git-url: ${{ vars.OCTOZIPO_GIT_URL }}
          push-create: ${{ vars.OCTOZIPO_PUSH_CREATE }}
          allow-empty: true
```

Set `allow-empty: true` when the build may legitimately produce no packages, otherwise octozipo fails the
run when the directory holds no zip files.

### Testing

The test suite lives at `tests/test-action.sh`. It builds zip packages and bare "remote" repositories on the
fly, points the SSH urls octozipo uses at those local repositories (with a git `url.<base>.insteadOf` rewrite),
runs the action entry script and checks the repositories, the step outputs and the job summary. No git server,
SSH key or network access is needed.

Tests run automatically on every push to master, on every pull request, and can be triggered manually from the
Actions tab. The workflow also runs the action itself (`uses: ./`) against a local repository.

#### Running Locally

```bash
bash tests/test-action.sh ./src/action.sh
```

#### What The Tests Cover

- **Input validation** — missing `zip-dir` or `org`, invalid booleans, bad `git-url`, missing files
- **Empty directory** — fails by default, passes with `allow-empty`
- **Update and create** — an existing repository is updated and tagged, a new one is push-created, outputs, report file and summary match, a re-run is `unchanged`
- **Dry run** — nothing is pushed, the repository directory is kept
- **Pending** — a new repository without `push-create` is kept locally and reported with a warning
- **Push failure** — the git error is shown and the step fails with the octozipo exit code
- **Broken package** — a package that can not be unzipped is skipped, the others are still processed
- **Relative paths and environment fallbacks** — `VDM_*` variables and paths relative to the workspace
- **Mapper, spacer and use-xml-name** — repository and branch mapping
- **Environment file** — its values override the inputs
- **Git identity inputs** — the author and committer of the commits, the SSH key path
- **Quiet and debug** — info messages are muted, errors still show, debug processes nothing
- **Signed commits and tags** — with the git configuration `octoleo/git-user` writes, commits and tags are signed without a terminal

### Uninstall

```shell
$ octozipo --uninstall
```

### Free Software License
```txt
@copyright  Copyright (C) 2021 Llewellyn van der Merwe. All rights reserved.
@license    GNU General Public License version 2; see LICENSE.txt
```
