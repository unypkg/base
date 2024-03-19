#!/usr/bin/env bash
# shellcheck disable=SC1091

## This is the unypkg base system build script - stage 2
## Created by michacassola mich@casso.la
######################################################################################################################
######################################################################################################################
# Run as root on Ubuntu LTS

cat <<EOF


######################################################################################################################
######################################################################################################################

Stage 2 - Building the final system in the /uny chroot

######################################################################################################################
######################################################################################################################


EOF

if [[ $EUID -gt 0 ]]; then
    echo "Not root, exiting..."
    exit
fi

apt update && apt install -y gh git

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

### Setup Git and GitHub
# Setup Git User -
source "$UNY"/uny/build/github_conf

tee >"$UNY"/uny/build/fs_size_function <<'EOF'
function fs_size {
    # Filesystem space
    df -h
    # Complete root folders and complete size
    du -hsx --exclude=/{proc,sys,dev,run} /*
    du -hsx --exclude=/{proc,sys,dev,run} /{,*}
    du -hsx $UNY/sources
}
EOF
source "$UNY"/uny/build/fs_size_function

set -xv
fs_size

# Cleaning GitHub runner
rm -rf /usr/local/lib/android
rm -rf /usr/share/dotnet
rm -rf /var/lib/docker
fs_size

[ ! -e /etc/bash.bashrc ] || mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE

######################################################################################################################
######################################################################################################################
### Download stage 1

stage1_release_url="$(curl -Ls -o /dev/null -w "%{url_effective}" https://github.com/unypkg/stage1/releases/latest)"
stage1_download_url="$(echo "$stage1_release_url" | sed -e "s|/tag/|/download/|" -e "s|\([^/]*$\)|\1/\1.tar.xz|")"
# shellcheck disable=SC2001
stage1_filename="$(echo "$stage1_release_url" | sed -e "s|.*/\([^/]*$\)|\1.tar.xz|")"
uny_build_date_now="$(echo "$stage1_release_url" | sed -e "s|.*/\([^/]*$\)|\1|" -e "s|stage1-||")"

mkdir -v $UNY
cd $UNY || exit

fs_size
wget "$stage1_download_url"
tar xf "$stage1_filename"
rm "$stage1_filename"
fs_size

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
set -vx
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
    fs_size
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

function cleanup_verbose_off_timing_end {
    rm -rf /sources/"$pkgname"*"$pkgver"
    shopt -u nocaseglob
    duration=$SECONDS
    echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."
    fs_size
    set +vx
    exec 2>&4 1>&3
}
EOF

# shellcheck source=/dev/null
source /uny/build/functions

source /uny/build/fs_size_function

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
    --enable-kernel=5.15 \
    --enable-stack-protector=strong \
    --disable-nscd \
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

tar -xf ../../tzdata*.tar.gz

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

cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

######################################################################################################################
### Libxcrypt
pkgname="libxcrypt"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"\
    --enable-hashes=strong,glibc \
    --enable-obsolete-api=no \
    --disable-static \
    --disable-failure-tokens

make -j"$(nproc)"
make -j"$(nproc)" check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end

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
    --with-{b,yes}crypt \
    --without-libbsd \
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
cleanup_verbose_off_timing_end

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
    --disable-fixincludes \
    --with-system-zlib

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
cleanup_verbose_off_timing_end

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
### Pkgconf
pkgname="pkgconf"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --disable-static \
    --docdir=/uny/pkg/"$pkgname"/"$pkgver"/share/doc/pkgconf

make -j"$(nproc)"
make install

ln -sv pkgconf   /uny/pkg/"$pkgname"/"$pkgver"/bin/pkg-config
ln -sv pkgconf.1 /uny/pkg/"$pkgname"/"$pkgver"/share/man/man1/pkg-config.1

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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

tee /bin/bash <<'EOF'
#!/usr/bin/env bash 
exec bash "$@"
EOF
chmod +x /bin/bash
ln -sfv bash /bin/sh 

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end
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
set -vx
# shellcheck source=/dev/null
source /uny/build/functions

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
    -Dpager="${less_bin[*]} -isR" \
    -Duseshrplib \
    -Dusethreads

make -j"$(nproc)"
TEST_JOBS=$(nproc) make test_harness
make install

unset BUILD_ZLIB BUILD_BZIP2

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end

######################################################################################################################
### Autoconf
pkgname="autoconf"

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
cleanup_verbose_off_timing_end

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
make -j$(($(nproc)>4?$(nproc):4)) check
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end

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
groupadd -g 102 dummy -U tester
chown -R tester .
su tester -c "PATH=$PATH make RUN_EXPENSIVE_TESTS=yes check"
groupdel dummy

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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

chown -R tester .
su tester -c "PATH=$PATH make check"

rm -f /usr/bin/gawk-5.3.0
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end

######################################################################################################################
### Findutils
pkgname="findutils"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver" --localstatedir=/var/lib/locate

make -j"$(nproc)"

chown -R tester .
su tester -c "PATH=$PATH make -j$(nproc) check"

chown -R root .
make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

######################################################################################################################
### Make
pkgname="make"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

./configure --prefix=/uny/pkg/"$pkgname"/"$pkgver"

make -j"$(nproc)"

chown -R tester .
su tester -c "PATH=$PATH make check"

make install

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

######################################################################################################################
### Util-Linux
pkgname="util-linux"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

unset LD_RUN_PATH

sed -i '/test_mkfds/s/^/#/' tests/helpers/Makemodule.am

./configure ADJTIME_PATH=/var/lib/hwclock/adjtime \
    --prefix=/uny/pkg/"$pkgname"/"$pkgver" \
    --runstatedir=/run \
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
cleanup_verbose_off_timing_end

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
cleanup_verbose_off_timing_end

######################################################################################################################
######################################################################################################################
### System cleanup

### Testing if everything is found in /uny/pkg that is in /usr/bin
echo "Testing if everything is found in /uny/pkg that is in /usr/bin"
for bin in {/bin/*,/sbin/*}; do
    type "$(basename "$bin")" | grep -v "/uny"
done

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
ln -sfv bash /bin/sh 
EOFUNY4

######################################################################################################################
######################################################################################################################
### Exit chroot

mountpoint -q $UNY/dev/shm && umount $UNY/dev/shm
umount $UNY/dev/pts
umount $UNY/{sys,proc,run,dev}

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

set -vx

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
    pkg="$(echo "$pkg" | grep -Eo "vdet.*new$" | sed -e "s|vdet-||" -e "s|-new||")"
    pkgv="$(echo "$vdet_content" | head -n 1)"

    cp "$vdet_new_file" "$pkg"/"$pkgv"/vdet

    source_archive_orig="$(echo /var/uny/sources/"$pkg"-"$pkgv".tar.*)"
    source_archive_new="$(echo "$source_archive_orig" | sed -r -e "s|^.*/||" -e "s|(\.tar.*$)|-source\1|")"
    cp -a "$source_archive_orig" "$source_archive_new"
    cp -a /var/uny/build/logs/"$pkg"-*.log "$pkg"-build.log
    XZ_OPT="-9 --threads=0" tar -cJpf unypkg-"$pkg".tar.xz "$pkg"
    # To-do: Also upload source with next command
    gh -R unypkg/"$pkg" release create "$pkgv"-"$uny_build_date_now" --generate-notes \
        "$pkg/$pkgv/vdet#vdet - $vdet_content" unypkg-"$pkg".tar.xz "$pkg"-build.log "$source_archive_new"
done
