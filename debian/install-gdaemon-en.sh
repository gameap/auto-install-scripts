#!/bin/bash

shopt -s dotglob
export DEBIAN_FRONTEND="noninteractive"

parse_options ()
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

show_help ()
{
    echo
    echo "GameAP Daemon auto installator"
}

update_packages_list ()
{
    echo -n "Running apt-get update... "
    apt-get update &> /dev/null

    if [ "$?" -ne "0" ]; then
        echo "Unable to update apt" >> /dev/stderr
        exit 1
    fi

    echo "done."
}

install_packages ()
{
    packages=$@

    echo -n "Installing ${packages}... "
    apt-get install -y $packages &> /dev/null

    if [ "$?" -ne "0" ]; then
        echo "Unable to install ${packages}." >> /dev/stderr
        echo "Package installation aborted." >> /dev/stderr
        exit 1
    fi
    echo "done."
}

add_gpg_key ()
{
    gpg_key_url=$1
    curl -SfL "${gpg_key_url}" 2> /dev/null | apt-key add - &>/dev/null

    if [ "$?" -ne "0" ]; then
      echo "Unable to add GPG key!" >> /dev/stderr
      exit 1
    fi
}

unknown_os ()
{
  echo "Unfortunately, your operating system distribution and version are not supported by this script."
}

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

gpg_check ()
{
  echo "Checking for gpg..."
  if command -v gpg > /dev/null; then
    echo "Detected gpg..."
  else
    echo "Installing gnupg for GPG verification..."
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work." >> /dev/stderr
      echo "Repository installation aborted." >> /dev/stderr
      exit 1
    fi
  fi
}

curl_check ()
{
  echo "Checking for curl..."
  if command -v curl > /dev/null; then
    echo "Detected curl..."
  else
    echo "Installing curl..."
    apt-get install -q -y curl
    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work." >> /dev/stderr
      echo "Repository installation aborted." >> /dev/stderr
      exit 1
    fi
  fi
}

generate_certs ()
{
    mkdir -p /etc/gameap-daemon/certs
    cd /etc/gameap-daemon/certs

    echo
    echo "Generating Root certificates..."
    echo

    if [ -f "rootca.key" ]; then
        echo "Root certificate exists. Skipping..."
    else
        openssl genrsa -out rootca.key 2048
        if [ "$?" -ne "0" ]; then
            echo "Unable to generate rootca key" >> /dev/stderr
            exit 1
        fi

        openssl req -x509 -new -nodes -key rootca.key -days 3650 -subj '/O=GameAP Daemon Root' -out rootca.crt
        if [ "$?" -ne "0" ]; then
            echo "Unable to generate rootca certificate" >> /dev/stderr
            exit 1
        fi
    fi

    echo
    echo "Generating GameAP Daemon server certificates..."
    echo

    if [ -f "server.key" ]; then
        echo "Server certificate exists. Skipping..."
    else
        openssl genrsa -out server.key 2048
        if [ "$?" -ne "0" ]; then
            echo "Unable to generate server key" >> /dev/stderr
            exit 1
        fi

        openssl req -new -key server.key -subj '/O=GameAP Daemon' -out server.csr
        if [ "$?" -ne "0" ]; then
            echo "Unable to generate server certificate" >> /dev/stderr
            exit 1
        fi

        openssl x509 -req -in server.csr -CA rootca.crt -CAkey rootca.key -CAcreateserial -out server.crt -days 3650
        if [ "$?" -ne "0" ]; then
            echo "Unable to sign server certificate" >> /dev/stderr
            exit 1
        fi
    fi

    # echo
    # echo "Generating GameAP client certificates..."
    # echo
    #
    # openssl genrsa -out client.key 2048
    # if [ "$?" -ne "0" ]; then
    #     echo "Unable to generate client key" >> /dev/stderr
    #     exit 1
    # fi
    #
    # openssl req -new -key client.key -subj '/O=GameAP Daemon Client' -out client.csr
    # if [ "$?" -ne "0" ]; then
    #     echo "Unable to generate client certificate" >> /dev/stderr
    #     exit 1
    # fi

    # openssl x509 -req -in client.csr -CA rootca.crt -CAkey rootca.key -CAcreateserial -out client.crt -days 3650
    # if [ "$?" -ne "0" ]; then
    #     echo "Unable to sign client certificate" >> /dev/stderr
    #     exit 1
    # fi
    #

    if [ ! -f "dh2048.pem" ]; then
      openssl dhparam -out dh2048.pem 2048
      if [ "$?" -ne "0" ]; then
          echo "Unable to generate DH certificate" >> /dev/stderr
          exit 1
      fi
    fi
}

get_ds_data ()
{
      hosts=(ifconfig.co ifconfig.me ipecho.net/plain icanhazip.com)

      for host in ${hosts[*]}; do
          ds_public_ip=$(curl -qL ${host}) &> /dev/null

          if [ ! -z $ds_public_ip ]; then
              break
          fi
      done

      ds_location=$(curl ifconfig.co/country) &> /dev/null
}

main ()
{
    detect_os

    update_packages_list

    curl_check
    gpg_check

    add_gpg_key "http://packages.gameap.ru/gameap-rep.gpg.key"
    echo "deb http://packages.gameap.ru/${os}/ ${dist} main" > /etc/apt/sources.list.d/gameap.list
    update_packages_list

    install_packages gameap-daemon openssl
    generate_certs

    if [[ $createToken ]]; then
        get_ds_data

        echo
        echo "Creating dedicated server on panel..."
        echo

        result=$(curl -qL \
          -F "ip[]=${ds_public_ip}" \
          -F "name=${HOSTNAME}" \
          -F "location=${ds_location}" \
          -F "work_path=/srv/gameap" \
          -F "os=linux" \
          -F "gdaemon_host=${ds_public_ip}" \
          -F "gdaemon_port=31717" \
          -F "gdaemon_server_cert=@/etc/gameap-daemon/certs/server.crt" \
          ${panelHost}/gdaemon/create/${createToken}) &> /dev/null

        if [ "$?" -ne "0" ]; then
            echo "Unable to insert dedicated server" >> /dev/stderr
            exit 1
        fi

        result_message=$(echo "$result" | head -1 | cut -d' ' -f1)

        if [ "$result_message" == "Error" ]; then
            echo "Unable to insert dedicated server: " >> /dev/stderr
            echo $(echo $result | cut -d' ' -f2-) >> /dev/stderr
            exit 1
        elif [ "$result_message" == "Success" ]; then
            echo
            echo "Configuring gameap daemon..."
            echo

            dedicated_server_id=$(echo $result | head -1 | cut -d' ' -f2)
            api_key=$(echo $result | head -1 | cut -d' ' -f3)

            certificate=$(echo "$result" | tail -n +2)
            echo "$certificate" > /etc/gameap-daemon/certs/client.crt

            sed -i "s/ds_id.*$/ds_id=${dedicated_server_id}/" /etc/gameap-daemon/gameap-daemon.cfg

            sed -i "s/api_host.*$/api_host=${panelHost##*/}/" /etc/gameap-daemon/gameap-daemon.cfg
            sed -i "s/api_key.*$/api_key=${api_key}/" /etc/gameap-daemon/gameap-daemon.cfg

            sed -i "s/client_certificate_file.*$/client_certificate_file=\/etc\/gameap-daemon\/certs\/client\.crt/" /etc/gameap-daemon/gameap-daemon.cfg
        else
            echo "Unknown response from panel"
            echo "$result" > response.log
        fi
    fi

    sed -i "s/certificate_chain_file.*$/certificate_chain_file=\/etc\/gameap-daemon\/certs\/server\.crt/" /etc/gameap-daemon/gameap-daemon.cfg
    sed -i "s/private_key_file.*$/private_key_file=\/etc\/gameap-daemon\/certs\/server\.key/" /etc/gameap-daemon/gameap-daemon.cfg
    sed -i "s/dh_file.*$/dh_file=\/etc\/gameap-daemon\/certs\/dh2048\.pem/" /etc/gameap-daemon/gameap-daemon.cfg

    echo "Starting GameAP Daemon..."
    service gameap-daemon start

    if [ "$?" -ne "0" ]; then
        echo "GameAP Daemon start failed" >> /dev/stderr
        exit 1
    fi

    echo "Success"
}

parse_options $@
main
