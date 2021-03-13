#!/usr/bin/env bash

set -u
set -e
shopt -s dotglob

export DAEMON_SETUP_TOKEN=test_auto_setup_token

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
    elif [[ -f /etc/system-release-cpe ]]; then
        os=$(cut --delimiter=":" -f 3 /etc/system-release-cpe)
        dist=$(cut --delimiter=":" -f 5 /etc/system-release-cpe)
    elif [[ -n "$(command -v lsb_release 2>/dev/null)" ]]; then
        dist=$(lsb_release -c | cut -f2)
        os=$(lsb_release -i | cut -f2 | awk '{ print tolower($1) }')

    elif [[ -e /etc/debian_version ]]; then
        os=$(cat /etc/issue | head -1 | awk '{ print tolower($1) }')
        if grep -q '/' /etc/debian_version; then
            dist=$(cut --delimiter='/' -f1 /etc/debian_version)
        else
            dist=$(cut --delimiter='.' -f1 /etc/debian_version)
        fi
    else
        unknown_os
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
        esac
    fi

    # remove whitespace from OS and dist name
    os="${os// /}"
    dist="${dist// /}"

    # lowercase
    os=${os,,}
    dist=${dist,,}
}

echo
echo "Start building"
echo "Web-server: ${WEB_SERVER}"
echo "Database: ${DATABASE}"
echo

detect_os

echo "127.0.0.1 test.gameap" > /etc/hosts

if [[ ${os} == "debian" ]] || [[ ${os} == "ubuntu" ]]; then
    ./debian/install-en.sh --github --path=/var/www/gameap --host=test.gameap --web-server=${WEB_SERVER} --database=${DATABASE}
elif [[ ${os} == "centos" ]]; then
    ./centos/install-en.sh --github --path=/var/www/gameap --host=test.gameap --web-server=${WEB_SERVER} --database=${DATABASE}
else
    echo "Unknown OS" >> /dev/stderr
    exit 1
fi

echo
echo "Checking available gameap host"
echo
curl -sL -w "HTTP CODE: %{http_code}\\n" "http://test.gameap/login" -o /dev/null

echo
echo "Checking GameAP Daemon installation"

if [[ ${os} == "debian" ]] || [[ ${os} == "ubuntu" ]]; then
    daemon_install_command="./debian/install-gdaemon-en.sh"
elif [[ ${os} == "centos" ]]; then
    daemon_install_command="./centos/install-gdaemon-en.sh"
else
    echo "Unknown os"
    exit 1
fi

if ! echo "Illuminate\Support\Facades\Cache::put('gdaemonAutoCreateToken', 'test_auto_setup_token', 99999);" | /var/www/gameap/artisan tinker; then
    echo "Failed to set auto setup token"
    ./artisan --version
    exit 1
fi

export createToken=test_auto_setup_token
export panelHost=http://test.gameap;

export CREATE_TOKEN=test_auto_setup_token
export PANEL_HOST=http://test.gameap;

if ! ${daemon_install_command}; then
    echo "Unable to install gameap-daemon"

    if [[ -f /tmp/gameap-response-create-ds.log ]]; then
        echo
        echo "Showing gameap create ds respoonse log:"
        echo
        cat /tmp/gameap-response-create-ds.log
        echo
    fi

    exit 1
fi
