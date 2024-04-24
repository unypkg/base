#!/usr/bin/env bash
# shellcheck disable=SC1091

## This is the unypkg base system build script - stage 1
## Created by michacassola mich@casso.la
######################################################################################################################
######################################################################################################################
# Run as root on Ubuntu LTS

cat <<EOF


######################################################################################################################
######################################################################################################################

Stage 1 - Setting up the build system

######################################################################################################################
######################################################################################################################


EOF

if [[ $EUID -gt 0 ]]; then
    echo "Not root, exiting..."
    exit
fi

apt update && apt install -y gcc g++ gperf bison flex texinfo help2man make libncurses5-dev \
    python3-dev autoconf automake libtool libtool-bin gawk curl bzip2 xz-utils unzip zstd \
    patch libstdc++6 rsync gh git meson ninja-build gettext autopoint libsigsegv-dev pkgconf

### Getting Variables from files
UNY_AUTO_PAT="$(cat UNY_AUTO_PAT)"
export UNY_AUTO_PAT
GH_TOKEN="$(cat GH_TOKEN)"
export GH_TOKEN

### Setup the Shell
ln -fs /bin/bash /bin/sh

export UNY=/uny
tee >/root/.bash_profile <<EOF
export UNY=/uny
PS1='\u:\w\$ '
#if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    #if [ -f "$HOME/.bashrc" ]; then
    #    . "$HOME/.bashrc"
    #fi
#fi
EOF
# shellcheck source=/dev/null
source /root/.bash_profile

### Add uny user
groupadd uny
useradd -s /bin/bash -g uny -m -k /dev/null uny

### Create uny chroot skeleton
mkdir -pv "$UNY"/home
mkdir -pv "$UNY"/sources/unygit
chmod -v a+wt "$UNY"/sources

mkdir -pv "$UNY"/{etc,var} "$UNY"/usr/{bin,lib,sbin}
mkdir -pv "$UNY"/uny/build/logs

### Setup Git and GitHub in GitHub Actions
cat >"$UNY"/uny/build/github_conf <<"GITEOF"
#!/usr/bin/env bash

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
GITEOF
source "$UNY"/uny/build/github_conf

set -xv

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

cat >"$UNY"/uny/build/download_functions <<"EOF"
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

function check_if_newer_version {
    # Download last vdet file
    curl -LO https://github.com/unypkg/"$pkgname"/releases/latest/download/vdet
    old_commit_id="$(sed '2q;d' vdet)"
    uny_build_date_seconds_old="$(sed '4q;d' vdet)"
    [[ $latest_commit_id == "" ]] && latest_commit_id="$latest_ver"

    # pkg will be built, if commit id is different and newer.
    # Before a pkg is built the existence of a build-"$pkgname" file is checked
    if [[ "$latest_commit_id" != "$old_commit_id" && "$uny_build_date_seconds_now" -gt "$uny_build_date_seconds_old" ]]; then
        echo "newer" >release-"$pkgname"
    fi
}

function version_details {
    {
        echo "$latest_ver"
        echo "$latest_commit_id"
        echo "$uny_build_date_now"
        echo "$uny_build_date_seconds_now"
    } >vdet-"$pkgname"
    check_if_newer_version
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
EOF

source "$UNY"/uny/build/download_functions

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

newesttimedatafile="$(curl https://data.iana.org/time-zones/releases/ | grep -Eo "\"tzdata[0-9]+[a-z]+.tar.gz\"" | sed 's|"||g' | sort --version-sort | tail -n 1)"
wget https://data.iana.org/time-zones/releases/"$newesttimedatafile"

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
pkggit="https://gcc.gnu.org/git/gcc.git refs/tags/releases/gcc*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | tail --lines=1)"
# shellcheck disable=SC2086
#latest_ver="$(git ls-remote --refs --sort="v:refname" $pkggit | grep -oE "gcc-[^0-9]*(([0-9]+\.)*[0-9]+)" | sed "s|gcc-||" | sort -n | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=4 | sed "s|gcc-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
######################################################################################################################
### Exit if Glibc, Binutils or GCC are not newer
#if [[ -f vdet-glibc-new || -f vdet-binutils-new || -f vdet-gcc-new ]]; then
#    echo "Continuing"
#else
#    echo "No new version of Glibc, Binutils or GCC found, exiting..."
#    exit
#fi

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

# shellcheck disable=SC2086,SC2154
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
pkggit="https://git.tukaani.org/xz.git refs/tags/v5.2.7"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create
git_clone_source_repo

cd "$pkg_git_repo_dir" || exit
./autogen.sh
cd /uny/sources || exit

version_details
archiving_source

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

# shellcheck disable=SC2086
versubnums="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]([.0-9]+)+$" | tail -n 20 | grep -Eo "[^v0-9][.0-9]+\." | sed "s|\.||g" | sort -u)"
versubnum_even="$(for i in $versubnums; do if [[ $((i % 2)) -eq 0 ]]; then echo "$i"; fi; done)"
versubnum_even_latest="$(echo "$versubnum_even" | tail -n 1)"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" https://github.com/Perl/perl5.git refs/tags/v[0-9]."$versubnum_even_latest".* | tail -n 1)"
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

check_for_repo_and_create

wget https://github.com/westes/flex/releases/download/v"$latest_ver"/flex-"$latest_ver".tar.gz

version_details

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
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "libcap-[0-9]\.[0-9]+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|libcap-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

repo_clone_version_archive

######################################################################################################################
### Libxcrypt
pkgname="libxcrypt"
pkggit="https://github.com/besser82/libxcrypt.git refs/tags/v*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "[0-9]\.([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://github.com/besser82/libxcrypt/releases/download/v"$latest_ver"/libxcrypt-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Shadow
pkgname="shadow"
pkggit="https://github.com/shadow-maint/shadow.git refs/tags/[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "[0-9]\.([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3)"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create

wget https://github.com/shadow-maint/shadow/releases/download/"$latest_ver"/shadow-"$latest_ver".tar.xz

version_details

######################################################################################################################
### Pkg-config
pkgname="pkgconf"
pkggit="https://github.com/pkgconf/pkgconf refs/tags/pkgconf-[0-9.]*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "pkgconf-[0-9]([.0-9]+)+$" | tail -n 1)"
latest_ver="$(echo "$latest_head" | cut --delimiter='/' --fields=3 | sed "s|pkgconf-||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

check_for_repo_and_create
git_clone_source_repo

cd "$pkg_git_repo_dir" || exit
autoreconf -i
cd /uny/sources || exit

version_details
archiving_source

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

check_for_repo_and_create
git_clone_source_repo

cd "$pkg_git_repo_dir" || exit
mv expat ../expat
cd /uny/sources || exit
rm -r "$pkg_git_repo_dir"
cd expat || exit
./buildconf.sh
cd /uny/sources || exit
pkg_git_repo_dir=expat

version_details
archiving_source

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

check_for_repo_and_create
git_clone_source_repo

cd "$pkg_git_repo_dir" || exit
make -f Makefile.aut distfiles
cd /uny/sources || exit

version_details
archiving_source

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
# shellcheck disable=SC2034
pkgname="automake"
pkggit="https://git.savannah.gnu.org/git/automake.git refs/tags/v[0-9.]*"
# shellcheck disable=SC2034
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

cat >/uny/uny/build/stage_functions <<"EOF"
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
source "$UNY"/uny/build/stage_functions
EOF
EOFUNY

sudo -i -u uny bash <<"EOFUNY"
set -vx
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
    --enable-kernel=5.15 \
    --with-headers="$UNY"/usr/include \
    --disable-nscd \
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

gccver="$(echo /uny/sources/gcc-* | grep -Eo "[0-9]+(\.[0-9]+)*" | sort -u)"

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
    --enable-no-install-program=kill,uptime \
    gl_cv_macro_MB_CUR_MAX_good=y

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

./configure --prefix=/usr \
    --host="$UNY_TGT" \
    --build=$(./build-aux/config.guess)

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
    --host="$UNY_TGT" \
    --build=$(./build-aux/config.guess)

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

#sed -e '/ifdef SIGPIPE/,+2 d' \
#    -e '/undef  FATAL_SIG/i FATAL_SIG (SIGPIPE);' \
#    -i src/main.c

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

./configure --prefix=/usr   \
    --host=$UNY_TGT \
    --build=$(./build-aux/config.guess)

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

sed '6009s/$add_dir//' -i ltmain.sh

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
tar -xf ../mpc-*.tar.xz
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
    --disable-libsanitizer \
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
set -vx
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
set -vx

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
source /uny/build/stage_functions

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
    -Duseshrplib \
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

pkgname="python"

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
XZ_OPT="-0 --threads=0" tar -cJpf /home/stage1-"$uny_build_date_now".tar.xz .
gh -R unypkg/stage1 release create stage1-"$uny_build_date_now" --generate-notes \
    /home/stage1-"$uny_build_date_now".tar.xz
