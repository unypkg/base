#!/usr/bin/env bash

## This is the unypkg base system build script
## Created by michacassola mich@casso.la
######################################################################################################################
######################################################################################################################
# Run as root on Ubuntu LTS

cat <<EOF


######################################################################################################################
######################################################################################################################

Setting up the build system

######################################################################################################################
######################################################################################################################


EOF

if [[ $EUID -gt 0 ]]; then
    echo "Not root, exiting..."
    exit
fi

apt update && apt install -y gcc g++ gperf bison flex texinfo help2man make libncurses5-dev \
    python3-dev autoconf automake libtool libtool-bin gawk curl bzip2 xz-utils unzip \
    patch libstdc++6 rsync gh git meson ninja-build gettext autopoint libsigsegv-dev

### Getting Variables from files
UNY_AUTO_PAT="$(cat UNY_AUTO_PAT)"
export UNY_AUTO_PAT
# shellcheck disable=SC2034
GH_TOKEN="$(cat GH_TOKEN)"
export GH_TOKEN

### Setup the Shell
ln -fs /bin/bash /bin/sh

export UNY=/uny
tee >/root/.bash_profile <<EOF
export UNY=/uny
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
EOF
# shellcheck source=/dev/null
source /root/.bash_profile

### Setup Git and GitHub
# Setup Git User -
git config --global user.name "uny-auto"
git config --global user.email "uny-auto@unyqly.com"
git config --global credential.helper store
git config --global advice.detachedHead false

git credential approve <<EOF
protocol=https
url=https://github.com
username=uny-auto
password="$UNY_AUTO_PAT"
EOF

# gh auth with uny-auto classic personal access token
# This only works interactively
# gh auth login --with-token #<<<"$UNY_AUTO_PAT"

### Add uny user
groupadd uny
useradd -s /bin/bash -g uny -m -k /dev/null uny

### Create uny chroot skeleton
mkdir -pv "$UNY"/home
mkdir -pv "$UNY"/sources/unygit
chmod -v a+wt "$UNY"/sources

mkdir -pv "$UNY"/{etc,var} "$UNY"/usr/{bin,lib,sbin}
mkdir -pv "$UNY"/build/logs

for i in bin lib sbin; do
    ln -sv usr/$i "$UNY"/$i
done

case $(uname -m) in
x86_64) mkdir -pv "$UNY"/lib64 ;;
esac

mkdir -pv "$UNY"/tools

chown -R uny:uny "$UNY"/* #{usr{,/*},lib,var,etc,bin,sbin,tools}
case $(uname -m) in
x86_64) chown -v uny "$UNY"/lib64 ;;
esac

[ ! -e /etc/bash.bashrc ] || mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE

######################################################################################################################
######################################################################################################################
### Download sources

cat <<EOF


######################################################################################################################
######################################################################################################################

Downloading sources

######################################################################################################################
######################################################################################################################


EOF

cd "$UNY"/sources || exit

# new vdet date information
uny_build_date_seconds_now="$(date +%s)"
uny_build_date_now="$(date -d @"$uny_build_date_seconds_now" +"%Y-%m-%dT%H.%M.%SZ")"

######################################################################################################################
######################################################################################################################
### functions

function check_for_repo_and_create {
    # Create repo if it doesn't exist
    if [[ $(curl -s -o /dev/null -w "%{http_code}" https://github.com/unypkg/"$pkgname") != "200" ]]; then
        gh repo create unypkg/"$pkgname" --public
        [[ ! -d unygit ]] && mkdir -v unygit
        git -C unygit clone https://github.com/unypkg/"$pkgname".git
        touch unygit/"$pkgname"/emptyfile
        git -C unygit/"$pkgname" add .
        git -C unygit/"$pkgname" commit -m "Make repo non-empty"
        git -C unygit/"$pkgname" push origin
    fi
}

function git_clone_source_repo {
    # shellcheck disable=SC2001
    pkg_head="$(echo "$latest_head" | sed "s|.*refs/[^/]*/||")"
    pkg_git_repo="$(echo "$pkggit" | cut --fields=1 --delimiter=" ")"
    pkg_git_repo_dir="$(basename "$pkg_git_repo" | cut -d. -f1)"
    [[ -d "$pkg_git_repo_dir" ]] && rm -rf "$pkg_git_repo_dir"
    # shellcheck disable=SC2086
    git clone $gitdepth --single-branch -b "$pkg_head" "$pkg_git_repo"
}

function version_details {
    # Download last vdet file
    curl -LO https://github.com/unypkg/"$pkgname"/releases/latest/download/vdet
    old_commit_id="$(sed '2q;d' vdet)"
    uny_build_date_seconds_old="$(sed '4q;d' vdet)"
    [[ $latest_commit_id == "" ]] && latest_commit_id="$latest_ver"

    # pkg will be built, if commit id is different and newer.
    # Before a pkg is built the existence of a vdet-"$pkgname"-new file is checked
    if [[ "$latest_commit_id" != "$old_commit_id" && "$uny_build_date_seconds_now" -gt "$uny_build_date_seconds_old" ]]; then
        {
            echo "$latest_ver"
            echo "$latest_commit_id"
            echo "$uny_build_date_now"
            echo "$uny_build_date_seconds_now"
        } >vdet-"$pkgname"-new
    fi
}

function archiving_source {
    rm -rf "$pkg_git_repo_dir"/.git "$pkg_git_repo_dir"/.git*
    [[ -d "$pkgname-$latest_ver" ]] && rm -rf "$pkgname-$latest_ver"
    mv -v "$pkg_git_repo_dir" "$pkgname-$latest_ver"
    XZ_OPT="--threads=0" tar -cJpf "$pkgname-$latest_ver".tar.xz "$pkgname-$latest_ver"
}

function repo_clone_version_archive {
    check_for_repo_and_create
    git_clone_source_repo
    version_details
    archiving_source
}

######################################################################################################################
######################################################################################################################

######################################################################################################################
### glibc
pkgname="glibc"
pkggit="https://sourceware.org/git/glibc.git refs/heads/release/*/master"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --heads --sort="v:refname" $pkggit | tail --lines=1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=4)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

## To-Do: Make test with git diff --binary for glibc-2.37 release and with security backports from release/2.37/master
repo_clone_version_archive

######################################################################################################################
### Binutils
pkgname="binutils"
pkggit="https://sourceware.org/git/binutils-gdb.git refs/heads/binutils-$(git ls-remote --refs --sort="v:refname" https://sourceware.org/git/binutils-gdb.git refs/tags/binutils-[0-9_]* | tail -n 1 | grep -Eo "[0-9_]*" | tail -n 1 | grep -Eo "[0-9]_[0-9]*")-branch"
gitdepth="--depth=25"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --heads --sort="v:refname" $pkggit | tail --lines=1)"
latest_ver="$(echo "$latest_head" | grep -o "[0-9_]*" | tail -n 1 | sed "s|_|.|")"

check_for_repo_and_create
git_clone_source_repo

latest_commit_id="$(git -C "$pkg_git_repo_dir" log --perl-regexp --author='^((?!GDB Administrator).*)$' -n 1 | grep "commit" | cut -d" " -f 2)"
git -C "$pkg_git_repo_dir" checkout "$latest_commit_id"
rm -r "$pkg_git_repo_dir"/{contrib,djunpack.bat,gdb,gdb*,libbacktrace,libdecnumber,multilib.am,readline,sim}

version_details
archiving_source

######################################################################################################################
### GCC
pkgname="gcc"
pkggit="https://gcc.gnu.org/git/gcc.git refs/heads/releases/gcc*"
gitdepth="--depth=25"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --heads --sort="v:refname" $pkggit | tail --lines=1)"
# shellcheck disable=SC2086
latest_ver="$(git ls-remote --refs --sort="v:refname" $pkggit | grep -oE "gcc-[^0-9]*(([0-9]+\.)*[0-9]+)" | sed "s|gcc-||" | sort -n | tail -n 1)"

check_for_repo_and_create
git_clone_source_repo

latest_commit_id="$(git -C "$pkg_git_repo_dir" log --perl-regexp --author='^((?!GCC Administrator).*)$' -n 1 | grep "commit" | cut -d" " -f 2)"
git -C "$pkg_git_repo_dir" checkout "$latest_commit_id"

version_details
archiving_source

######################################################################################################################
######################################################################################################################
### Exit if Glibc, Binutils or GCC are not newer
if [[ -f vdet-glibc-new || -f vdet-binutils-new || -f vdet-gcc-new ]]; then
    echo "Continuing"
else
    echo "No new version of Glibc, Binutils or GCC found, exiting..."
    exit
fi

######################################################################################################################
### Linux API Headers
pkgname="linux-api-headers"
pkggit="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git refs/heads/linux-rolling-stable"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --heads --sort="v:refname" $pkggit | tail --lines=1)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

## To-Do: Make test with git diff --binary for glibc-2.37 release and with security backports from release/2.37/master
check_for_repo_and_create
git_clone_source_repo

# shellcheck disable=SC2086
latest_ver="$(git ls-remote --refs --tags --sort="v:refname" $pkg_git_repo | grep -Ev "\-rc[0-9]" | grep -oE "[0-9]*(([0-9]+\.)*[0-9]+)" | tail -n 1)"

version_details
archiving_source

######################################################################################################################
### M4
pkgname="m4"
pkggit="https://git.savannah.gnu.org/r/m4.git refs/tags/v1.4*"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --sort="v:refname" $pkggit | tail --lines=1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/m4/m4-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Ncurses
pkgname="ncurses"
pkggit="https://github.com/ThomasDickey/ncurses-snapshots.git refs/tags/*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --sort="v:refname" $pkggit | grep -E "v[0-9]_[0-9]+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed -e "s|v||" -e "s|_|.|")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Bash
pkgname="bash"
pkggit="https://git.savannah.gnu.org/git/bash.git refs/*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --tags --refs --sort="v:refname" $pkggit | grep -E "bash-[0-9].[0-9]$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed -e "s|bash-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Coreutils
pkgname="coreutils"
pkggit="https://git.savannah.gnu.org/git/coreutils.git refs/tags/v*"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --sort="v:refname" $pkggit | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/coreutils/coreutils-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Diffutils
pkgname="diffutils"
pkggit="https://git.savannah.gnu.org/git/diffutils.git refs/tags/v*"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/diffutils/diffutils-"$latest_ver".tar.xz

version_details

######################################################################################################################
### File
pkgname="file"
pkggit="https://github.com/file/file.git refs/tags/FILE*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed -e "s|FILE||" -e "s|_|.|")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create
git_clone_source_repo

cd "$pkg_git_repo_dir" || exit
autoreconf -i
cd /uny/sources || exit

version_details
archiving_source

######################################################################################################################
### Findutils
pkgname="findutils"
pkggit="https://git.savannah.gnu.org/git/findutils.git refs/tags/v*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/findutils/findutils-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Gawk
pkgname="gawk"
pkggit="https://git.savannah.gnu.org/git/gawk.git refs/tags/gawk-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "gawk-[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|gawk-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Grep
pkgname="grep"
pkggit="https://git.savannah.gnu.org/git/grep.git refs/tags/v*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9].[0-9]+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/grep/grep-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Gzip
pkgname="gzip"
pkggit="https://git.savannah.gnu.org/git/gzip.git refs/tags/v*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9].[0-9]+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/gzip/gzip-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Make
pkgname="make"
pkggit="https://git.savannah.gnu.org/git/make.git refs/tags/[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/make/make-"$latest_ver".tar.gz

version_details

######################################################################################################################
### Patch
pkgname="patch"
pkggit="https://git.savannah.gnu.org/git/patch.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/patch/patch-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Sed
pkgname="sed"
pkggit="https://git.savannah.gnu.org/git/sed.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/sed/sed-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Tar
pkgname="tar"
pkggit="https://git.savannah.gnu.org/git/tar.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/tar/tar-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Xz
pkgname="xz"
pkggit="https://github.com/tukaani-project/xz.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Gettext
pkgname="gettext"
pkggit="https://git.savannah.gnu.org/git/gettext.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/gettext/gettext-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Bison
pkgname="bison"
pkggit="https://git.savannah.gnu.org/git/bison.git  refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/bison/bison-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Perl
pkgname="perl"
pkggit="https://github.com/Perl/perl5.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Python
pkgname="python"
pkggit="https://github.com/python/cpython.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9](.[0-9]+)[^a-z]+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Texinfo
pkgname="texinfo"
pkggit="https://git.savannah.gnu.org/git/texinfo.git refs/tags/texinfo-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "texinfo-[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|texinfo-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/texinfo/texinfo-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Util-Linux
pkgname="util-linux"
pkggit="https://github.com/util-linux/util-linux.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### zLib
pkgname="zlib"
pkggit="https://github.com/madler/zlib.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Bzip2
pkgname="bzip2"
pkggit="https://gitlab.com/bzip2/bzip2.git refs/tags/bzip2-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "bzip2-[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|bzip2-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Zstd
pkgname="zstd"
pkggit="https://github.com/facebook/zstd.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Readline
pkgname="readline"
pkggit="https://git.savannah.gnu.org/git/readline.git refs/tags/readline-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "readline-[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|readline-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Bc
pkgname="bc"
pkggit="https://github.com/gavinhoward/bc.git refs/tags/[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Flex
pkgname="flex"
pkggit="https://github.com/westes/flex.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Tcl
pkgname="tcl"
pkggit="https://github.com/tcltk/tcl.git refs/tags/core-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "core-[0-9](-[0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed -e "s|core-||" -e "s|-|.|g")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Expect
pkgname="expect"
expectver="5.45.4"
curl -LO https://prdownloads.sourceforge.net/expect/expect"$expectver".tar.gz
tar xf expect"$expectver".tar.gz
rm expect"$expectver".tar.gz
chown -R root:root expect"$expectver"
mv expect"$expectver" expect-"$expectver"
XZ_OPT="--threads=0" tar -cJpf expect-"$expectver".tar.xz expect-"$expectver"

latest_ver="$expectver"
latest_commit_id="$expectver"

check_for_repo_and_create
version_details

######################################################################################################################
### DejaGNU
pkgname="dejagnu"
pkggit="https://git.savannah.gnu.org/git/dejagnu.git refs/tags/dejagnu-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "dejagnu-[0-9](\.[0-9]+)+-release$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed -e "s|dejagnu-||" -e "s|-release||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### GMP
pkgname="gmp"

latest_pkg="$(curl https://ftp.gnu.org/gnu/gmp/ | tac | tac | grep -oE "gmp-.*.tar.xz\"" | sed "s|\"||" | tail -n 1)"
latest_ver="$(echo "$latest_pkg" | cut --delimiter='-' --fields=2 | sed "s|.tar.xz||")"
latest_commit_id="$latest_ver"

curl -LO https://ftp.gnu.org/gnu/gmp/"$latest_pkg"
tar xf "$latest_pkg"
chown -R root:root gmp-*

check_for_repo_and_create
version_details

######################################################################################################################
### MPFR
pkgname="mpfr"
pkggit="https://gitlab.inria.fr/mpfr/mpfr.git refs/tags/[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create
git_clone_source_repo

cd "$pkg_git_repo_dir" || exit
autoreconf -i
cd /uny/sources || exit

version_details
archiving_source

######################################################################################################################
### MPC
pkgname="mpc"
pkggit="https://gitlab.inria.fr/mpc/mpc.git refs/tags/[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create
git_clone_source_repo

cd "$pkg_git_repo_dir" || exit
autoreconf -i
cd /uny/sources || exit

version_details
archiving_source

######################################################################################################################
### Attr
pkgname="attr"
pkggit="https://git.savannah.gnu.org/git/attr.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://download.savannah.nongnu.org/releases/attr/attr-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Acl
pkgname="acl"
pkggit="https://git.savannah.gnu.org/git/acl.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://download.savannah.gnu.org/releases/acl/acl-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Libcap
pkgname="libcap"
pkggit="https://git.kernel.org/pub/scm/libs/libcap/libcap.git refs/tags/libcap-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "libcap-[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|libcap-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Shadow
pkgname="shadow"
pkggit="https://github.com/shadow-maint/shadow.git refs/tags/[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Pkg-config
pkgname="pkg-config"
pkggit="https://gitlab.freedesktop.org/pkg-config/pkg-config.git refs/tags/pkg-config-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "pkg-config-[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|pkg-config-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Libtool
pkgname="libtool"
pkggit="https://git.savannah.gnu.org/git/libtool.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/libtool/libtool-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Expat
pkgname="expat"
pkggit="https://github.com/libexpat/libexpat.git refs/tags/R_[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "R_[0-9](_[0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed -e "s|R_||" -e "s|_|.|g")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Less
pkgname="less"
pkggit="https://github.com/gwsw/less.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Autoconf
pkgname="autoconf"
pkggit="https://git.savannah.gnu.org/git/autoconf.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/autoconf/autoconf-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Automake
pkgname="automake"
pkggit="https://git.savannah.gnu.org/git/automake.git refs/tags/v[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://ftp.gnu.org/gnu/automake/automake-"$latest_ver".tar.xz

version_details

######################################################################################################################
######################################################################################################################
### Run the next part as uny user

cat <<EOF


######################################################################################################################
######################################################################################################################

Building temporary system as uny user

######################################################################################################################
######################################################################################################################


EOF

# Change ownership to uny
chown -R uny:uny "$UNY"/*

sudo -i -u uny bash <<"EOFUNY"
set -vx

######################################################################################################################
######################################################################################################################
### Functions

cat >/uny/build/stage_functions <<"EOF"
function unpack_cd {
    cd "$UNY"/sources/ || exit
    [[ ! -d $(echo $pkgname* | grep -Eo "$pkgname-[^0-9]*(([0-9]+\.)*[0-9]+)" | sort -u) ]] && tar xf "$pkgname"*.tar.*
    cd "$(echo $pkgname* | grep -Eo "$pkgname-[^0-9]*(([0-9]+\.)*[0-9]+)" | sort -u)" || exit
}

function cleanup {
    cd "$UNY"/sources/ || exit
    rm -rf "$(echo $pkgname* | grep -Eo "$pkgname-[^0-9]*(([0-9]+\.)*[0-9]+)" | sort -u)"
}
EOF

######################################################################################################################
######################################################################################################################

cat >~/.bash_profile <<"EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

cat >~/.bashrc <<"EOF"
set +h
umask 022
UNY=/uny
LC_ALL=POSIX
UNY_TGT=$(uname -m)-uny-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$UNY/tools/bin:$PATH
CONFIG_SITE=$UNY/usr/share/config.site
export UNY LC_ALL UNY_TGT PATH CONFIG_SITE
MAKEFLAGS="-j$(nproc)"
source "$UNY"/build/stage_functions
EOF
EOFUNY

sudo -i -u uny bash <<"EOFUNY"
source ~/.bashrc

######################################################################################################################
######################################################################################################################
### Start timing
SECONDS=0

######################################################################################################################
### Binutils Pass 1

pkgname="binutils"

unpack_cd

mkdir -v build
cd build || exit

../configure --prefix="$UNY"/tools \
    --with-sysroot="$UNY" \
    --target="$UNY_TGT" \
    --disable-nls \
    --enable-gprofng=no \
    --disable-werror

make -j"$(nproc)"
make install

cleanup

######################################################################################################################
### GCC Pass 1

pkgname="gcc"

unpack_cd

### Additional packages
tar -xf ../mpfr-*.tar.xz
mv -v mpfr-* mpfr
tar -xf ../gmp-*.tar.xz
mv -v gmp-* gmp
tar -xf ../mpc-*.tar.xz
mv -v mpc-* mpc

case $(uname -m) in
x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
    ;;
esac

mkdir -v build
cd build || exit

glibcver="$(echo "$UNY"/sources/glibc-*.tar* | grep -Eo '[0-9]\.[0-9]+')"

../configure \
    --target="$UNY_TGT" \
    --prefix="$UNY"/tools \
    --with-glibc-version="$glibcver" \
    --with-sysroot="$UNY" \
    --with-newlib \
    --without-headers \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-nls \
    --disable-shared \
    --disable-multilib \
    --disable-threads \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --enable-languages=c,c++

make -j"$(nproc)"
make install

cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
    "$(dirname "$("$UNY_TGT"-gcc -print-libgcc-file-name)")"/include/limits.h

cleanup

######################################################################################################################
### Linux API Headers

pkgname="linux"

unpack_cd

make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include "$UNY"/usr

cleanup

######################################################################################################################
### glibc

pkgname="glibc"

case $(uname -m) in
i?86)
    ln -sfv ld-linux.so.2 "$UNY"/lib/ld-lsb.so.3
    ;;
x86_64)
    ln -sfv ../lib/ld-linux-x86-64.so.2 "$UNY"/lib64
    ln -sfv ../lib/ld-linux-x86-64.so.2 "$UNY"/lib64/ld-lsb-x86-64.so.3
    ;;
esac

unpack_cd

mkdir -v build
cd build || exit

echo "rootsbindir=/usr/sbin" >configparms

../configure \
    --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(../scripts/config.guess)" \
    --enable-kernel=3.2 \
    --with-headers="$UNY"/usr/include \
    libc_cv_slibdir=/usr/lib

make -j"$(nproc)"
make DESTDIR="$UNY" install

sed '/RTLDLIST=/s@/usr@@g' -i "$UNY"/usr/bin/ldd

#mkheaders_command=("$UNY"/tools/libexec/gcc/"$UNY_TGT"/*/install-tools/mkheaders)
"${mkheaders_command[@]}"

cleanup

######################################################################################################################
### Libstdc++

pkgname="gcc"

unpack_cd

mkdir -v build
cd build || exit

gccver="$(echo /uny/tools/x86_64-uny-linux-gnu/include/c++/* | grep -o "[^/]*$")"

../libstdc++-v3/configure \
    --host="$UNY_TGT" \
    --build="$(../config.guess)" \
    --prefix=/usr \
    --disable-multilib \
    --disable-nls \
    --disable-libstdcxx-pch \
    --with-gxx-include-dir=/tools/"$UNY_TGT"/include/c++/"$gccver"

make -j"$(nproc)"
make DESTDIR="$UNY" install

rm -v "$UNY"/usr/lib/lib{stdc++,stdc++fs,supc++}.la

cleanup

######################################################################################################################
### M4

pkgname="m4"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)"

make -j"$(nproc)"
make DESTDIR="$UNY" install

cleanup

######################################################################################################################
### Ncurses

pkgname="ncurses"

unpack_cd

sed -i s/mawk// configure

mkdir build
pushd build || exit
../configure
make -C include
make -C progs tic
popd || exit

./configure \
    --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(./config.guess)" \
    --mandir=/usr/share/man \
    --with-manpage-format=normal \
    --with-shared \
    --without-normal \
    --with-cxx-shared \
    --without-debug \
    --without-ada \
    --disable-stripping \
    --enable-widec

make -j"$(nproc)"
make DESTDIR="$UNY" TIC_PATH="$(pwd)"/build/progs/tic install

echo "INPUT(-lncursesw)" >"$UNY"/usr/lib/libncurses.so

cleanup

######################################################################################################################
### Bash

pkgname="bash"

unpack_cd

./configure --prefix=/usr \
    --build="$(sh support/config.guess)" \
    --host="$UNY_TGT" \
    --without-bash-malloc

make -j"$(nproc)"
make DESTDIR=$UNY install

ln -sv bash $UNY/bin/sh

cleanup

######################################################################################################################
### Coreutils

pkgname="coreutils"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)" \
    --enable-install-program=hostname \
    --enable-no-install-program=kill,uptime

make -j"$(nproc)"
make DESTDIR=$UNY install

mv -v $UNY/usr/bin/chroot $UNY/usr/sbin
mkdir -pv $UNY/usr/share/man/man8
mv -v $UNY/usr/share/man/man1/chroot.1 $UNY/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' $UNY/usr/share/man/man8/chroot.8

cleanup

######################################################################################################################
### Diffutils

pkgname="diffutils"

unpack_cd

./configure --prefix=/usr --host="$UNY_TGT"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### File

pkgname="file"

unpack_cd

mkdir build
pushd build || exit

../configure --disable-bzlib \
    --disable-libseccomp \
    --disable-xzlib \
    --disable-zlib

make -j"$(nproc)"
popd || exit

./configure --prefix=/usr --host="$UNY_TGT" --build="$(./config.guess)"

make FILE_COMPILE="$(pwd)"/build/src/file -j"$(nproc)"
make DESTDIR=$UNY install

rm -v $UNY/usr/lib/libmagic.la

cleanup

######################################################################################################################
### Findutils

pkgname="findutils"

unpack_cd

./configure --prefix=/usr \
    --localstatedir=/var/lib/locate \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Gawk

pkgname="gawk"

unpack_cd

sed -i 's/extras//' Makefile.in

./configure --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Grep

pkgname="grep"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Gzip

pkgname="gzip"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Make

pkgname="make"

unpack_cd

sed -e '/ifdef SIGPIPE/,+2 d' \
    -e '/undef  FATAL_SIG/i FATAL_SIG (SIGPIPE);' \
    -i src/main.c

./configure --prefix=/usr \
    --without-guile \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Patch

pkgname="patch"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Sed

pkgname="sed"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Tar

pkgname="tar"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)"

make -j"$(nproc)"
make DESTDIR=$UNY install

cleanup

######################################################################################################################
### Xz

pkgname="xz"

unpack_cd

./configure --prefix=/usr \
    --host="$UNY_TGT" \
    --build="$(build-aux/config.guess)" \
    --disable-static \
    --docdir=/usr/share/doc/xz

make -j"$(nproc)"
make DESTDIR=$UNY install

rm -v $UNY/usr/lib/liblzma.la

cleanup

######################################################################################################################
### Binutils Pass 2

pkgname="binutils"

unpack_cd

mkdir -v build
cd build || exit

../configure \
    --prefix=/usr \
    --build="$(../config.guess)" \
    --host="$UNY_TGT" \
    --disable-nls \
    --enable-shared \
    --enable-gprofng=no \
    --disable-werror \
    --enable-64-bit-bfd

make -j"$(nproc)"
make DESTDIR=$UNY install

rm -v $UNY/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes}.{a,la}

cleanup

######################################################################################################################
### GCC Pass 2

pkgname="gcc"

unpack_cd

### Additional packages
tar -xf ../mpfr-*.tar.xz
mv -v mpfr-* mpfr
tar -xf ../gmp-*.tar.xz
mv -v gmp-* gmp
tar -xf ../mpc-*.tar.gz
mv -v mpc-* mpc

case $(uname -m) in
x86_64)
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    ;;
esac

sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in

mkdir -v build
cd build || exit

../configure \
    --build="$(../config.guess)" \
    --host="$UNY_TGT" \
    --target="$UNY_TGT" \
    LDFLAGS_FOR_TARGET=-L"$PWD"/"$UNY_TGT"/libgcc \
    --prefix=/usr \
    --with-build-sysroot=$UNY \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-nls \
    --disable-multilib \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --enable-languages=c,c++

make -j"$(nproc)"
make DESTDIR=$UNY install

ln -sv gcc $UNY/usr/bin/cc

cleanup

set +vx

######################################################################################################################
######################################################################################################################
### Timing end
duration=$SECONDS
echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."

EOFUNY

######################################################################################################################
######################################################################################################################
### Run as root

cat <<EOF


######################################################################################################################
######################################################################################################################

Setting up the chroot system and building temporary tools inside of it

######################################################################################################################
######################################################################################################################


EOF

### Make chroot reusable with unyc command
cat >/bin/unyc <<'EOFUNYC'
#!/usr/bin/env bash

cat <<EOF

Mounting virtual file systems and entering uny's chroot

#######################################################
### Welcome to uny's chroot ###########################
#######################################################

EOF
mount --bind /dev $UNY/dev         #>/dev/null
mount --bind /dev/pts $UNY/dev/pts #>/dev/null
mount -t proc proc $UNY/proc       #>/dev/null
mount -t sysfs sysfs $UNY/sys      #>/dev/null
mount -t tmpfs tmpfs $UNY/run      #>/dev/null

if [ -h $UNY/dev/shm ]; then
    mkdir -pv $UNY/"$(readlink $UNY/dev/shm)"
else
    mount -t tmpfs -o nosuid,nodev tmpfs $UNY/dev/shm
fi

UNY_PATH="$(cat /uny/uny/paths/bin):$(cat /uny/uny/paths/sbin):/usr/bin:/usr/sbin"
chroot "$UNY" /usr/bin/env -i \
    HOME=/uny/root \
    TERM="$TERM" \
    PS1='uny | \u:\w\$ ' \
    PATH="$UNY_PATH" \
    bash --login

cat <<EOF

Exited uny's chroot and unmounting virtual file systems

#######################################################
### See you soon ######################################
#######################################################

EOF

mountpoint -q $UNY/dev/shm && umount $UNY/dev/shm
umount $UNY/dev/pts
umount $UNY/{sys,proc,run,dev}
EOFUNYC
chmod +x /bin/unyc

chown -R root:root $UNY/*
case $(uname -m) in
x86_64) chown -R root:root $UNY/lib64 ;;
esac

######################################################################################################################
######################################################################################################################
### Enter Chroot

mkdir -pv $UNY/{dev,proc,sys,run}

mount -v --bind /dev $UNY/dev
mount -v --bind /dev/pts $UNY/dev/pts
mount -vt proc proc $UNY/proc
mount -vt sysfs sysfs $UNY/sys
mount -vt tmpfs tmpfs $UNY/run

if [ -h $UNY/dev/shm ]; then
    mkdir -pv $UNY/"$(readlink $UNY/dev/shm)"
else
    mount -t tmpfs -o nosuid,nodev tmpfs $UNY/dev/shm
fi

chroot "$UNY" /usr/bin/env -i \
    HOME=/uny/root \
    TERM="$TERM" \
    PS1='uny auto | \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    bash -x <<'EOFUNY2'
######################################################################################################################
######################################################################################################################
### In the Chroot

######################################################################################################################
### Chroot setup

mkdir -pv /home
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware

mkdir -pv /usr/{,local/}{include,src}
mkdir -pv /usr/local/{bin,lib,sbin}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}

ln -sfv /run /var/run
ln -sfv /run/lock /var/lock

install -dv -m 0750 /uny/root
install -dv -m 1777 /tmp /var/tmp

ln -sv /proc/self/mounts /etc/mtab
cat >/etc/hosts <<EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF

cat >/etc/passwd <<"EOF"
root:x:0:0:root:/uny/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat >/etc/group <<"EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

echo "tester:x:101:101::/home/tester:/bin/bash" >>/etc/passwd
echo "tester:x:101:" >>/etc/group
install -o tester -d /home/tester

##########################
#exec /usr/bin/bash --login
/usr/bin/bash --login

touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664 /var/log/lastlog
chmod -v 600 /var/log/btmp

######################################################################################################################
######################################################################################################################
### Building temporary tools

######################################################################################################################
### Functions

# shellcheck source=/dev/null
source /build/stage_functions

######################################################################################################################
### Gettext

pkgname="gettext"

unpack_cd

./configure --disable-shared

make -j"$(nproc)"

cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin

cleanup

######################################################################################################################
### Bison

pkgname="bison"

unpack_cd

./configure --prefix=/usr \
    --docdir=/usr/share/doc/bison

make -j"$(nproc)"
make install

cleanup

######################################################################################################################
### Perl

pkgname="perl"

unpack_cd

sh Configure -des \
    -Dprefix=/usr \
    -Dvendorprefix=/usr \
    -Dprivlib=/usr/lib/perl5/core_perl \
    -Darchlib=/usr/lib/perl5/core_perl \
    -Dsitelib=/usr/lib/perl5/site_perl \
    -Dsitearch=/usr/lib/perl5/site_perl \
    -Dvendorlib=/usr/lib/perl5/vendor_perl \
    -Dvendorarch=/usr/lib/perl5/vendor_perl

make -j"$(nproc)"
make install

cleanup

######################################################################################################################
### Python

pkgname="Python"

unpack_cd

./configure --prefix=/usr \
    --enable-shared \
    --without-ensurepip

make -j"$(nproc)"
make install

cleanup

######################################################################################################################
### Texinfo

pkgname="texinfo"

unpack_cd

./configure --prefix=/usr

make -j"$(nproc)"
make install

cleanup

######################################################################################################################
### Util-Linux

pkgname="util-linux"

unpack_cd

mkdir -pv /var/lib/hwclock

./configure ADJTIME_PATH=/var/lib/hwclock/adjtime \
    --libdir=/usr/lib \
    --docdir=/usr/share/doc/util-linux \
    --disable-chfn-chsh \
    --disable-login \
    --disable-nologin \
    --disable-su \
    --disable-setpriv \
    --disable-runuser \
    --disable-pylibmount \
    --disable-static \
    --without-python \
    runstatedir=/run

make -j"$(nproc)"
make install

cleanup

######################################################################################################################
######################################################################################################################
### Cleaning

rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name \*.la -delete
rm -rf /tools

######################################################################################################################
######################################################################################################################
### Timing end
duration=$SECONDS
echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."

EOFUNY2

######################################################################################################################
######################################################################################################################
### Exit chroot and Backup

mountpoint -q $UNY/dev/shm && umount $UNY/dev/shm
umount $UNY/dev/pts
umount $UNY/{sys,proc,run,dev}

cd $UNY || exit
XZ_OPT="-0 --threads=0" tar -cJpf /home/lfs-temp-tools-11.3.tar.xz .

######################################################################################################################
######################################################################################################################
### Reenter Chroot

cat <<EOF


######################################################################################################################
######################################################################################################################

Building the base system in the chroot

######################################################################################################################
######################################################################################################################


EOF

mount -v --bind /dev $UNY/dev
mount -v --bind /dev/pts $UNY/dev/pts
mount -vt proc proc $UNY/proc
mount -vt sysfs sysfs $UNY/sys
mount -vt tmpfs tmpfs $UNY/run

if [ -h $UNY/dev/shm ]; then
    mkdir -pv $UNY/"$(readlink $UNY/dev/shm)"
else
    mount -t tmpfs -o nosuid,nodev tmpfs $UNY/dev/shm
fi

chroot "$UNY" /usr/bin/env -i \
    HOME=/uny/root \
    TERM="$TERM" \
    PS1='uny | \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    bash -x <<'EOFUNY3'
######################################################################################################################
######################################################################################################################
### In the Chroot

######################################################################################################################
## Uny setup

### Directories and Symlinks
mkdir -v /uny /pkg
ln -sv /pkg /uny/pkg # ln [OPTION]... TARGET... DIRECTORY
mkdir -v /etc/uny
mkdir -v /uny/paths
[[ -f /uny/paths/bin ]] && rm -rf /uny/paths/*

# Set PATH and functions on login
tee /uny/root/.profile <<'EOF'
source /uny/paths/pathenv
source /uny/build/functions
EOF

### Temporary standard headers
# Get paths from: echo | gcc -Wp,-v -x c++ - -fsyntax-only
# and echo | gcc -Wp,-v -x c - -fsyntax-only
touch /uny/paths/include-c-base
touch /uny/paths/include-cplus-base
c_include_base=(/usr/lib/gcc/x86_64-uny-linux-gnu/*)
cplus_include_base=(/usr/include/c++/*)
[[ -d /uny/include"${c_include_base[*]}" ]] && rm -rf /uny/include"${c_include_base[*]}"
mkdir -vp /uny/include"${c_include_base[*]}" /uny/include/usr/include/c++
cp -av "${c_include_base[*]}"/include /uny/include"${c_include_base[*]}"
cp -av "${c_include_base[*]}"/include-fixed /uny/include"${c_include_base[*]}"
cp -av "${cplus_include_base[*]}" /uny/include"${cplus_include_base[*]}"
echo -n "/uny/include${c_include_base[*]}/include:/uny/include${c_include_base[*]}/include-fixed" >/uny/paths/include-c-base
echo -n "/uny/include${cplus_include_base[*]}:/uny/include${cplus_include_base[*]}/x86_64-uny-linux-gnu:/uny/include${cplus_include_base[*]}/backward" >/uny/paths/include-cplus-base

######################################################################################################################
######################################################################################################################
### Building packages

tee /uny/build/functions <<'EOF'
#!/usr/bin/env bash

function add_to_paths_files {
    for usrpath in /uny/pkg/"$pkgname"/"$pkgver"/*; do
        pathtype=$(basename "$usrpath")
        [[ ! -f /uny/paths/$pathtype ]] && touch /uny/paths/"$pathtype"
        if grep -q "/$pkgname/[^/:]*" /uny/paths/"$pathtype"; then
            sed "s+/$pkgname/[^/:]*+/$pkgname/$pkgver+" -i /uny/paths/"$pathtype"
        else
            [[ ! $pkgname == "glibc" ]] && delim=":" || delim=""
            echo -n "$delim/uny/pkg/$pkgname/$pkgver/$pathtype" >>/uny/paths/"$pathtype"
        fi
    done
    # shellcheck source=/dev/null
    source /uny/paths/pathenv
}

function remove_from_paths_files {
    for usrpath in /uny/pkg/"$pkgname"/"$pkgver"/*; do
        pathtype=$(basename "$usrpath")
        if grep -q "/$pkgname/[^/:]*" /uny/paths/"$pathtype"; then
            sed -z -e "s|:.[^:]*$pkgname/[^:]*||" -e "s/\n//g" -i /uny/paths/"$pathtype"
        fi
    done
    # shellcheck source=/dev/null
    source /uny/paths/pathenv
}

function version_verbose_log_clean_unpack_cd {
    SECONDS=0
    shopt -s nocaseglob
    pkgver="$(echo /sources/$pkgname*.tar* | sed "s/$pkgname//" | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')"
    [[ ! -d /uny/build/logs ]] && mkdir /uny/build/logs
    LOG_FILE=/uny/build/logs/"$pkgname-$pkgver"-unypkg-build-$(date -u +"%Y-%m-%dT%H.%M.%SZ").log
    exec 3>&1 4>&2
    trap 'exec 2>&4 1>&3' 0 1 2 3 15
    exec > >(tee "$LOG_FILE") 2>&1
    set -vx
    # shellcheck disable=SC2269
    pkgname="$pkgname"
    # shellcheck disable=SC2269
    pkgver="$pkgver"

    remove_from_paths_files
    rm -rf /uny/pkg/"$pkgname"/"$pkgver"
    rm -rf /sources/"$pkgname"*"$pkgver"
    cd /sources || exit
    tar xf "$pkgname"*.tar.*
    cd "$(echo $pkgname* | grep -Eio "$pkgname.[^0-9]*(([0-9]+\.)*[0-9]+)" | sort -u)" || exit
}

function get_env_var_values {
    libpath="$(cat /uny/paths/lib):/uny/pkg/$pkgname/$pkgver/lib"
    LIBRARY_PATH="$libpath" # Used during linking
    export LIBRARY_PATH
    ldflags="-Wl,-rpath=$libpath -Wl,--dynamic-linker=$(grep -o "^.*glibc/[^:]*" /uny/paths/lib)/ld-linux-x86-64.so.2" # Used at runtime
    export LDFLAGS="$ldflags"
    LD_RUN_PATH=$libpath # Used at runtime
    export LD_RUN_PATH
}

function get_include_paths_temp {
    C_INCLUDE_PATH="$(cat /uny/paths/include-c-base):$(cat /uny/paths/include)"
    export C_INCLUDE_PATH
    CPLUS_INCLUDE_PATH="$(cat /uny/paths/include-cplus-base):$(cat /uny/paths/include)"
    export CPLUS_INCLUDE_PATH
}

function get_include_paths {
    C_INCLUDE_PATH="$(cat /uny/paths/include)"
    export C_INCLUDE_PATH
    CPLUS_INCLUDE_PATH="$(cat /uny/paths/include)"
    export CPLUS_INCLUDE_PATH
}

function dependencies_file_and_unset_vars {
    for o in /uny/pkg/"$pkgname"/"$pkgver"/{lib,bin,sbin}/*; do
        if [[ ! -L $o && -f $o ]]; then
            echo "Shared objects required by: $o"
            ldd "$o"
            ldd "$o" | grep -v "$pkgname/$pkgver" | sed "s|^.*ld-linux.*||" | grep -o "uny/pkg\(.*\)" | sed -e "s+uny/pkg/+unypkg/+" | grep -Eo "(unypkg/[a-z0-9]+/[0-9.]*)" | sort -u >>/uny/pkg/"$pkgname"/"$pkgver"/rdep
        fi
    done
    sort -u /uny/pkg/"$pkgname"/"$pkgver"/rdep -o /uny/pkg/"$pkgname"/"$pkgver"/rdep
    echo "Packages required by unypkg/$pkgname/$pkgver:"
    cat /uny/pkg/"$pkgname"/"$pkgver"/rdep

    unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_RUN_PATH LDFLAGS CFLAGS
}

function verbose_off_timing_end {
    shopt -u nocaseglob
    duration=$SECONDS
    echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."
    set +vx
    exec 2>&4 1>&3
}
EOF

# shellcheck source=/dev/null
source /uny/build/functions

######################################################################################################################
### Glibc

pkgname="glibc"

version_verbose_log_clean_unpack_cd

####################################################
### Start of individual build script

sed '/width -=/s/workend - string/number_length/' \
    -i stdio-common/vfprintf-process-arg.c

mkdir -v build
cd build || exit

echo "rootsbindir=/uny/pkg/$pkgname/$pkgver/sbin" >configparms

# Check how to automatically determin kernel version for this to automate future versions
../configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-werror \
    --enable-kernel=3.2 \
    --enable-stack-protector=strong \
    --with-headers=/usr/include \
    libc_cv_slibdir=/uny/pkg/"$pkgname"/"$pkgver"/lib

make -j"$(nproc)"
make -j"$(nproc)" check

# shellcheck disable=SC2016
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile

make install

cp -av /usr/lib/libstdc++.so* /uny/pkg/"$pkgname"/"$pkgver"/lib/
cp -av /usr/lib/libgcc_s.so* /uny/pkg/"$pkgname"/"$pkgver"/lib/

#sed "/RTLDLIST=/s@/usr@/uny/pkg/$pkgname/$pkgver@g" -i /uny/pkg/"$pkgname"/"$pkgver"/bin/ldd
sed '/RTLDLIST=/s@/lib64@/lib@g' -i /uny/pkg/"$pkgname"/"$pkgver"/bin/ldd

tee /uny/paths/pathenv <<'EOF'
PATH="$(cat /uny/paths/bin):$(cat /uny/paths/sbin):/usr/bin:/usr/sbin"
export PATH
EOF
add_to_paths_files

# ldconfig for dynamic runtime linker ld-linux.so
cat >/etc/ld.so.conf <<"EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf
EOF
mkdir -pv /etc/ld.so.conf.d
cat >/etc/ld.so.conf.d/"$pkgname"-"$pkgver".conf <<EOF
/uny/pkg/$pkgname/$pkgver/lib
EOF
ldconfig

cp -v ../nscd/nscd.conf /etc/nscd.conf
mkdir -pv /var/cache/nscd

mkdir -pv /uny/pkg/"$pkgname"/"$pkgver"/lib/locale

tee -a /uny/paths/pathenv <<EOF
LOCPATH="/uny/pkg/$pkgname/$pkgver/lib/locale"
export LOCPATH
I18NPATH="/uny/pkg/$pkgname/$pkgver/share/i18n"
export I18NPATH
EOF
source /uny/paths/pathenv

localedef -i POSIX -f UTF-8 C.UTF-8 2>/dev/null || true
localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
localedef -i de_DE -f ISO-8859-1 de_DE
localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i el_GR -f ISO-8859-7 el_GR
localedef -i en_GB -f ISO-8859-1 en_GB
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i en_HK -f ISO-8859-1 en_HK
localedef -i en_PH -f ISO-8859-1 en_PH
localedef -i en_US -f ISO-8859-1 en_US
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i es_ES -f ISO-8859-15 es_ES@euro
localedef -i es_MX -f ISO-8859-1 es_MX
localedef -i fa_IR -f UTF-8 fa_IR
localedef -i fr_FR -f ISO-8859-1 fr_FR
localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i is_IS -f ISO-8859-1 is_IS
localedef -i is_IS -f UTF-8 is_IS.UTF-8
localedef -i it_IT -f ISO-8859-1 it_IT
localedef -i it_IT -f ISO-8859-15 it_IT@euro
localedef -i it_IT -f UTF-8 it_IT.UTF-8
localedef -i ja_JP -f EUC-JP ja_JP
localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2>/dev/null || true
localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
localedef -i se_NO -f UTF-8 se_NO.UTF-8
localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
localedef -i zh_CN -f GB18030 zh_CN.GB18030
localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
localedef -i zh_TW -f UTF-8 zh_TW.UTF-8

cat >/etc/nsswitch.conf <<"EOF"
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF

tar -xf ../../tzdata2022g.tar.gz

ZONEINFO=/uny/pkg/$pkgname/$pkgver/share/zoneinfo
mkdir -pv "$ZONEINFO"/{posix,right}

for tz in etcetera southamerica northamerica europe africa antarctica \
    asia australasia backward; do
    zic -L /dev/null -d "$ZONEINFO" ${tz}
    zic -L /dev/null -d "$ZONEINFO"/posix ${tz}
    zic -L leapseconds -d "$ZONEINFO"/right ${tz}
done

cp -v zone.tab zone1970.tab iso3166.tab "$ZONEINFO"
zic -d "$ZONEINFO" -p America/New_York
unset ZONEINFO

ln -sfv /uny/pkg/"$pkgname"/"$pkgver"/share/zoneinfo/Europe/Berlin /etc/localtime

verbose_off_timing_end

######################################################################################################################
### Linux API Headers
pkgname="linux-api-headers"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

make mrproper
make headers

find usr/include -type f ! -name '*.h' -delete
mkdir -pv /uny/pkg/"$pkgname"/"$pkgver"
cp -rv usr/include /uny/pkg/"$pkgname"/"$pkgver"

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### zLib
pkgname="zlib"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

rm -fv /uny/pkg/"$pkgname"/"$pkgver"/lib/libz.a

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Bzip2
pkgname="bzip2"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

# shellcheck disable=SC2016
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile

make CFLAGS="$ldflags -fpic -fPIC -Wall -Winline -O2 -g -D_FILE_OFFSET_BITS=64" -f Makefile-libbz2_so
make clean

make CFLAGS="$ldflags -Wall -Winline -O2 -g -D_FILE_OFFSET_BITS=64" -j"$(nproc)"
make PREFIX=/uny/pkg/"$pkgname"/"$pkgver" install

cp -av libbz2.so.* /uny/pkg/"$pkgname"/"$pkgver"/lib
ln -sv libbz2.so.1.0.8 /uny/pkg/"$pkgname"/"$pkgver"/lib/libbz2.so

cp -v bzip2-shared /uny/pkg/"$pkgname"/"$pkgver"/bin/bzip2
for i in {bzcat,bunzip2}; do
    ln -sfv /uny/pkg/"$pkgname"/"$pkgver"/bin/bzip2 "$i"
done

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### XZ
pkgname="xz"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/xz

make -j"$(nproc)"
make check -j"$(nproc)"
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Zstd
pkgname="zstd"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

make prefix=/uny/pkg/"$pkgname"/"$pkgver" -j"$(nproc)"
make check -j"$(nproc)"
make prefix=/uny/pkg/"$pkgname"/"$pkgver" install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### File
pkgname="file"

version_verbose_log_clean_unpack_cd
get_env_var_values

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make check -j"$(nproc)"
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Ncurses
pkgname="ncurses"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --mandir=/usr/share/man \
    --with-shared \
    --without-debug \
    --without-normal \
    --with-cxx-shared \
    --enable-pc-files \
    --enable-widec \
    --with-pkg-config-libdir=/uny/pkg/"$pkgname"/"$pkgver"/lib/pkgconfig

make -j"$(nproc)"
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Readline
pkgname="readline"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

patch -Np1 -i ../readline-8.2-upstream_fix-1.patch

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --with-curses \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/readline

make SHLIB_LIBS="-lncursesw" -j"$(nproc)"
make SHLIB_LIBS="-lncursesw" install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### M4
pkgname="m4"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

#export CFLAGS="$ldflags"
make -j"$(nproc)"
make check -j"$(nproc)"
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Bc
pkgname="bc"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

CC=gcc ./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" -G -O3 -r

make -j"$(nproc)"
make test -j"$(nproc)"
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Flex
pkgname="flex"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/flex \
    --disable-static

make -j"$(nproc)"
make check -j"$(nproc)"
make install

ln -sv flex /uny/pkg/"$pkgname"/"$pkgver"/bin/lex

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Tcl
pkgname="tcl"
rm "$(echo /sources/$pkgname*html.tar*)"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

pkgshortver="$(echo "$pkgver" | sed -nre 's|^[^0-9]*(([0-9]+\.){1}[0-9]+).*|\1|p')"

SRCDIR=$(pwd)
cd unix || exit
./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --mandir=/uny/pkg/"$pkgname"/"$pkgver"/share/man

make -j"$(nproc)"

sed -e "s|$SRCDIR/unix|/uny/pkg/$pkgname/$pkgver/lib|" \
    -e "s|$SRCDIR|/uny/pkg/$pkgname/$pkgver/include|" \
    -i tclConfig.sh

tdbcver="$(echo pkgs/tdbc[0-9].* | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')"

sed -e "s|$SRCDIR/unix/pkgs/tdbc$tdbcver|/uny/pkg/$pkgname/$pkgver/lib/tdbc$tdbcver|" \
    -e "s|$SRCDIR/pkgs/tdbc$tdbcver/generic|/uny/pkg/$pkgname/$pkgver/include|" \
    -e "s|$SRCDIR/pkgs/tdbc$tdbcver/library|/uny/pkg/$pkgname/$pkgver/lib/tcl$pkgshortver|" \
    -e "s|$SRCDIR/pkgs/tdbc$tdbcver|/uny/pkg/$pkgname/$pkgver/include|" \
    -i pkgs/tdbc"$tdbcver"/tdbcConfig.sh

itclver="$(echo pkgs/itcl[0-9].* | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')"

sed -e "s|$SRCDIR/unix/pkgs/itcl$itclver|/uny/pkg/$pkgname/$pkgver/lib/itcl$itclver|" \
    -e "s|$SRCDIR/pkgs/itcl$itclver/generic|/uny/pkg/$pkgname/$pkgver/include|" \
    -e "s|$SRCDIR/pkgs/itcl$itclver|/uny/pkg/$pkgname/$pkgver/include|" \
    -i pkgs/itcl"$itclver"/itclConfig.sh

unset SRCDIR

make -j"$(nproc)" test
make install

chmod -v u+w /uny/pkg/"$pkgname"/"$pkgver"/lib/libtcl"$pkgshortver".so

make install-private-headers

ln -sfv tclsh"$pkgshortver" /uny/pkg/"$pkgname"/"$pkgver"/bin/tclsh

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Expect
pkgname="expect"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

tcldir=(/uny/pkg/tcl/*)
#tclver=$(basename "${tcldir[*]}")

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --with-tcl="${tcldir[*]}"/lib \
    --enable-shared \
    --mandir=/uny/pkg/"$pkgname"/"$pkgver"/share/man \
    --with-tclinclude="${tcldir[*]}"/include

make -j"$(nproc)"
make test -j"$(nproc)"
make install

ln -svf expect"$pkgver"/libexpect"$pkgver".so /uny/pkg/"$pkgname"/"$pkgver"/lib

tcldir1=(/uny/pkg/tcl/*/lib/tcl*.*)
tcldir2=(/uny/pkg/tcl/*/lib/tcl*)
ln -svf "${tcldir1[@]}" /uny/pkg/"$pkgname"/"$pkgver"/lib/
ln -svf "${tcldir2[@]}" /uny/pkg/"$pkgname"/"$pkgver"/lib/

mv -v /uny/pkg/tcl/*/bin/expect /uny/pkg/expect/*/bin/
#echo "unypkg/tcl/$tclver" >/uny/pkg/"$pkgname"/"$pkgver"/rdep

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### DejaGNU
pkgname="dejagnu"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

mkdir -v build
cd build || exit

../configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"
makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
makeinfo --plaintext -o doc/dejagnu.txt ../doc/dejagnu.texi

make -j"$(nproc)" install
install -v -dm755 /uny/pkg/"$pkgname"/"$pkgver"/share/doc/dejagnu
install -v -m644 doc/dejagnu.{html,txt} /uny/pkg/"$pkgname"/"$pkgver"/share/doc/dejagnu

make -j"$(nproc)" check

# manually add run dependencies
cat >/uny/pkg/"$pkgname"/"$pkgver"/rdep <<EOF
unypkg/tcl/$(echo /uny/pkg/tcl/* | grep -o "[.0-9]*")
unypkg/expect/$(echo /uny/pkg/expect/* | grep -o "[.0-9]*")
EOF

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Binutils
pkgname="binutils"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

libpath="$(cat /uny/paths/lib):/uny/pkg/$pkgname/$pkgver/lib:/uny/pkg/$pkgname/$pkgver/lib/gprofng"
LIBRARY_PATH="$libpath" # Used during linking
export LIBRARY_PATH
ldflags="-Wl,-rpath=$libpath -Wl,--dynamic-linker=$(grep -o "^.*glibc/[^:]*" /uny/paths/lib)/ld-linux-x86-64.so.2" # Used at runtime
export LDFLAGS="$ldflags"
unset LD_RUN_PATH

expect -c "spawn ls" || exit

mkdir -v build
cd build || exit

../configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --sysconfdir=/etc \
    --enable-gold \
    --enable-ld=default \
    --enable-plugins \
    --enable-shared \
    --disable-werror \
    --enable-64-bit-bfd \
    --with-system-zlib

make tooldir=/uny/pkg/"$pkgname"/"$pkgver" -j"$(nproc)" #-j"$(nproc)"
make -k -j"$(nproc)" check
make tooldir=/uny/pkg/"$pkgname"/"$pkgver" install

rm -fv /uny/pkg/"$pkgname"/"$pkgver"/lib/lib{bfd,ctf,ctf-nobfd,sframe,opcodes}.a
rm -fv /uny/pkg/"$pkgname"/"$pkgver"/share/man/man1/{gprofng,gp-*}.1

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### GMP
pkgname="gmp"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

cp -v configfsf.guess config.guess
cp -v configfsf.sub config.sub

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --enable-cxx \
    --disable-static \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/gmp

make -j"$(nproc)"
make html -j"$(nproc)"

make check 2>&1 | tee gmp-check-log -j"$(nproc)"
awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log

make install
make install-html

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### MPFR
pkgname="mpfr"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

sed -e 's/+01,234,567/+1,234,567 /' \
    -e 's/13.10Pd/13Pd/' \
    -i tests/tsprintf.c

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --enable-thread-safe \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/mpfr

make -j"$(nproc)"
make -j"$(nproc)" html
make -j"$(nproc)" check

make install
make install-html

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### MPC
pkgname="mpc"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/mpc

make -j"$(nproc)"
make -j"$(nproc)" html
make -j"$(nproc)" check

make install
make install-html

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Gettext
pkgname="gettext"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/gettext

make -j"$(nproc)"
make -j"$(nproc)" check

make install
chmod -v 0755 /uny/pkg/"$pkgname"/"$pkgver"/lib/preloadable_libintl.so

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Attr
pkgname="attr"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --sysconfdir=/etc \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/attr

make -j"$(nproc)"
make -j"$(nproc)" check

make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Acl
pkgname="acl"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/acl

make -j"$(nproc)"

make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Libcap
pkgname="libcap"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

sed -i '/install -m.*STA/d' libcap/Makefile

make prefix=/uny/pkg/"$pkgname"/"$pkgver" lib=lib -j"$(nproc)"
make -j"$(nproc)" test

make prefix=/uny/pkg/"$pkgname"/"$pkgver" lib=lib install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Shadow
pkgname="shadow"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

# shellcheck disable=2016
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \;

sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD SHA512:' \
    -e 's@#\(SHA_CRYPT_..._ROUNDS 5000\)@\100@' \
    -e 's:/var/spool/mail:/var/mail:' \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' \
    -i etc/login.defs

touch /usr/bin/passwd
./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --sysconfdir=/etc \
    --disable-static \
    --with-group-name-max-length=32

make -j"$(nproc)"

make exec_prefix=/uny/pkg/"$pkgname"/"$pkgver" install
make -C man install-man

add_to_paths_files

pwconv
grpconv
mkdir -p /etc/default
useradd -D --gid 999
sed -i '/MAIL/s/yes/no/' /etc/default/useradd
sed -i '/SHELL/s/\/bin\/bash/\/usr\/bin\/env bash/' /etc/default/useradd

####################################################
### End of individual build script

dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### GCC
pkgname="gcc"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

case $(uname -m) in
x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
    ;;
esac

# Change dynamic linker definition in source code
glibc_dir=(/uny/pkg/glibc/*/lib)
glibc_dir_fixed="${glibc_dir//\//\\\/}"
sed -e "s|lib64|lib|" -e "s|libx32|lib|" -e "/GLIBC_DYNAMIC_LINKER/s/\/lib/$glibc_dir_fixed/" -i gcc/config/i386/linux64.h gcc/config/i386/linux.h
cat gcc/config/i386/linux64.h gcc/config/i386/linux.h

mkdir -v build
cd build || exit

../configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    LD=ld \
    --enable-languages=c,c++ \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-multilib \
    --disable-bootstrap \
    --with-system-zlib \
    --with-slibdir="${glibc_dir[*]}"

make -j"$(nproc)"

ulimit -s 32768

chown -R tester .
su tester -c "PATH=$PATH make -k -j$(nproc) check"

chown -R root:root .
make install

ln -sv gcc /uny/pkg/"$pkgname"/"$pkgver"/bin/cc
ln -svr /uny/pkg/"$pkgname"/"$pkgver"/bin/cpp /uny/pkg/"$pkgname"/"$pkgver"/lib
ln -sfv /uny/pkg/"$pkgname"/"$pkgver"/libexec/gcc/"$(gcc -dumpmachine)"/"$pkgver"/liblto_plugin.so \
    /uny/pkg/binutils/*/lib/bfd-plugins/

cp -av /uny/pkg/"$pkgname"/"$pkgver"/lib/libstdc++.so* /uny/pkg/glibc/*/lib/
#cp -av /usr/lib/libgcc_s.so* /uny/pkg/glibc/*/lib/

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Link time library setup
ln -svf /etc/ld.so.conf /uny/pkg/glibc/*/etc/
for dir in /uny/pkg/*/*/lib; do
    cat >/etc/ld.so.conf.d/"$(echo "$dir.conf" | sed -e "s|/uny/pkg/||" -e "s|/lib||" -e "s|/|-|")" <<EOFDIR
$dir
EOFDIR
done
ldconfig -v

######################################################################################################################
### Pkg-config
pkgname="pkg-config"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --with-internal-glib \
    --disable-host-tool \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/pkg-config

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Sed
pkgname="sed"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" html

chown -R tester .
su tester -c "PATH=$PATH make -j$(nproc) check"

chown -R root:root .
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Bison
pkgname="bison"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/bison

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Grep
pkgname="grep"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

sed -i "s/echo/#echo/" src/egrep.sh

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Bash
pkgname="bash"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --without-bash-malloc \
    --with-installed-readline \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/bash

make -j"$(nproc)"

chown -R tester .
su -s expect tester <<EOF
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
EOF

chown -R root:root .
make install

ln -sv bash /uny/pkg/"$pkgname"/"$pkgver"/bin/sh

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

EOFUNY3

######################################################################################################################
######################################################################################################################
### Exit and reenter chroot to use new bash

cat <<EOF


######################################################################################################################
######################################################################################################################

Building the rest with the new bash being used

######################################################################################################################
######################################################################################################################


EOF

mountpoint -q $UNY/dev/shm && umount $UNY/dev/shm
umount $UNY/dev/pts
umount $UNY/{sys,proc,run,dev}

mount -v --bind /dev $UNY/dev
mount -v --bind /dev/pts $UNY/dev/pts
mount -vt proc proc $UNY/proc
mount -vt sysfs sysfs $UNY/sys
mount -vt tmpfs tmpfs $UNY/run

if [ -h $UNY/dev/shm ]; then
    mkdir -pv $UNY/"$(readlink $UNY/dev/shm)"
else
    mount -t tmpfs -o nosuid,nodev tmpfs $UNY/dev/shm
fi

######################################################################################################################
######################################################################################################################
### Link etc folder in and out of chroot
ln -sv /uny/etc/uny /etc/uny

UNY_PATH="$(cat /uny/uny/paths/bin):$(cat /uny/uny/paths/sbin):/usr/bin:/usr/sbin"
chroot "$UNY" /usr/bin/env -i \
    HOME=/uny/root \
    TERM="$TERM" \
    PS1='uny | \u:\w\$ ' \
    PATH="$UNY_PATH" \
    bash -x <<'EOFUNY4'
######################################################################################################################
### Libtool
pkgname="libtool"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" -k check
make install

rm -fv /uny/pkg/"$pkgname"/"$pkgver"/lib/libltdl.a

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Expat
pkgname="expat"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/"$pkgname"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Less
pkgname="less"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" --sysconfdir=/etc

make -j"$(nproc)"

make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Perl
pkgname="perl"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

export BUILD_ZLIB=False
export BUILD_BZIP2=0

less_bin=(/uny/pkg/less/*/bin/less)

sh Configure -des \
    -Dprefix=/uny/pkg/"$pkgname"/"$pkgver" \
    -Dvendorprefix=/uny/pkg/"$pkgname"/"$pkgver" \
    -Dprivlib=/uny/pkg/"$pkgname"/"$pkgver"/lib/perl5/core_perl \
    -Darchlib=/uny/pkg/"$pkgname"/"$pkgver"/lib/perl5/core_perl \
    -Dsitelib=/uny/pkg/"$pkgname"/"$pkgver"/lib/perl5/site_perl \
    -Dsitearch=/uny/pkg/"$pkgname"/"$pkgver"/lib/perl5/site_perl \
    -Dvendorlib=/uny/pkg/"$pkgname"/"$pkgver"/lib/perl5/vendor_perl \
    -Dvendorarch=/uny/pkg/"$pkgname"/"$pkgver"/lib/perl5/vendor_perl \
    -Dman1dir=/uny/pkg/"$pkgname"/"$pkgver"/share/man/man1 \
    -Dman3dir=/uny/pkg/"$pkgname"/"$pkgver"/share/man/man3 \
    -Dpager="${less_bin[*]}" \
    -Duseshrplib \
    -Dusethreads

make -j"$(nproc)"
make -j"$(nproc)" test
make install

unset BUILD_ZLIB BUILD_BZIP2

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Autoconf
pkgname="autoconf"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

sed -e 's/SECONDS|/&SHLVL|/' \
    -e '/BASH_ARGV=/a\        /^SHLVL=/ d' \
    -i.orig tests/local.at

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Automake
pkgname="automake"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/automake

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Coreutils
pkgname="coreutils"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

patch -Np1 -i ../"$pkgname"-*.patch

autoreconf -fiv
FORCE_UNSAFE_CONFIGURE=1 ./configure \
    --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --enable-no-install-program=kill,uptime

make -j"$(nproc)"

make NON_ROOT_USERNAME=tester -j"$(nproc)" check-root
echo "dummy:x:102:tester" >>/etc/group
chown -R tester .
su tester -c "PATH=$PATH make RUN_EXPENSIVE_TESTS=yes check"
sed -i '/dummy/d' /etc/group

chown -R root .
make install

mkdir -pv /uny/pkg/"$pkgname"/"$pkgver"/sbin
mv -v /uny/pkg/"$pkgname"/"$pkgver"/bin/chroot /uny/pkg/"$pkgname"/"$pkgver"/sbin
mkdir -pv /uny/pkg/"$pkgname"/"$pkgver"/share/man/man8
mv -v /uny/pkg/"$pkgname"/"$pkgver"/share/man/man1/chroot.1 /uny/pkg/"$pkgname"/"$pkgver"/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' /uny/pkg/"$pkgname"/"$pkgver"/share/man/man8/chroot.8

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Diffutils
pkgname="diffutils"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Gawk
pkgname="gawk"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

sed -i 's/extras//' Makefile.in

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make LN='ln -f' install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Findutils
pkgname="findutils"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

case $(uname -m) in
i?86) TIME_T_32_BIT_OK=yes ./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" --localstatedir=/var/lib/locate ;;
x86_64) ./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" --localstatedir=/var/lib/locate ;;
esac

make -j"$(nproc)"

chown -R tester .
su tester -c "PATH=$PATH make -j$(nproc) check"

chown -R root .
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Gzip
pkgname="gzip"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Make
pkgname="make"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

sed -e '/ifdef SIGPIPE/,+2 d' \
    -e '/undef  FATAL_SIG/i FATAL_SIG (SIGPIPE);' \
    -i src/main.c

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Patch
pkgname="patch"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Tar
pkgname="tar"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

FORCE_UNSAFE_CONFIGURE=1 \
    ./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Texinfo
pkgname="texinfo"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"
make -j"$(nproc)" check
make install
make TEXMF=/uny/pkg/"$pkgname"/"$pkgver"/share/texmf install-tex

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Util-Linux
pkgname="util-linux"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure ADJTIME_PATH=/var/lib/hwclock/adjtime \
    --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-chfn-chsh \
    --disable-login \
    --disable-nologin \
    --disable-su \
    --disable-setpriv \
    --disable-runuser \
    --disable-pylibmount \
    --disable-static \
    --without-python \
    --without-systemd \
    --without-systemdsystemunitdir \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/util-linux

make -j"$(nproc)"

chown -R tester .
su tester -c "make -k -j$(nproc) check"

chown -R root:root .
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
### Python
pkgname="python"
rm "$(echo /sources/$pkgname*html.tar*)"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --enable-shared \
    --with-system-expat \
    --with-system-ffi \
    --enable-optimizations

make -j"$(nproc)"
#make -j"$(nproc)" test
make install

cat >/etc/pip.conf <<EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
verbose_off_timing_end

######################################################################################################################
######################################################################################################################
### System cleanup
# shellcheck disable=SC2114
rm -rf /{bin,sbin,lib,lib64,usr,media,mnt,opt,srv,boot}

### Setup skeleton again
mkdir -pv /usr/bin
ln -sv /usr/bin /bin
ln -sv /uny/pkg/coreutils/*/bin/env /usr/bin/env
tee /bin/bash <<'EOF'
#!/usr/bin/env bash 
exec bash "$@"
EOF
chmod +x /bin/bash
ln -sv bash /bin/sh 
EOFUNY4

######################################################################################################################
######################################################################################################################
### Exit chroot

mountpoint -q $UNY/dev/shm && umount $UNY/dev/shm
umount $UNY/dev/pts
umount $UNY/{sys,proc,run,dev}

######################################################################################################################
######################################################################################################################
### Testing if everything is found in /uny/pkg folders

cat <<EOF


######################################################################################################################
######################################################################################################################

Testing if everything is found in /uny/pkg folders

######################################################################################################################
######################################################################################################################


EOF

for bin in {/bin/*,/sbin/*}; do
    type "$(basename "$bin")" | grep -v "/uny"
done

######################################################################################################################
######################################################################################################################
### Cleaning and compressing final build system

cat <<EOF


######################################################################################################################
######################################################################################################################

Cleaning and compressing final build system

######################################################################################################################
######################################################################################################################


EOF

mkdir -pv /var/uny/build
mv -v /uny/sources /var/uny/sources
rm -rfv /uny/uny/include

cd $UNY || exit
XZ_OPT="--threads=0" tar -cJpf /var/unypkg-base-build-logs-"$uny_build_date_now".tar.xz uny/build/logs
mv -v /uny/uny/build/logs /var/uny/build/logs

XZ_OPT="--threads=0" tar --exclude='./tmp' -cJpf /var/unypkg-base-"$uny_build_date_now".tar.xz .

gh -R unypkg/base release create "$uny_build_date_now" --generate-notes \
    /var/unypkg-base-build-logs-"$uny_build_date_now".tar.xz /var/unypkg-base-"$uny_build_date_now".tar.xz

######################################################################################################################
######################################################################################################################
### Packaging individual ones

cd $UNY/pkg || exit
for pkg in /var/uny/sources/vdet-*-new; do
    vdet_content="$(cat "$pkg")"
    vdet_new_file="$pkg"
    pkg="$(echo "$pkg" | grep -Eo "[^\-]*-new$" | sed "s|-new||")"
    pkgv="$(echo "$vdet_content" | cut -d" " -f1)"

    cp "$vdet_new_file" "$pkg"/"$pkgv"/vdet
    cp -a /var/uny/sources/"$pkg"-"$pkgv".tar.xz "$pkg"-"$pkgv"-source.tar.xz
    cp -a /var/uny/build/logs/"$pkg"-*.log "$pkg"-build.log
    XZ_OPT="-9 --threads=0" tar -cJpf unypkg-"$pkg".tar.xz "$pkg"
    # To-do: Also upload source with next command
    gh -R unypkg/"$pkg" release create "$pkgv"-"$uny_build_date_now" --generate-notes \
        "$pkg/$pkgv/vdet#vdet - $vdet_content" unypkg-"$pkg".tar.xz "$pkg"-build.log "$pkg"-"$pkgv"-source.tar.xz
done
