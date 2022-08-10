---
title: 使用 Debian 进行安装
sidebar_label: 手动安装（Debian）
---

本文件提供了在 vanilla Debian 或 Ubuntu 系统上安装 TeslaMate 的必要步骤。**推荐的和最直接的安装方法是通过使用 [Docker](docker.md)**，然而本攻略提供了在 aptitude（Debian/Ubuntu）环境下手动安装的必要步骤。

## 要求

单击以下标题，查看详细的安装步骤。

<details>
  <summary>Postgres (v12+)</summary>

```bash
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | sudo tee  /etc/apt/sources.list.d/pgdg.list
sudo apt-get update
sudo apt-get install -y postgresql-12 postgresql-client-12
```

来源：[postgresql.org/download](https://www.postgresql.org/download/)

</details>

<details>
  <summary>Elixir (v1.12+)</summary>

```bash
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y elixir esl-erlang
```

来源：[elixir-lang.org/install](https://elixir-lang.org/install)

</details>

<details>
  <summary>Grafana (v8.3.4+) & Plugins</summary>

```bash
sudo apt-get install -y apt-transport-https software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server.service # to start Grafana at boot time
```

来源：[grafana.com/docs/installation](https://grafana.com/docs/grafana/latest/installation/)

同时安装所需的 Grafana 插件：

```bash
sudo grafana-cli plugins install pr0ps-trackmap-panel 2.1.2
sudo grafana-cli plugins install natel-plotly-panel 0.0.7
sudo grafana-cli --pluginUrl https://github.com/panodata/panodata-map-panel/releases/download/0.16.0/panodata-map-panel-0.16.0.zip plugins install grafana-worldmap-panel-ng
sudo systemctl restart grafana-server
```

在[克隆 TeslaMate git 仓库](#clone-teslamate-git-repository)之后，[导入 Grafana 仪表盘](#import-grafana-dashboards)。

</details>

<details>
  <summary>An MQTT Broker (e.g. Mosquitto)</summary>

```bash
sudo apt-get install -y mosquitto
```

来源：[mosquitto.org/download](https://mosquitto.org/download/)

</details>

<details>
  <summary>Node.js (v14+)</summary>

```bash
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get install -y nodejs
```

来源：[nodejs.org/en/download/package-manager](https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions-enterprise-linux-fedora-and-snap-packages)

</details>

## 克隆 TeslaMate 的 git 存储库

下面的命令将克隆 TeslaMate 项目的源文件。这应该在你想安装 TeslaMate 的适当目录下运行。请先记录这个路径，并将其提供给本指南末尾提出的启动脚本。

```bash
cd /usr/src

git clone https://github.com/adriankumpf/teslamate.git
cd teslamate

git checkout $(git describe --tags `git rev-list --tags --max-count=1`) # Checkout the latest stable version
```

## 创建 PostgreSQL 数据库

以下命令将在 PostgreSQL 数据库服务器上创建一个名为 `teslamate` 的数据库，以及一个名为 `teslamate` 的用户。当创建 `teslamate` 用户时，你会被提示以交互方式输入用户的密码。请记录此密码，并在本指南末尾的启动脚本中作为一个环境变量提供。

```console
sudo -u postgres psql
postgres=# create database teslamate;
postgres=# create user teslamate with encrypted password 'your_secure_password_here';
postgres=# grant all privileges on database teslamate to teslamate;
postgres=# ALTER USER teslamate WITH SUPERUSER;
postgres=# \q
```

_注意：在运行初始数据库迁移后，超级用户的权限可以被撤销。_

## 编译 Elixir 项目

```bash
mix local.hex --force; mix local.rebar --force

mix deps.get --only prod
npm install --prefix ./assets && npm run deploy --prefix ./assets

MIX_ENV=prod mix do phx.digest, release --overwrite
```

### 设置你的系统语言

你可能需要设置你的系统语言。如果你在运行 TeslaMate 服务时得到一个错误，这可能说明你没有设置一个能够使用 UTF-8 的系统语言，请运行以下命令来设置你系统上的语言。

```bash
sudo locale-gen en_US.UTF-8
sudo localectl set-locale LANG=en_US.UTF-8
```

## 在启动时自动启动 TeslaMate

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

<Tabs
defaultValue="systemd"
values={[
{ label: 'systemd', value: 'systemd', },
{ label: 'screen', value: 'screen', },
]}>
<TabItem value="systemd">

在 `/etc/systemd/system/teslamate.service` 创建一个 systemd 服务：

```
[Unit]
Description=TeslaMate
After=network.target
After=postgresql.service

[Service]
Type=simple
# User=username
# Group=groupname

Restart=on-failure
RestartSec=5

Environment="HOME=/usr/src/teslamate"
Environment="LANG=en_US.UTF-8"
Environment="LC_CTYPE=en_US.UTF-8"
Environment="TZ=Europe/Berlin"
Environment="PORT=4000"
Environment="ENCRYPTION_KEY=your_secure_encryption_key_here"
Environment="DATABASE_USER=teslamate"
Environment="DATABASE_PASS=#your secure password!
Environment="DATABASE_NAME=teslamate"
Environment="DATABASE_HOST=127.0.0.1"
Environment="MQTT_HOST=127.0.0.1"

WorkingDirectory=/usr/src/teslamate

ExecStartPre=/usr/src/teslamate/_build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
ExecStart=/usr/src/teslamate/_build/prod/rel/teslamate/bin/teslamate start
ExecStop=/usr/src/teslamate/_build/prod/rel/teslamate/bin/teslamate stop

[Install]
WantedBy=multi-user.target
```

- `MQTT_HOST` 应该是你的 MQTT 代理的 IP 地址。如果你没有安装，可以用 `DISABLE_MQTT=true` 禁用 MQTT 功能。
- `TZ` 应该是你的本地时区。使用链接的维基百科页面中的 [TZ 数据库名称](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)计算出你的时区名称。

启动服务：

```bash
sudo systemctl start teslamate
```

并自动让它在启动时启动：

```bash
sudo systemctl enable teslamate
```

</TabItem>
<TabItem value="screen">

创建以下文件： `/usr/local/bin/teslamate-start.sh`

你需要注意以下细节：

- `MQTT_HOST` 应该是你的 MQTT 代理的 IP 地址。如果你没有安装，可以用 `DISABLE_MQTT=true` 禁用 MQTT 功能。
- `TZ` 应该是你的本地时区。使用链接的维基百科页面中的 [TZ 数据库名称](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)计算出你的时区名称。
- `TESLAMATEPATH` 应该是你运行 `git clone` 的路径。

```
export ENCRYPTION_KEY="your_secure_encryption_key_here"
export DATABASE_USER="teslamate"
export DATABASE_PASS="your_secure_password_here"
export DATABASE_HOST="127.0.0.1"
export DATABASE_NAME="teslamate"
export MQTT_HOST="127.0.0.1"
export MQTT_USERNAME="teslamate"
export MQTT_PASSWORD="teslamate"
export MQTT_TLS="false"
export TZ="Europe/Berlin"
export TESLAMATEPATH=/usr/src/teslamate

$TESLAMATEPATH/_build/prod/rel/teslamate/bin/teslamate start
```

在安装过程中需要运行一次以下命令，以便为 TeslaMate 安装创建数据库模式：

```bash
export ENCRYPTION_KEY="your_secure_encryption_key_here"
export DATABASE_USER="teslamate"
export DATABASE_PASS="your_secure_password_here"
export DATABASE_HOST="127.0.0.1"
export DATABASE_NAME="teslamate"
_build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
```

在 /etc/rc.local 中添加以下内容，以便在启动时伴随启动一个屏幕会话，并在屏幕会话中运行 TeslaMate 服务器。这可以让你在需要时以交互方式连接到会话。

```bash
# Start TeslaMate
cd /usr/src/teslamate
screen -S teslamate -L -dm bash -c "cd /usr/src/teslamate; ./start.sh; exec sh"
```

</TabItem>
</Tabs>

## 导入 Grafana 仪表盘

1.  访问 [localhost:3000](http://localhost:3000) 并登录。默认的凭证是：`admin:admin`。

2.  创建一个名为 "TeslaMate" 的数据源：

    ```
    Type: PostgreSQL
    Default: YES
    Name: TeslaMate
    Host: localhost
    Database: teslamate
    User: teslamate  Password: your_secure_password_here
    SSL-Mode: disable
    Version: 10
    ```

3.  [手动导入](https://grafana.com/docs/reference/export_import/#importing-a-dashboard)仪表板[文件](https://github.com/adriankumpf/teslamate/tree/master/grafana/dashboards)或使用 `dashboards.sh` 脚本：

    ```bash
    $ ./grafana/dashboards.sh restore

    URL:                  http://localhost:3000
    LOGIN:                admin:admin
    DASHBOARDS_DIRECTORY: ./grafana/dashboards

    RESTORED locations.json
    RESTORED drive-stats.json
    RESTORED updates.json
    RESTORED drive-details.json
    RESTORED charge-details.json
    RESTORED states.json
    RESTORED overview.json
    RESTORED vampire-drain.json
    RESTORED visited.json
    RESTORED drives.json
    RESTORED projected-range.json
    RESTORED charge-level.json
    RESTORED charging-stats.json
    RESTORED mileage.json
    RESTORED charges.json
    RESTORED efficiency.json
    ```

    :::tip
    要使用默认以外的凭证，请设置 `LOGIN` 变量：

    ```bash
    LOGIN=user:password ./grafana/dashboards.sh restore
    ```

    :::
