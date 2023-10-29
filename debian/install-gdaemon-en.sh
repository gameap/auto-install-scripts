#!/usr/bin/env bash

set -u
shopt -s dotglob

[[ "${DEBUG:-}" == 'true' ]] && set -x
export DEBIAN_FRONTEND="noninteractive"

_parse_options ()
{
    for i in "$@"
    do
        case $i in
            -h|--help)
                show_help
                exit 0
            ;;
        esac
    done
}

_check_env_variables()
{
    if [[ -z ${CREATE_TOKEN:-} ]]; then
        if [[ -z ${createToken:-} ]]; then
            echo "Empty create token" >> /dev/stderr
            exit 1
        fi

        CREATE_TOKEN=${createToken}
    fi

    if [[ -z ${PANEL_HOST:-} ]]; then
        if [[ -z ${panelHost:-} ]]; then
            echo "Empty panel host" >> /dev/stderr
            exit 1
        fi

        PANEL_HOST=${panelHost}
    fi
}

show_help ()
{
    echo
    echo "GameAP Daemon auto installator"
}

update_packages_list ()
{
    echo
    echo -n "Running apt-get update... "

    if ! apt-get update &> /dev/null; then
        echo "Unable to update apt" >> /dev/stderr
        exit 1
    fi

    echo "done."
    echo
}

install_packages ()
{
    packages=("$@")

    echo
    echo -n "Installing ${packages[*]}... "

    # nolint
    if ! apt-get install -y ${packages[*]} &> /dev/null; then
        echo "Unable to install ${packages[*]}." >> /dev/stderr
        echo "Package installation aborted." >> /dev/stderr
        exit 1
    fi

    echo "done."
    echo
}

add_gpg_key ()
{
    gpg_key_url=$1
    if ! curl -SfL "${gpg_key_url}" 2> /dev/null | apt-key add - &>/dev/null; then
      echo "Unable to add GPG key!" >> /dev/stderr
      exit 1
    fi
}

unknown_os ()
{
    echo "Unfortunately, your operating system distribution and version are not supported by this script."
    exit 1
}

detect_os ()
{
    os=""
    dist=""

    if [[ -e /etc/lsb-release ]]; then
        . /etc/lsb-release

        if [[ "${ID:-}" = "raspbian" ]]; then
            os=${ID}
            dist=$(cut --delimiter='.' -f1 /etc/debian_version)
        else
            os=${DISTRIB_ID}
            dist=${DISTRIB_CODENAME}

            if [ -z "$dist" ]; then
                dist=${DISTRIB_RELEASE}
            fi
        fi
    elif [[ -e /etc/os-release ]]; then
        . /etc/os-release

        os="${ID:-}"

        if [[ -n "${VERSION_CODENAME:-}" ]]; then
            dist=${VERSION_CODENAME:-}
        elif [[ -n "${VERSION_ID:-}" ]]; then
            dist=${VERSION_ID:-}
        fi

    elif [[ -n "$(command -v lsb_release > /dev/null 2>&1)" ]]; then
        dist=$(lsb_release -c | cut -f2)
        os=$(lsb_release -i | cut -f2 | awk '{ print tolower($1) }')
    fi

    if [[ -z "$dist" ]] && [[ -e /etc/debian_version ]]; then
        os=$(cat /etc/issue | head -1 | awk '{ print tolower($1) }')
        if grep -q '/' /etc/debian_version; then
            dist=$(cut --delimiter='/' -f1 /etc/debian_version)
        else
            dist=$(cut --delimiter='.' -f1 /etc/debian_version)
        fi
    fi

    if [[ -z "$dist" ]]; then
        unknown_os
    fi

    if [[ "${os}" = "debian" ]]; then
        case $dist in
            6* ) dist="squeeze" ;;
            7* ) dist="wheezy" ;;
            8* ) dist="jessie" ;;
            9* ) dist="stretch" ;;
            10* ) dist="buster" ;;
            11* ) dist="bullseye" ;;
            12* ) dist="bookworm" ;;
        esac
    fi

    # remove whitespace from OS and dist name
    os="${os// /}"
    dist="${dist// /}"

    # lowercase
    os=${os,,}
    dist=${dist,,}

    echo "Detected operating system as $os/$dist."
}

cpuarch=""

_detect_arch ()
{
    local architecture
    architecture=$(uname -m)
    if [[ "$architecture" == x86_64* ]]; then
        cpuarch="amd64"
    elif [[ "$architecture" == i*86 ]]; then
        cpuarch="386"
    elif  [[ "$architecture" == arm64 ]]; then
        cpuarch="arm64"
    elif  [[ "$architecture" == arm ]]; then
        cpuarch="arm"
    fi

    if [[ -z "$cpuarch" ]]; then
        _unknown_arch
    fi
}

_unknown_arch ()
{
    echo "Unfortunately, your architecture are not supported by this script."
    exit 2
}

gpg_check ()
{
    echo
    echo "Checking for gpg..."
    if command -v gpg > /dev/null; then
        echo "Detected gpg..."
    else
        echo "Installing gnupg for GPG verification..."
        if ! install_packages gnupg; then
            echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work." >> /dev/stderr
            echo "Repository installation aborted." >> /dev/stderr
            exit 1
        fi
    fi
}

curl_check ()
{
    echo
    echo "Checking for curl..."

    if command -v curl > /dev/null; then
        echo "Detected curl..."
    else
        echo "Installing curl..."
        if ! install_packages curl; then
            echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work." >> /dev/stderr
            echo "Repository installation aborted." >> /dev/stderr
            exit 1
        fi
    fi
}

_main ()
{
    _check_env_variables

    detect_os

    update_packages_list

    curl_check
    gpg_check

    detect_arch

    script="https://github.com/gameap/gameapctl/releases/download/v0.2.1/gameapctl-v0.2.1-linux-${cpuarch}.tar.gz"

    echo "Preparation for installation..."
    curl_check

    if ! command -v gameapctl > /dev/null; then
      echo
      echo
      echo "Downloading gameapctl for your operating system..."
      curl -sL $script --output /tmp/gameapctl-v0.2.1-linux-${cpuarch}.tar.gz &> /dev/null

      echo
      echo
      echo "Unpacking archive..."
      tar -xvf /tmp/gameapctl-v0.2.1-linux-${cpuarch}.tar.gz -C /usr/local/bin

      chmod +x /usr/local/bin/gameapctl
    fi

    if ! command -v gameapctl > /dev/null; then
      PATH=$PATH:/usr/local/bin
    fi

    echo
    echo
    echo "gameapctl updating..."
    gameapctl self-update

    echo
    echo
    echo "Running installation..."
    gameap daemon install
}

parse_options "$@"
_main
