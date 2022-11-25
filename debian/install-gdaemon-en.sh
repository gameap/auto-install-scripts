#!/bin/bash

set -u
shopt -s dotglob

[[ "${DEBUG:-}" == 'true' ]] && set -x
export DEBIAN_FRONTEND="noninteractive"

declare -a ds_ip_list

parse_options ()
{
    for i in "$@"
    do
        case $i in
            -h|--help)
                show_help
                exit 0
            ;;
            --without-starting)
                option_without_starting=1
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

_check_systemd()
{
    if ! command -v systemctl > /dev/null 2>&1; then
        return 1
    fi

    if ! systemctl daemon-reload >/dev/null 2>&1; then
        return 1
    fi

    return 0
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

install_gameap_daemon ()
{
    cd "$(mktemp -d)" || (echo "failed to make temp directory"; exit)

    echo "Downloading gameap-daemon binaries..."
    if ! curl -qL "https://packages.gameap.ru/gameap-daemon/download-release?os=linux&arch=$(arch)" \
      -o gameap-daemon.tar.gz > /dev/null 2>&1; then
        echo "Unable to download gameap-daemon" >> /dev/stderr
        exit 1
    fi

    echo "Unpacking gameap-daemon binaries..."
    if ! tar -xvf gameap-daemon.tar.gz; then
        echo "Unable to unpack gameap-daemon archive" >> /dev/stderr
        exit 1
    fi

    chmod +x gameap-daemon

    if _check_systemd; then
        echo "Downloading systemd configuration..."
        if ! curl -qL "https://packages.gameap.ru/gameap-daemon/systemd-service.tar.gz" \
        -o systemd-service.tar.gz > /dev/null 2>&1; then
            echo "Unable to download systemd configuration" >> /dev/stderr
            exit 1
        fi

        echo "Unpacking systemd configuration..."
        if ! tar -xvf systemd-service.tar.gz; then
            echo "Unable to unpack systemd configuration" >> /dev/stderr
            exit 1
        fi
    else
        echo "Downloading initd configuration..."
        if ! curl -qL "https://packages.gameap.ru/gameap-daemon/initrd-script-debian.tar.gz" \
          -o initrd-script-debian.tar.gz > /dev/null 2>&1; then
            echo "Unable to download initrd scripts configuration" >> /dev/stderr
            exit 1
        fi

        echo "Unpacking initd configuration..."
        if ! tar -xvf initrd-script-debian.tar.gz; then
            echo "Unable to unpack initrd scripts configuration" >> /dev/stderr
            exit 1
        fi
    fi

    echo "Downloading gameap-daemon configuration..."
    if ! curl -qL "https://raw.githubusercontent.com/gameap/daemon/master/config/gameap-daemon.cfg" \
      -o gameap-daemon.cfg > /dev/null 2>&1; then
        echo "Unable to download gameap-daemon configuration" >> /dev/stderr
        exit 1
    fi

    echo "Downloading gameap-daemon runner configuration..."
    if ! curl -qL "https://raw.githubusercontent.com/gameap/scripts/master/process-manager/screen/runner.sh" \
      -o runner.sh > /dev/null 2>&1; then
        echo "Unable to download gameap-daemon configuration" >> /dev/stderr
        exit 1
    fi

    echo "Copying gameap-daemon files..."
    mkdir -p /etc/gameap-daemon

    cp gameap-daemon /usr/bin/gameap-daemon
    cp gameap-daemon.cfg /etc/gameap-daemon/gameap-daemon.cfg

    cp runner.sh /srv/gameap/runner.sh
    chmod +x /srv/gameap/runner.sh

    if _check_systemd; then
        echo "Copying gameap-daemon systemd configuration..."
        cp gameap-daemon.service /etc/systemd/system/gameap-daemon.service
        if ! systemctl daemon-reload; then
            echo "Unable to daemon-reload" >> /dev/stderr
            exit 1
        fi
    else
        echo "Copying gameap-daemon initd configuration..."
        cp ./default/gameap-daemon /etc/default/gameap-daemon
        cp ./init.d/gameap-daemon /etc/init.d/gameap-daemon

        echo "DAEMON=\"/usr/bin/gameap-daemon\"" >> /etc/default/gameap-daemon
    fi

    install_packages tmux screen
}

gpg_check ()
{
    echo
    echo "Checking for gpg..."
    if command -v gpg > /dev/null; then
        echo "Detected gpg..."
    else
        echo "Installing gnupg for GPG verification..."
        if ! apt-get install -y gnupg; then
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
        if ! apt-get install -q -y curl; then
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

    if [[ $(getconf LONG_BIT) == "64" ]]; then
        lib32install
    fi

    cd /srv/gameap/steamcmd || return

    if ! curl -O https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz; then
        echo "Unable to download SteamCMD" >> /dev/stderr
        echo "Skipping installation SteamCMD" >> /dev/stderr
        return
    fi

    if ! tar -xvzf steamcmd_linux.tar.gz; then
        echo "Unable to unpack SteamCMD" >> /dev/stderr
        echo "Skipping installation SteamCMD" >> /dev/stderr
        return
    fi

    rm steamcmd_linux.tar.gz
}

lib32install ()
{
    if [[ "${os}" = "debian" ]]; then
        if [[ "${dist}" = "bullseye" ]]; then
            install_packages lib32gcc-s1 lib32stdc++6
        elif [[ "${dist}" = "bookworm" ]]; then
            install_packages lib32gcc-s1 lib32stdc++6 lib32z1
        else
            install_packages lib32gcc1 lib32stdc++6
        fi
    else
        install_packages lib32gcc1 lib32stdc++6
    fi
}

generate_certs ()
{
    mkdir -p /etc/gameap-daemon/certs
    cd /etc/gameap-daemon/certs || exit 1

    echo
    echo "Generating GameAP Daemon server certificates..."
    echo

    if [[ -f "server.key" ]]; then
        echo "Server key exists. Skipping..."
    else
        if ! openssl genrsa -out server.key 2048; then
            echo "Unable to generate server key" >> /dev/stderr
            exit 1
        fi
    fi

    if [[ -f "server.crt" ]]; then
        echo "Server certificate exists. Skipping..."
    else
        if ! openssl req -new -key server.key -subj "/CN=$(hostname)/O=GameAP Daemon" -out server.csr; then
            echo "Unable to generate server certificate" >> /dev/stderr
            exit 1
        fi
    fi
}

get_ds_data ()
{
    hosts=(ifconfig.me ipecho.net/plain icanhazip.com ifconfig.co)
    ds_public_ip="127.0.0.1"
    for host in ${hosts[*]}; do
        result=$(curl -qL ${host}) &> /dev/null

        if [[ "$?" -eq "0" ]]; then
            if is_ipv4 "${result}" || is_ipv6 "${result}"; then
                ds_public_ip=${result}
                break;
            fi
        fi
    done

    hosts=(ifconfig.co/country ipinfo.io/country ifconfig.es/country)
    ds_location="Unknown"
    for host in ${hosts[*]}; do
        result=$(curl -qL ${host}) &> /dev/null

        if [[ "$?" -eq "0" ]]; then
            if (( ${#result} < 32 )); then
                ds_location=${result}
                break;
            fi
        fi
    done

    if [[ -n $ds_public_ip ]]; then
        ds_ip_list+=("$ds_public_ip")
    fi

    hostnames=$(hostname -I)

    for ip in ${hostnames[*]}; do
        if [[ "$ip" == "$ds_public_ip" ]]; then
            continue
        fi

        if [[ "$ip" == "127."* ]]; then
            continue
        fi

        ds_ip_list+=("$ip")
    done
}

version ()
{
    echo "$@" | awk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'; 
}

is_ipv4 ()
{
    if [[ $1 =~ ^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; then
        # IPv4
        return 0
    fi

    return 1
}

is_ipv6 ()
{
    if [[ $1 =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        # IPv6
        return 0
    fi

    return 1
}

_groupadd ()
{
    group=$1

    if command -v groupadd > /dev/null; then
        groupadd ${group}
    elif command -v /usr/sbin/groupadd > /dev/null; then
        /usr/sbin/groupadd ${group}
    fi
}

main ()
{
    _check_env_variables

    detect_os

    update_packages_list

    curl_check
    gpg_check

    add_gpg_key "http://packages.gameap.ru/gameap-rep.gpg.key"
    update_packages_list
    
    work_dir="/srv/gameap"

    if [[ ! -s $work_dir ]]; then
        mkdir -p $work_dir
    fi

    if [[ -z "$(getent group gameap)" ]]; then
        _groupadd "gameap"

        if [[ "$?" -ne "0" ]]; then
            echo "Unable to add group" >> /dev/stderr
            exit 1
        fi
    fi

    if [[ -z "$(getent passwd gameap)" ]]; then
        useradd -g gameap -d $work_dir -s /bin/bash gameap

        if [[ "$?" -ne "0" ]]; then
            echo "Unable to add user" >> /dev/stderr
            exit 1
        fi
    fi

    steamcmd_install

    if ! mkdir -p "${work_dir}/servers"; then
        echo "Unable to create ${work_dir}/servers directory" >> /dev/stderr
        exit 1
    fi

    if ! chmod 755 "${work_dir}/servers"; then
        echo "Unable to chmod ${work_dir}/servers directory" >> /dev/stderr
        exit 1
    fi

    if ! chown -R gameap:gameap $work_dir; then
        echo "Unable to chown work directory" >> /dev/stderr
        exit 1
    fi

    install_packages openssl unzip xz-utils
    generate_certs

    install_gameap_daemon

    if [[ -n "${CREATE_TOKEN}" ]]; then
        get_ds_data

        echo
        echo "Creating dedicated server on panel..."
        echo
    
        declare -a curl_fields

        if [[ -z "${ds_ip_list:-}" ]]; then
            gdaemon_host=$ds_public_ip
        else
            for ip in ${ds_ip_list[*]}; do
                curl_fields+=("-F ip[]=${ip} ")
            done

            gdaemon_host="${ds_ip_list[0]}"

            if [[ "${#ds_ip_list[@]}" -gt 1 ]]; then
                for ip in ${ds_ip_list[*]}; do
                    # IPv4 is a priority. Check for IPv4.
                    if is_ipv4 ${ip}; then
                        gdaemon_host="${ip}"
                        break
                    fi
                done
            fi
        fi
        
        # OpenVZ compatible
        if [[ "$(version "$(uname -r)")" -le "$(version 2.6.32)" ]]; then
            echo 
            echo "Old kernel detected..."
            echo "Using screen package instead gameap-starter..."
            echo

            if [[ "${os}" == "ubuntu" ]]; then
                # Update libstdc++6 on Ubuntu Xenial OpenVZ
                install_packages software-properties-common
                add-apt-repository -y ppa:ubuntu-toolchain-r/test
                update_packages_list

                install_packages libstdc++6
            fi

            install_packages screen
            curl -o $work_dir/server.sh  https://raw.githubusercontent.com/et-nik/gameap-legacy/v1.2-stable/bin/Linux/server.sh
            chmod +x $work_dir/server.sh

            curl_fields+=("-F script_start={node_work_path}/server.sh -t start -d {dir} -n {uuid} -u {user} -c \"{command}\" ")
            curl_fields+=("-F script_stop={node_work_path}/server.sh -t stop -d {dir} -n {uuid} -u {user} ")
            curl_fields+=("-F script_restart={node_work_path}/server.sh -t restart -d {dir} -n {uuid} -u {user} -c \"{command}\" ")
            curl_fields+=("-F script_status={node_work_path}/server.sh -t status -d {dir} -n {uuid} -u {user} ")
            curl_fields+=("-F script_get_console={node_work_path}/server.sh -t get_console -d {dir} -n {uuid} -u {user} ")
            curl_fields+=("-F script_send_command={node_work_path}/server.sh -t send_command -d {dir} -n {uuid} -u {user} -c \"{command}\" ")
        else
            curl_fields+=("-F script_get_console={node_work_path}/runner.sh get_console -d {dir} -n {uuid} -u {user} ")
            curl_fields+=("-F script_send_command={node_work_path}/runner.sh send_command -d {dir} -n {uuid} -u {user} -c \"{command}\"")
        fi

        result=$(curl -qL \
          "${curl_fields[@]}" \
          -F "name=${HOSTNAME}" \
          -F "location=${ds_location}" \
          -F "work_path=${work_dir}" \
          -F "steamcmd_path=${work_dir}/steamcmd" \
          -F "os=linux" \
          -F "gdaemon_host=${gdaemon_host}" \
          -F "gdaemon_port=31717" \
          -F "gdaemon_server_cert=@/etc/gameap-daemon/certs/server.csr" \
          "${PANEL_HOST}"/gdaemon/create/"${CREATE_TOKEN}") &> /dev/null

        if [[ "$?" -ne "0" ]]; then
            echo "Curl Result: ${result}"
            echo "Curl Fields: " "${curl_fields[@]}"
            echo

            echo "Unable to insert dedicated server" >> /dev/stderr
            exit 1
        fi

        result_message=$(echo "$result" | head -1 | cut -d' ' -f1)

        if [[ "$result_message" == "Error" ]]; then
            echo "Unable to insert dedicated server: " >> /dev/stderr
            echo "$(echo $result | cut -d' ' -f2-)" >> /dev/stderr
            exit 1
        elif [[ "$result_message" == "Success" ]]; then
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

            if ! sed -i "s/ds_id.*$/ds_id=${dedicated_server_id}/" /etc/gameap-daemon/gameap-daemon.cfg \
                || ! sed -i "s/api_host.*$/api_host=${PANEL_HOST//\//\\/}/" /etc/gameap-daemon/gameap-daemon.cfg \
                || ! sed -i "s/api_key.*$/api_key=${api_key}/" /etc/gameap-daemon/gameap-daemon.cfg \
                || ! sed -i "s/ca_certificate_file.*$/ca_certificate_file=\/etc\/gameap-daemon\/certs\/ca\.crt/" /etc/gameap-daemon/gameap-daemon.cfg; then

                echo "Unable to edit GDaemon configuration (/etc/gameap-daemon/gameap-daemon.cfg)"
                exit 1
            fi

            if is_ipv6 "${gdaemon_host}"; then
                sed -i "s/listen_ip.*$/listen_ip=::/" /etc/gameap-daemon/gameap-daemon.cfg
            fi
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
    sed -i "s/.output_log.*$/output_log=\/var\/log\/gameap-daemon\/output\.log/" /etc/gameap-daemon/gameap-daemon.cfg

    if [[ -z "${option_without_starting:-}" ]]; then
        echo "Starting GameAP Daemon..."

        if ! service gameap-daemon start; then
            echo "Unable to start gameap-daemon service" >> /dev/stderr
            exit 1
        fi

        if _check_systemd; then
            systemctl enable gameap-daemon
        fi
    fi

    echo "Success"
}

parse_options "$@"
main
