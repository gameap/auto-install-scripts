#!/usr/bin/env bash

shopt -s dotglob
[[ "${DEBUG:-}" == 'true' ]] && set -x

trap ctrl_c INT

function ctrl_c() {
    echo
    echo "Exiting..."
    echo
    exit 130
}

parse_options () 
{
    for i in "$@"
    do
        case $i in
            -h|--help)
                show_help
                exit 0
            ;;
            --path=*)
                gameap_path=${i#*=}
                shift

                if [[ ! -s "${gameap_path}" ]]; then
                    mkdir -p ${gameap_path}

                    if [[ "$?" -ne "0" ]]; then
                        echo "Unable to make directory: ${gameap_path}." >> /dev/stderr
                        exit 1
                    fi
                fi
            ;;
            --host=*)
                gameap_host=${i#*=}
                shift
            ;;
            --web-server=*)
                web_selected="${i#*=}"
                shift
            ;;
            --database=*)
                db_selected="${i#*=}"
                shift
            ;;
            --github)
                from_github=1
            ;;
            --develop)
                develop=1
            ;;
            --upgrade)
                upgrade=1
            ;;
        esac
    done
}

show_help ()
{
    echo
    echo "GameAP web auto installator"
}

install_packages ()
{
    packages=$@

    echo
    echo -n "Installing ${packages}... "
    yum install -y $packages &> /dev/null

    if [[ "$?" -ne "0" ]]; then
        echo "Unable to install ${packages}." >> /dev/stderr
        echo "Package installation aborted." >> /dev/stderr
        exit 1
    fi

    echo "done."
    echo
}

add_gpg_key ()
{
    gpg_key_url=$1
    rpm --import "${gpg_key_url}" 2> /dev/null

    if [[ "$?" -ne "0" ]]; then
      echo "Unable to add GPG key!" >> /dev/stderr
      exit 1
    fi
}

generate_password()
{
    echo $(tr -cd 'a-zA-Z0-9' < /dev/urandom | fold -w18 | head -n1)
}

unknown_os ()
{
    echo "Unfortunately, your operating system distribution and version are not supported by this script."
    exit 2
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

            if [[ -z "$dist" ]]; then
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

    echo "Detected operating system as ${os}/${dist}."
}

gpg_check ()
{
    echo
    echo "Checking for gpg..."
    if command -v gpg > /dev/null; then
        echo "Detected gpg..."
    else
        echo "Installing gnupg for GPG verification..."
        yum install -y gnupg

        if [[ "$?" -ne "0" ]]; then
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
        yum install -q -y curl

        if [[ "$?" -ne "0" ]]; then
            echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work." >> /dev/stderr
            echo "Repository installation aborted." >> /dev/stderr
            exit 1
        fi
    fi
}

tar_check ()
{
    echo
    echo "Checking for tar..."

    if command -v tar > /dev/null; then
        echo "Detected tar..."
    else
        echo "Installing tar..."
        yum install -q -y tar

        if [[ "$?" -ne "0" ]]; then
            echo "Unable to install tar! Your base system has a problem; please check your default OS's package repositories because tar should work." >> /dev/stderr
            echo "Repository installation aborted." >> /dev/stderr
            exit 1
        fi
    fi
}

mysql_repo_setup ()
{
    echo
    echo "Setup MySQL repo..."

    if [[ "${os}" == "centos" ]] && [[ "${dist}" == "6" ]]; then

        if [[ $(uname -p) == "x86_64" ]]; then
            mariadb_repo_arch="amd64"
        else
            mariadb_repo_arch="x86"
        fi

        cat <<EOT >> /etc/yum.repos.d/mariadb.repo
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.1/centos${dist}-${mariadb_repo_arch}
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOT
    fi
}

get_package_name ()
{
    package=$1

    if [[ "${package}" = "mysql" ]]; then
        case ${dist} in
            "6" ) package_name="MariaDB-server" ;;
            "7" ) package_name="mariadb-server" ;;
            "8" ) package_name="mysql-server" ;;
        esac
    fi

    echo $package_name
}

add_php_repo ()
{
    yum -y install epel-release &> /dev/null
    yum -y install http://rpms.remirepo.net/enterprise/remi-release-${dist}.rpm &> /dev/null
    yum -y install yum-utils &> /dev/null
    php_packages_check 1
}

php_packages_check ()
{
    not_repo=$1
    
    echo
    echo
    echo "Checking for PHP..."

    echo
    echo "Checking for PHP 8.0 version available..."

    if yum --showduplicates list php74 &> /dev/null; then
        echo "PHP 8.0 available"
        php_version="80"

        if [[ ${dist} == "8" ]]; then
            yum module disable php:remi-7.2 -y &> /dev/null
            yum module disable php:remi-7.3 -y &> /dev/null
            yum module enable php:remi-7.4 -y &> /dev/null
        else
            yum-config-manager --disable remi-php54 &> /dev/null
            yum-config-manager --enable remi-php${php_version} &> /dev/null
        fi

        return
    fi
    echo "PHP 8.0 not available..."

    echo
    echo "Checking for PHP 7.4 version available..."

    if yum --showduplicates list php74 &> /dev/null; then
        echo "PHP 7.4 available"
        php_version="74"

        if [[ ${dist} == "8" ]]; then
            yum module disable php:remi-7.2 -y &> /dev/null
            yum module disable php:remi-7.3 -y &> /dev/null
            yum module enable php:remi-7.4 -y &> /dev/null
        else
            yum-config-manager --disable remi-php54 &> /dev/null
            yum-config-manager --enable remi-php${php_version} &> /dev/null
        fi

        return
    fi
    echo "PHP 7.4 not available..."

    echo
    echo "Checking for PHP 7.3 version available..."

    if yum --showduplicates list php73 &> /dev/null; then
        echo "PHP 7.3 available"
        php_version="73"

        if [[ ${dist} == "8" ]]; then
            yum module disable php:remi-7.2 -y &> /dev/null
            yum module enable php:remi-7.3 -y &> /dev/null
        else
            yum-config-manager --disable remi-php54 &> /dev/null
            yum-config-manager --enable remi-php${php_version} &> /dev/null
        fi

        return
    fi
    echo "PHP 7.3 not available..."

    if [[ -z ${not_repo} ]]; then
        echo
        echo "Trying to add PHP repo..."
        add_php_repo
    fi
}

install_from_github ()
{
    install_packages git

    echo
    echo "Installing Composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    echo "done"
    
    echo
    echo "Installing NodeJS..."
    curl -sL https://rpm.nodesource.com/setup_15.x | sudo -E bash - &> /dev/null
    install_packages nodejs
    echo "done"

    if [[ -z "${develop:-}" ]]; then
        git_branch="master"
    else
        git_branch="develop"
    fi

    git clone -b $git_branch https://github.com/et-nik/gameap.git $gameap_path
    if [[ "$?" -ne "0" ]]; then
        echo "Unable to download from GitHub" >> /dev/stderr
        exit 1
    fi

    cd $gameap_path || exit 1

    echo
    echo "Installing Composer packages..."
    echo "This may take a long while..."
    if ! composer install &> /dev/null; then
        echo "Unable to install Composer packages. " >> /dev/stderr
        exit 1
    fi
    echo "done"

    cp .env.example .env

    echo
    echo "Generating encryption key..."
    php artisan key:generate --force
    echo "done"

    echo
    echo "Installing NodeJS packages..."
    npm install &> /dev/null
    if [[ "$?" -ne "0" ]]; then
        echo "Unable to install NodeJS packages. " >> /dev/stderr
        echo "Styles building aborted." >> /dev/stderr
        exit 1
    fi
    echo "done"

    echo
    echo "Building the styles..."
    npm run prod &> /dev/null
    if [[ "$?" -ne "0" ]]; then
        echo "Unable to build styles. " >> /dev/stderr
        echo "Styles building aborted." >> /dev/stderr
        exit 1
    fi
    echo "done"
}

download_unpack_from_repo ()
{
    cd $gameap_path || exit 1

    echo
    echo "Downloading GameAP archive..."

    curl -SfL http://packages.gameap.ru/gameap/latest \
        --output gameap.tar.gz &> /dev/null
    
    if [[ "$?" -ne "0" ]]; then
        echo "Unable to download GameAP. "
        echo "Installation GameAP aborted."
        exit 1
    fi
    echo "done"

    echo "Unpacking GameAP archive..."
    tar -xvf gameap.tar.gz -C ./ &> /dev/null
    if [[ "$?" -ne "0" ]]; then
        echo "Unable to unpack GameAP. " >> /dev/stderr
        echo "Installation GameAP aborted." >> /dev/stderr
        exit 1
    fi
    echo "done"
    
    cp -r gameap/* ./
    rm -r gameap
    rm gameap.tar.gz
}

install_from_official_repo ()
{
    cd $gameap_path || exit 1

    download_unpack_from_repo

    cp .env.example .env
}

generate_encription_key ()
{
    cd $gameap_path || exit 1
    
    echo "Generating encryption key..."
    php artisan key:generate --force
    
    if [[ "$?" -ne "0" ]]; then
        echo "Unable to generate encription key" >> /dev/stderr
        exit 1
    fi

    echo "done"
}

upgrade_migrate ()
{
    cd $gameap_path || exit 1

    echo
    echo "Migrating database..."
    php artisan migrate

    if [[ "$?" -ne "0" ]]; then
        echo "Unable to migrate database" >> /dev/stderr
        exit 1
    fi
    echo "done"
}

upgrade_postscripts ()
{
    cd $gameap_path || exit 1

    php artisan cache:clear
    php artisan config:cache
    php artisan view:cache
}

upgrade_from_github ()
{
    cd $gameap_path || exit 1
    git pull

    if [[ "$?" -ne "0" ]]; then
        echo "Unable to running \"git pull\"" >> /dev/stderr
        exit 1
    fi

    echo
    echo "Updating Composer packages..."
    echo "This may take a long while..."
    composer update --no-dev --optimize-autoloader &> /dev/null

    if [[ "$?" -ne "0" ]]; then
        echo "Unable to update Composer packages. " >> /dev/stderr
        exit 1
    fi
    echo "done"

    echo
    echo "Building the styles..."
    npm run prod &> /dev/null
    if [[ "$?" -ne "0" ]]; then
        echo "Unable to build styles. " >> /dev/stderr
        echo "Styles building aborted." >> /dev/stderr
        exit 1
    fi
    echo "done"

    upgrade_migrate
    upgrade_postscripts
}

upgrade_from_official_repo ()
{
    cd $gameap_path || exit 1

    download_unpack_from_repo
    upgrade_migrate
    upgrade_postscripts
}


cron_setup ()
{
    crontab -l > gameap_cron
    echo "* * * * * cd ${gameap_path} && php artisan schedule:run >> /dev/null 2>&1" >> gameap_cron
    crontab gameap_cron
    rm gameap_cron
}

mysql_service_name ()
{
    case ${dist} in
        "6" ) echo "mysql" ;;
        "7" ) echo "mariadb" ;;
        "8" ) echo "mysqld" ;;
    esac
}

mysql_setup ()
{
    #while true; do read -p "Enter MySQL root password: " database_root_password; done
    #while true; do read -p "Enter MySQL user name: " database_user_name; done
    #while true; do read -p "Enter MySQL user password: " database_user_password; done

    if command -v mysqld > /dev/null; then
        echo
        echo "Detected installed mysql..."

        echo "MySQL configuring skipped."
        echo "Please configure MySQL manually."

        mysql_manual=1

        echo "Enter DB username: "
        read -r database_user_name
        echo "Enter DB password: "
        read -r database_user_password
        echo "Enter DB table name: "
        read -r database_table_name
    else
        mysql_repo_setup

        database_root_password=$(generate_password)
        database_user_name="gameap"
        database_user_password=$(generate_password)
        database_table_name="gameap"

        install_packages "$(get_package_name mysql)"
        unset mysql_package

        service $(mysql_service_name) start

        /usr/bin/mysqladmin -u root password "${database_root_password}"

        mysql -u root -p${database_root_password} -e 'CREATE DATABASE IF NOT EXISTS `gameap`' &> /dev/null
        if [[ "$?" -ne "0" ]]; then echo "Unable to create database. MySQL seting up failed." >> /dev/stderr; exit 1; fi

        innodb_version=$(mysql -u root -p${database_root_password} --disable-column-names -s -r -e "SELECT @@GLOBAL.innodb_version;")

        # Compare versions
        if [[  "${innodb_version}" = "`echo -e "${innodb_version}\n5.7" | sort -V | head -n1`" ]]; then
            # < 5.7
            password_field="password"
        else 
            password_field="authentication_string"
        fi

        if [[ "$?" -ne "0" ]]; then echo "Unable to set database root password. MySQL seting up failed." >> /dev/stderr; exit 1; fi

        service $(mysql_service_name) restart

        mysql -u root -p${database_root_password} -e "USE mysql;\
            CREATE USER '${database_user_name}'@'localhost' IDENTIFIED BY '${database_user_password}';\
            GRANT SELECT ON *.* TO '${database_user_name}'@'localhost';\
            GRANT ALL PRIVILEGES ON gameap.* TO '${database_user_name}'@'localhost';
            FLUSH PRIVILEGES;"

        if [[ "$?" -ne "0" ]]; then echo "Unable to grant privileges. MySQL seting up failed." >> /dev/stderr; exit 1; fi
    fi
}

nginx_setup ()
{
    if command -v nginx > /dev/null; then
        echo "Detected installed nginx..."
    else
        cat <<EOT >> /etc/yum.repos.d/nginx.repo
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/${os}/${dist}/$(uname -p)/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/${os}/${dist}/$(uname -p)/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
EOT

        install_packages nginx
    fi

    curl -SfL https://raw.githubusercontent.com/gameap/auto-install-scripts/master/web-server-configs/nginx-no-ssl.conf \
        --output /etc/nginx/conf.d/gameap.conf &> /dev/null

    if [[ "$?" -ne "0" ]]; then
        echo "Unable to download default nginx config" >> /dev/stderr
        echo "Nginx configuring skipped" >> /dev/stderr
        return
    fi

    sed -i "s/^\(\s*user\s*\).*$/\1www-data\;/" /etc/nginx/nginx.conf

    gameap_public_path="$gameap_path/public"

    sed -i "s/^\(\s*server\_name\s*\).*$/\1${gameap_host}\;/" /etc/nginx/conf.d/gameap.conf
    sed -i "s/^\(\s*root\s*\).*$/\1${gameap_public_path//\//\\/}\;/" /etc/nginx/conf.d/gameap.conf
    sed -i "s/^\(\s*root\s*\).*$/\1${gameap_public_path//\//\\/}\;/" /etc/nginx/conf.d/gameap.conf

    fastcgi_pass=unix:/var/run/php-fpm/php-fpm.sock
    sed -i "s/^\(\s*fastcgi_pass\s*\).*$/\1${fastcgi_pass//\//\\/}\;/" /etc/nginx/conf.d/gameap.conf

    service nginx start
    service php-fpm start
}

apache_setup ()
{
    if command -v httpd > /dev/null; then
        echo "Detected installed apache..."
    else
        install_packages httpd
    fi

    curl -SfL https://raw.githubusercontent.com/gameap/auto-install-scripts/master/web-server-configs/apache-no-ssl.conf \
        --output /etc/httpd/conf.d/gameap.conf &> /dev/null

    if [[ "$?" -ne "0" ]]; then
        echo "Unable to download default Apache config" >> /dev/stderr
        echo "Apache configuring skipped" >> /dev/stderr
        return
    fi

    sed -i "s/^User .*$/User www-data/" /etc/httpd/conf/httpd.conf
    sed -i "s/^Group .*$/Group www-data/" /etc/httpd/conf/httpd.conf

    gameap_public_path="$gameap_path/public"
    gameap_ip=$(getent hosts ${gameap_host} | awk '{ print $1 }')

    sed -i "s/^\(\s*<VirtualHost\s*\).*\(:[0-9]*>\)$/\1${gameap_ip}\2/" /etc/httpd/conf.d/gameap.conf
    sed -i "s/^\(\s*ServerName\s*\).*$/\1${gameap_host}/" /etc/httpd/conf.d/gameap.conf
    sed -i "s/^\(\s*DocumentRoot\s*\).*$/\1${gameap_public_path//\//\\/}/" /etc/httpd/conf.d/gameap.conf
    sed -i "s/^\(\s*[\<{1}]Directory\s*\).*$/\1${gameap_public_path//\//\\/}>/" /etc/httpd/conf.d/gameap.conf

    sed -i '/ErrorLog/d' /etc/httpd/conf.d/gameap.conf
    sed -i '/CustomLog/d' /etc/httpd/conf.d/gameap.conf

    sed -i '/Require all granted/d' /etc/httpd/conf.d/gameap.conf

    if [[ -f /etc/httpd/conf.d/php.conf ]]; then
        php_fpm_handler="\"proxy:unix:/run/php-fpm/php-fpm.sock|fcgi://localhost\""
        sed -i "s/^\(\s*SetHandler\).*proxy:unix:\/run\/php-fpm.*$/\1 ${php_fpm_handler//\//\\/}/" /etc/httpd/conf.d/php.conf
    fi

    service httpd start
}

ask_user ()
{
    if [[ -z "${gameap_path}" ]]; then
        while true; do
            echo 
            read -p "Enter gameap installation path (Example: /var/www/gameap): " gameap_path

            if [[ -z "${gameap_path}" ]]; then
                gameap_path="/var/www/gameap"
            fi
            
            if [[ ! -s "${gameap_path}" ]]; then
                    read -p "${gameap_path} not found. Do you wish to make directory? (Y/n): " yn
                    case $yn in
                        [Yy]* ) mkdir -p ${gameap_path}; break;;
                    esac
            else 
                break;
            fi
        done
    fi

    if [[ -z "${upgrade:-}" ]]; then

        while [[ -z "${gameap_host}" ]]; do
            read -p "Enter gameap host (example.com): " gameap_host
        done

        if [[ -z "${db_selected:-}" ]]; then
            echo
            echo "Select database to install and configure"

            echo "1) MySQL"
            echo "2) SQLite"
            echo "3) None. Do not install a database"
            echo 

            while true; do
                read -p "Enter number: " db_selected
                case ${db_selected} in
                    1* ) db_selected="mysql"; echo "Okay! Will try install MySQL..."; break;;
                    2* ) db_selected="sqlite"; echo "Okay! Will try install SQLite..."; break;;
                    3* ) db_selected="none"; echo "Okay! ..."; break;;
                    * ) echo "Please answer 1-3.";;
                esac
            done
        fi

        if [[ -z "${web_selected:-}" ]]; then
            echo
            echo "Select Web-server to install and configure"

            echo "1) Nginx (Recommended)"
            echo "2) Apache"
            echo "3) None. Do not install a Web Server"
            echo 

            while true; do
                read -p "Enter number: " web_selected
                case $web_selected in
                    1* ) web_selected="nginx"; echo "Okay! Will try to install Nginx..."; break;;
                    2* ) web_selected="apache"; echo "Okay! Will try install Apache..."; break;;
                    3* ) web_selected="none"; echo "Okay! ..."; break;;
                    * ) echo "Please answer 1-3.";;
                esac
            done
        fi

    fi
}

main ()
{
    detect_os

    ask_user

    curl_check
    gpg_check
    tar_check

    if [[ -n "${upgrade:-}" ]]; then
        if [[ -n "${from_github:-}" ]]; then
            upgrade_from_github
        else
            upgrade_from_official_repo
        fi

        exit 0
    fi

    install_packages initscripts

    php_packages_check

    if [[ -z "${php_version}" ]]; then
        echo "Unable to find PHP >= 7.3" >> /dev/stderr
        exit 1
    fi

    install_packages php \
        php${php_version} \
        php${php_version}-php-common \
        php-gd \
        php-cli \
        php-fpm \
        php-pdo \
        php-mysqlnd \
        php-pecl-zip \
        php-redis \
        php-json \
        php-xml \
        php-mbstring \
        php-bcmath \
        php-gmp \
        php-intl

    # PHP. Listen unix socket /run/php-fpm/php-fpm.sock
    php_fpm_listen=/var/run/php-fpm/php-fpm.sock
    sed -i "s/^\(listen\s*=\s*\).*$/\1${php_fpm_listen//\//\\/}/" /etc/php-fpm.d/www.conf

    sed -i "s/^\(;listen.owner\s*=\s*\).*$/listen.owner = www-data/" /etc/php-fpm.d/www.conf
    sed -i "s/^\(;listen.group\s*=\s*\).*$/listen.group = www-data/" /etc/php-fpm.d/www.conf

    sed -i "s/^\(listen.acl_users\s*=\s*\).*$/\1apache,nginx,www-data/" /etc/php-fpm.d/www.conf

    sed -i "s/^\(user\s*=\s*\).*$/\1www-data/" /etc/php-fpm.d/www.conf
    sed -i "s/^\(group\s*=\s*\).*$/\1www-data/" /etc/php-fpm.d/www.conf

    if [[ -n "${from_github:-}" ]]; then
        install_from_github
    else
        install_from_official_repo
    fi

    chcon -R -t httpd_sys_content_t ${gameap_path}
    chcon -R -t httpd_sys_rw_content_t ${gameap_path}/storage
    chcon -R -t httpd_sys_rw_content_t ${gameap_path}/modules
    setsebool -P httpd_can_network_connect 1
    setsebool -P httpd_can_network_connect_db 1

    case ${db_selected} in
        "mysql" )
            mysql_setup

            sed -i "s/^\(DB\_CONNECTION\s*=\s*\).*$/\1mysql/" .env
            sed -i "s/^\(DB\_DATABASE\s*=\s*\).*$/\1${database_table_name}/" .env
            sed -i "s/^\(DB\_USERNAME\s*=\s*\).*$/\1${database_user_name}/" .env
            sed -i "s/^\(DB\_PASSWORD\s*=\s*\).*$/\1${database_user_password}/" .env
        ;;

        "sqlite" )
            database_name="${gameap_path}/database.sqlite"
            touch $database_name

            sed -i "s/^\(DB\_CONNECTION\s*=\s*\).*$/\1sqlite/" .env
            sed -i "s/^\(DB\_DATABASE\s*=\s*\).*$/\1${database_name//\//\\/}/" .env
        ;;
    esac

    generate_encription_key

    if [[ "${db_selected}" != "none" ]]; then
        echo "Migrating database..."
        php artisan migrate --seed

        if [[ "$?" -ne "0" ]]; then
            echo "Unable to migrate database." >> /dev/stderr
            echo "Database seting up aborted." >> /dev/stderr
            exit 1
        fi
        echo "done"
    fi

    if ! id -u "www-data" > /dev/null 2>&1; then
        adduser --no-create-home --system --user-group --shell /bin/false www-data
    fi

    if [[ "${web_selected}" != "none" ]]; then
        case $web_selected in
            "nginx" ) nginx_setup;;
            "apache" ) apache_setup;;
        esac
    fi

    chown -R www-data:www-data ${gameap_path}
    cron_setup

    # Change admin password
    cd $gameap_path
    admin_password=$(generate_password)
    php artisan user:change-password "admin" "${admin_password}"

    echo
    echo
    echo
    echo "---------------------------------"
    echo "DONE!"
    echo
    echo "GameAP file path: ${gameap_path}"
    echo

    if [[ "${db_selected}" = "sqlite" ]]; then
        echo "Database: ${database_name}"
    else
        if [[ ! -z "$database_root_password" ]]; then echo "Database root password: ${database_root_password}"; fi
        echo "Database name: gameap"
        if [[ ! -z "$database_user_name" ]]; then echo "Database user name: ${database_user_name}"; fi
        if [[ ! -z "$database_user_password" ]]; then echo "Database user password: ${database_user_password}"; fi
    fi

    echo
    echo "Administrator credentials"
    echo "Login: admin"
    echo "Password: ${admin_password}"
    echo
    echo "Host: http://${gameap_host}"
    echo
    echo "---------------------------------"
}

parse_options "$@"
main
