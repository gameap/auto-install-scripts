#!/bin/bash

set -u
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
    echo
    echo -n "Running apt-get update... "

    apt-get update &> /dev/null

    if [ "$?" -ne "0" ]; then
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
    apt-get install -y ${packages[*]} &> /dev/null

    if [ "$?" -ne "0" ]; then
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
    os=""
    dist=""

    if [ -e /etc/lsb-release ]; then
        . /etc/lsb-release

        if [ "${ID:-}" = "raspbian" ]; then
            os=${ID}
            dist=$(cut --delimiter='.' -f1 /etc/debian_version)
        else
            os=${DISTRIB_ID}
            dist=${DISTRIB_CODENAME}

            if [ -z "$dist" ]; then
                dist=${DISTRIB_RELEASE}
            fi
        fi

    elif [ -n "$(command -v lsb_release 2>/dev/null)" ]; then
        dist=$(lsb_release -c | cut -f2)
        os=$(lsb_release -i | cut -f2 | awk '{ print tolower($1) }')

    elif [ -e /etc/debian_version ]; then
        os=$(cat /etc/issue | head -1 | awk '{ print tolower($1) }')
        if grep -q '/' /etc/debian_version; then
        dist=$(cut --delimiter='/' -f1 /etc/debian_version)
        else
        dist=$(cut --delimiter='.' -f1 /etc/debian_version)
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
    echo
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
    echo
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

steamcmd_install ()
{
    echo
    echo "Installing steamcmd..."

    if [[ ! -s "/srv/gameap/steamcmd" ]]; then
        mkdir /srv/gameap/steamcmd
    else
        echo "Directory /srv/gameap/steamcmd is exists"
        echo "Skipping installation SteamCMD"
        return
    fi

    install_packages lib32gcc1 lib32stdc++6

    cd /srv/gameap/steamcmd || return

    curl -O https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz

    if [ "$?" -ne "0" ]; then
        echo "Unable to download SteamCMD" >> /dev/stderr
        echo "Skipping installation SteamCMD" >> /dev/stderr
        return
    fi

    tar -xvzf steamcmd_linux.tar.gz

    if [ "$?" -ne "0" ]; then
        echo "Unable to unpack SteamCMD" >> /dev/stderr
        echo "Skipping installation SteamCMD" >> /dev/stderr
        return
    fi

    rm steamcmd_linux.tar.gz
}

generate_certs ()
{
    mkdir -p /etc/gameap-daemon/certs
    cd /etc/gameap-daemon/certs || exit 1

    echo
    echo "Generating GameAP Daemon server certificates..."
    echo

    if [ -f "server.key" ]; then
        echo "Server key exists. Skipping..."
    else
        openssl genrsa -out server.key 2048
        if [ "$?" -ne "0" ]; then
            echo "Unable to generate server key" >> /dev/stderr
            exit 1
        fi
    fi

    if [ -f "server.crt" ]; then
        echo "Server certificate exists. Skipping..."
    else
        openssl req -new -key server.key -subj "/CN=$(hostname)/O=GameAP Daemon" -out server.csr
        if [ "$?" -ne "0" ]; then
            echo "Unable to generate server certificate" >> /dev/stderr
            exit 1
        fi
    fi

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

        if [ -n "$ds_public_ip" ]; then
            break
        fi
    done

    ds_location=$(curl ifconfig.co/country) &> /dev/null

    ds_ip_list=()
    hostnames=$(hostname -I)

    for ip in ${hostnames[*]}; do
        if [ "$ip" == "$ds_public_ip" ]; then
            continue
        fi

        ds_ip_list+=($ip)
    done
}

function version { 
    echo "$@" | gawk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'; 
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
    
    work_dir="/srv/gameap"

    if [[ ! -s $work_dir ]]; then
        mkdir -p $work_dir
    fi

    if [ -z "$(getent group gameap)" ]; then
        groupadd "gameap"

        if [ "$?" -ne "0" ]; then
            echo "Unable to add group" >> /dev/stderr
            exit 1
        fi
    fi

    if [ -z "$(getent passwd gameap)" ]; then
        useradd -g gameap -d $work_dir -s /bin/bash gameap

        if [ "$?" -ne "0" ]; then
            echo "Unable to add user" >> /dev/stderr
            exit 1
        fi
    fi

    steamcmd_install

    install_packages gameap-daemon openssl unzip
    generate_certs

    if [[ -n "$createToken" ]]; then
        get_ds_data

        echo
        echo "Creating dedicated server on panel..."
        echo

        curl_ip_fields="-F ip[]=${ds_public_ip} "
        
        for ip in ${ds_ip_list[*]}; do
            curl_ip_fields+="-F ip[]=${ip} "
        done

        if [ -z "${ds_ip_list:-}" ]; then
            gdaemon_host=$ds_public_ip
        else
            gdaemon_host="${ds_ip_list[0]}"
        fi
        
        # OpenVZ compatible
        curl_script_fields=""
        if [ "$(version $(uname -r))" -le "$(version "2.6.32")" ]; then
            echo 
            echo "Old kernel detected..."
            echo "Using screen package instead gameap-starter..."
            echo 
            
            install_packages screen
            curl -o $work_dir/server.sh  https://raw.githubusercontent.com/et-nik/gameap-legacy/v1.2-stable/bin/Linux/server.sh
            chmod +x $work_dir/server.sh

            curl_script_fields+="-F script_start=./server.sh -t start -d {dir} -n {uuid} -u {user} -c {command} "
            curl_script_fields+="-F script_stop=./server.sh -t stop -d {dir} -n {uuid} -u {user} "
            curl_script_fields+="-F script_restart=./server.sh -t restart -d {dir} -n {uuid} -u {user} -c {command} "
            curl_script_fields+="-F script_status=./server.sh -t status -d {dir} -n {uuid} -u {user} "
            curl_script_fields+="-F script_get_console=./server.sh -t get_console -d {dir} -n {uuid} "
            curl_script_fields+="-F script_send_command=./server.sh -t send_command -d {dir} -n {uuid} -c {command} "
        fi

        result=$(curl -qL \
          ${curl_ip_fields} \
          -F "name=${HOSTNAME}" \
          -F "location=${ds_location}" \
          -F "work_path=${work_dir}" \
          -F "steamcmd_path=${work_dir}/steamcmd" \
          -F "os=linux" \
          -F "gdaemon_host=${gdaemon_host}" \
          -F "gdaemon_port=31717" \
          -F "gdaemon_server_cert=@/etc/gameap-daemon/certs/server.csr" \
          ${curl_script_fields} \
          ${panelHost}/gdaemon/create/${createToken}) &> /dev/null

        if [ "$?" -ne "0" ]; then
            echo "Unable to insert dedicated server" >> /dev/stderr
            exit 1
        fi

        result_message=$(echo "$result" | head -1 | cut -d' ' -f1)

        if [ "$result_message" == "Error" ]; then
            echo "Unable to insert dedicated server: " >> /dev/stderr
            echo "$(echo $result | cut -d' ' -f2-)" >> /dev/stderr
            exit 1
        elif [ "$result_message" == "Success" ]; then
            echo
            echo "Configuring gameap daemon..."
            echo

            dedicated_server_id=$(echo $result | head -1 | cut -d' ' -f2)
            api_key=$(echo $result | head -1 | cut -d' ' -f3)

            certificates=$(echo "$result" | tail -n +2)

            caCertificate=$(echo "$certificates" | sed -e '1h;2,$H;$!d;g' -re 's/(.*)\n\n(.*)/\1/g')
            serverCertificate=$(echo "$certificates" | sed -e '1h;2,$H;$!d;g' -re 's/(.*)\n\n(.*)/\2/g')

            echo "$caCertificate" > /etc/gameap-daemon/certs/ca.crt
            echo "$serverCertificate" > /etc/gameap-daemon/certs/server.crt

            sed -i "s/ds_id.*$/ds_id=${dedicated_server_id}/" /etc/gameap-daemon/gameap-daemon.cfg

            sed -i "s/api_host.*$/api_host=${panelHost##*/}/" /etc/gameap-daemon/gameap-daemon.cfg
            sed -i "s/api_key.*$/api_key=${api_key}/" /etc/gameap-daemon/gameap-daemon.cfg

            sed -i "s/ca_certificate_file.*$/ca_certificate_file=\/etc\/gameap-daemon\/certs\/ca\.crt/" /etc/gameap-daemon/gameap-daemon.cfg
        else
            echo
            echo
            echo "Unknown response from panel"
            echo "$result" > /tmp/gameap-response-create-ds.log
            echo "See /tmp/gameap-response-create-ds.log log"
            echo
            
            exit 1
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

parse_options "$@"
main
