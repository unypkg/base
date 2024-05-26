#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034

## This is the unypkg repo creation script
## Created by michacassola mich@casso.la
######################################################################################################################
######################################################################################################################
# Run as root on Ubuntu LTS

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

set -xv

######################################################################################################################
######################################################################################################################
### Installing the unypkg script
wget -qO- uny.nu/pkg | bash
### unypkg functions
source /uny/git/unypkg/fn

uny_auto_github_conf

pkgrepos=("yasm" "mariadb" "boost" "libaio" "xorg-libs")
for pkgrepo in "${pkgrepos[@]}"; do
    pkgname="$pkgrepo"
    check_for_repo_and_create
done
