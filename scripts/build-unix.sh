#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to build the zen-browser codebase. It should be run from within the cloned git repository of the zen browser

type command_exists &> /dev/null 2>&1 || source "${HOME}/.shellrc"

! command_exists hg && error "mercurial is not installed! Please install and set it in the PATH env var before proceeding"
! command_exists gtar && error "gtar is not installed! Please install and set it in the PATH env var before proceeding"

sudo rm -rf engine

git submodule update --init --recursive --remote --rebase --force

# Change the repository in 'configs/common/mozconfig' to mine
# 'github.com/zen-browser/desktop' --> 'github.com/vraravam/zen-browser-desktop'
sed -i '' -e 's/github.com\/zen-browser\/desktop/github.com\/vraravam\/zen\-browser\-desktop/' configs/common/mozconfig

npm i
npm run init
npm run bootstrap

sh ./scripts/update-en-US-packs.sh
npm run build
npm start
