#!/bin/bash

set -e

_detect_os ()
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

    if [[ -z "$dist" ]]; then
        _unknown_os
    fi

    # remove whitespace from OS and dist name
    os="${os// /}"
    dist="${dist// /}"

    # lowercase
    os=${os,,}
    dist=${dist,,}

    echo "Detected operating system as $os/$dist."
}

_unknown_os ()
{
    echo "Unfortunately, your operating system distribution and version are not supported by this script."
    exit 2
}

_curl_check ()
{
  echo "Checking for curl..."
  if command -v curl > /dev/null; then
    echo "Detected curl..."
  else
    echo "Installing curl..."

    if [ "${os}" = "debian" ]; then
        apt-get -y update &> /dev/null
        apt-get -q -y install curl &> /dev/null
    elif [ "${os}" = "ubuntu" ]; then
        apt-get -y update &> /dev/null
        apt-get install -q -y curl &> /dev/null
    elif [ "${os}" = "centos" ]; then
        yum -q -y update &> /dev/null
        yum -q -y install curl &> /dev/null
    fi

    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work." >> /dev/stderr
      echo "Repository installation aborted." >> /dev/stderr
      exit 1
    fi
  fi
}

_tar_check ()
{
  echo "Checking for tar..."
  if command -v tar > /dev/null; then
    echo "Detected tar..."
  else
    echo "Installing tar..."

    if [ "${os}" = "debian" ]; then
        apt-get -y update &> /dev/null
        apt-get -q -y install tar &> /dev/null
    elif [ "${os}" = "ubuntu" ]; then
        apt-get -y update &> /dev/null
        apt-get install -q -y tar &> /dev/null
    elif [ "${os}" = "centos" ]; then
        yum -q -y update &> /dev/null
        yum -q -y install tar &> /dev/null
    fi

    if [ "$?" -ne "0" ]; then
      echo "Unable to install tar! Your base system has a problem; please check your default OS's package repositories because tar should work." >> /dev/stderr
      echo "Repository installation aborted." >> /dev/stderr
      exit 1
    fi
  fi
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
    elif  [[ "$architecture" == aarch64 ]]; then
        cpuarch="arm64"
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

_detect_os
_detect_arch

gameapctl_version="0.6.0"
gameapctl_url="https://github.com/gameap/gameapctl/releases/download/v${gameapctl_version}/gameapctl-v${gameapctl_version}-linux-${cpuarch}.tar.gz"

echo "Preparation for installation..."
_curl_check
_tar_check

if ! command -v gameapctl > /dev/null; then
  echo
  echo
  echo "Downloading gameapctl for your operating system..."
  curl -sL ${gameapctl_url} --output /tmp/gameapctl-v${gameapctl_version}-linux-${cpuarch}.tar.gz &> /dev/null

  echo
  echo
  echo "Unpacking archive..."
  tar -xvf /tmp/gameapctl-v${gameapctl_version}-linux-${cpuarch}.tar.gz -C /usr/local/bin

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
bash -c "gameapctl panel install $*"
