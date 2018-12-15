#!/bin/bash

language=$(echo $LANGUAGE | cut -d_ -f1)

os=$(cat /etc/os-release | grep ID | cut -d= -f2 | head -1)

if [ "${os}" = "debian" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/${os}/install-en.sh"
elif [ "${os}" = "ubuntu" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/${os}/install-en.sh"
elif [ "${os}" = "centos" ]; then 
    echo "Your operating system not supported"
    exit 1
fi

curl -sL $script | bash - $@