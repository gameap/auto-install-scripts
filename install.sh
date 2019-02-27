#!/bin/bash

language=$(echo $LANGUAGE | cut -d_ -f1)

detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    if [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      if [ "${ID}" = "raspbian" ]; then
        os=${ID}
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "$dist" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/debian_version ]; then
      os=`cat /etc/issue | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

      if [ "${os}" = "debian" ]; then
        case $dist in
            6* ) dist="squeeze" ;;
            7* ) dist="wheezy" ;;
            8* ) dist="jessie" ;;
            9* ) dist="stretch" ;;
            10* ) dist="buster" ;;
            11* ) dist="bullseye" ;;
        esac
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "$dist" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  # lowercase
  os=${os,,}
  dist=${dist,,}

  echo "Detected operating system as $os/$dist."
}

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

detect_os

if [ "${os}" = "debian" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/debian/install-en.sh"
elif [ "${os}" = "ubuntu" ]; then 
    script="https://raw.githubusercontent.com/gameap/auto-install-scripts/master/debian/install-en.sh"
elif [ "${os}" = "centos" ]; then 
    echo "Support CentOS is coming soon"
    echo "Your operating system not supported"
    exit 1
else
    echo "Your operating system not supported"
    exit 1
fi

echo "Preparation for installation..."
curl_check

echo
echo
echo "Downloading installator for your operating system..."
curl -sL $script --output /tmp/gameap-install.sh &> /dev/null
chmod +x /tmp/gameap-install.sh

echo
echo
echo "Running..."
echo
echo
bash /tmp/gameap-install.sh $@
rm /tmp/gameap-install.sh
