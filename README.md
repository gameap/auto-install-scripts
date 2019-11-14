GameAP full auto installation scripts

[![Build Status](https://drone.gameap.ru/api/badges/gameap/auto-install-scripts/status.svg)](https://drone.gameap.ru/gameap/auto-install-scripts)

## Supported OS

| Operating System       | Version          | Supported | Notes
|-----------------------|-------------------|-----------|----------------------------|
| Debian                | sid               | ✔         | Unstable distributive. Latest manual test: 26.07.2019
|                       | 10 / buster       | ✔         | 
|                       | 9 / stretch       | ✔         | Additional PHP repo is needed
|                       | 8 / jessie        | ✔         | Additional PHP repo is needed
|                       | 7 / wheezy        | ✘         | No repositories with PHP >= 7.1
|                       | 6 / squeeze       | ✘         | No repositories with PHP >= 7.1
| Ubuntu                | 19.10 / eoan      | ✔         | 
|                       | 19.04 / disco     | ✔         | 
|                       | 18.04 / bionic    | ✔         |
|                       | 16.04 / xenial    | ✔         |
|                       | 14.04 / trusty    | ✔         | Additional PHP repo is needed
|                       | 12.04 / precise   | ✘         | No repositories with PHP >= 7.1
| CentOS                | 8                 | ✔         | 
|                       | 7                 | ✔         | Additional PHP repo is needed.
|                       | 6                 | ✔         | Additional PHP repo is needed. Additional MySQL Repo is needed

## Installation

Download script and set execute permissions:
```
curl https://raw.githubusercontent.com/gameap/auto-install-scripts/master/install.sh \
        --output install-gameap.sh

chmod +x install-gameap.sh
```

## Usage

### Without options
```
./install-gameap.sh
```

### With options
```
./install-gameap.sh --path=/var/www/gameap \
    --host=your-gameap.ru \
    --web-server=nginx \
    --database=mysql
```

### Options

- `--path` Path to GameAP directory.
- `--host` Web host.
- `--web-server` Web server. Possible values: `nginx`, `apache`, `none`
- `--database` Database. Possible values: `mysql`, `pgsql`, `sqlite`, `none`
- `--github` Build GameAP from GitHub. Script will build styles and install PHP dependencies.