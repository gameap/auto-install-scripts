#!/bin/bash

language=$(echo $LANGUAGE | cut -d_ -f1)
os=$(cat /etc/os-release | grep ID | cut -d= -f2 | head -1)

curl_check ()
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

if [ "${os}" = "debian" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/debian/install-en.sh"
elif [ "${os}" = "ubuntu" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/debian/install-en.sh"
elif [ "${os}" = "centos" ]; then 
    echo "Your operating system not supported"
    exit 1
fi

echo "Script $script"
echo "Preparation for installation..."
curl_check

echo "Running..."
echo
echo

curl -sL $script --output /tmp/gameap-install.sh &> /dev/null
chmod +x /tmp/gameap-install.sh
bash /tmp/gameap-install.sh $@
rm /tmp/gameap-install.sh