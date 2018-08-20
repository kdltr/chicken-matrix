#!/bin/sh

set -e

build_custom_dep() {
    echo "Building $1…"
    cd "$1";
    chicken-install
}

build_sudo_deps() {
    echo "WARNING"
    echo 'It seems you don’t have write access to the default CHICKEN prefix'
    echo 'Some dependencies need that, installing them with `sudo`.'
    echo 'If you don’t have `sudo` on your platform, you can chose which tool to use by setting the SUDO environment variable'
    chicken-install -s bind
    chicken-install -s utf8
}

cd "`dirname $0`"

# Little hack for extensions that install stuff outside of the repository
test -w "`chicken-install -repository`" || build_sudo_dep

. ./vars.sh

test -d .git && git submodule update --init

( build_custom_dep chicken-ncurses )
( build_custom_dep rest-bind )

chicken-install -n

echo "Ensemble has been bulit, yay! \o/"
echo 'Run it with `./run.sh`'
