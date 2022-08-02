---
title: 使用 FreeBSD 进行安装
sidebar_label: 手动安装（FreeBSD）
---

这份文件提供了在 FreeBSD 中安装 TeslaMate 的必要步骤。**推荐的最直接的安装方法是通过使用 [Docker](docker.md)**，然而这份攻略提供了在 FreeBSD 13.0 环境中手动安装的必要步骤。
它假定前提条件已经满足，并且只提供了基本的说明，在 13.0 之前的 FreeBSD 中也应该可以使用。

## 要求

单击以下标题，查看详细的安装步骤。

<details>
  <summary>bash & jq</summary>

```bash
pkg install bash jq
bash
```

为了简单起见，请用 bash 而不是 csh 来完成本教程的其余部分。

</details>

<details>
  <summary>git</summary>

```bash
pkg install git
```

</details>

<details>
  <summary>Erlang (v21+)</summary>

```bash
pkg install erlang
```

</details>

<details>
  <summary>Elixir (v1.12+)</summary>

不幸的是，Elixir 部分在 FreeBSD ports 中没有很好的更新。因此，Erlang 21 的最新支持版本（FreeBSD ports 中的最新版本）为 Elixir 1.11。

我们将需要从源代码编译它，这很容易。

```bash
pkg install gmake

mkdir /usr/local/src
cd /usr/local/src
git clone https://github.com/elixir-lang/elixir.git
cd elixir
git checkout v1.11.4
gmake clean test
gmake install
elixir --version
```

</details>

<details>
  <summary>Postgres (v12+)</summary>

```bash
pkg install postgresql(12|13)-server
pkg install postgresql(12|13)-contrib
echo postgres_enable="yes" >> /etc/rc.conf
```

</details>

<details>
  <summary>Grafana (v8.3.4+) & Plugins</summary>

```bash
pkg install grafana7
echo grafana_enable="yes" >> /etc/rc.conf
```

</details>

<details>
  <summary>An MQTT Broker (e.g. Mosquitto)</summary>

```bash
pkg install mosquitto
echo mosquitto_enable="yes" >> /etc/rc.conf
```

</details>

<details>
  <summary>Node.js (v14+)</summary>

```bash
pkg install node14
pkg install npm-node14
```

</details>

## 克隆 TeslaMate 的 git 存储库

下面的命令将克隆 TeslaMate 项目的源文件。这应该在你想安装 TeslaMate 的适当目录下运行。请先记录这个路径，并将其提供给本指南末尾提出的启动脚本。

```bash
cd /usr/local/src

git clone https://github.com/adriankumpf/teslamate.git
cd teslamate

git checkout $(git describe --tags `git rev-list --tags --max-count=1`) # Checkout the latest stable version
```

## 创建 PostgreSQL 数据库

下面的命令将在 PostgreSQL 数据库服务器上创建一个名为 `teslamate` 的数据库，以及一个名为 `teslamate` 的用户。当创建 `teslamate` 用户时，你会被提示以交互方式输入用户的密码。这个密码应该被记录下来，并在本指南末尾的启动脚本中作为一个环境变量提供。如果不能从当前用户进入 psql 控制台，请使用 "su - postgres"。

```console
psql
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

export MIX_ENV=prod
mix do phx.digest, release --overwrite
```

## 在启动时自动启动 TeslaMate

### 创建 FreeBSD 服务以定义 _/usr/local/etc/rc.d/teslamate_

```console
# PROVIDE: teslamate
# REQUIRE: DAEMON
# KEYWORD: teslamate,tesla

. /etc/rc.subr

name=teslamate
rcvar=teslamate_enable

load_rc_config $name

user=teslamate
group=teslamate

#
# DO NOT CHANGE THESE DEFAULT VALUES HERE
# SET THEM IN THE /etc/rc.conf FILE
#
teslamate_enable=${teslamate_enable-"NO"}
pidfile=${teslamate_pidfile-"/var/run/${name}.pid"}

teslamate_enable_mqtt=${teslamate_enable_mqtt-"FALSE"}
teslamate_db_port=${teslamate_db_port-"5432"}

HTTP_BINDING_ADDRESS="0.0.0.0"; export HTTP_BINDING_ADDRESS
HOME="/usr/local/src/teslamate"; export HOME
PORT=${teslamate_port-"4000"}; export PORT
TZ=${teslamate_timezone-"Europe/Berlin"}; export TZ
LANG=${teslamate_locale-"en_US.UTF-8"}; export LANG
LC_CTYPE=${teslamate_locale-"en_US.UTF-8"}; export LC_TYPE
DATABASE_NAME=${teslamate_db-"teslamate"}; export DATABASE_NAME
DATABASE_HOST=${teslamate_db_host-"localhost"}; export DATABASE_HOST
DATABASE_USER=${teslamate_db_user-"teslamate"}; export DATABASE_USER
DATABASE_PASS=${teslamate_db_pass}; export DATABASE_PASS
ENCRYPTION_KEY=${teslamate_encryption_key}; export ENCRYPTION_KEY
DISABLE_MQTT=${teslamate_mqtt_enable-"FALSE"}; export DISABLE_MQTT
MQTT_HOST=${teslamate_mqtt_host-"localhost"}; export MQTT_HOST
VIRTUAL_HOST=${teslamate_virtual_host-"teslamate.example.com"}; export VIRTUAL_HOST

COMMAND=${teslamate_command-"${HOME}/_build/prod/rel/teslamate/bin/teslamate"}

teslamate_start()
{
  ${COMMAND} eval "TeslaMate.Release.migrate"
  ${COMMAND} daemon
}

start_cmd="${name}_start"
stop_cmd="${COMMAND} stop"
status_cmd="${COMMAND} pid"


run_rc_command "$1"

```

### 更新 _/etc/rc.conf_

```bash
echo teslamate_enable="YES" >> /etc/rc.conf
echo teslamate_db_host="localhost"  >> /etc/rc.conf
echo teslamate_port="5432"  >> /etc/rc.conf
echo teslamate_db_pass="<super secret>" >> /etc/rc.conf
echo teslamate_encryption_key="<super secret encryption key>" >> /etc/rc.conf
echo teslamate_disable_mqtt="true" >> /etc/rc.conf
echo teslamate_timezone="<TZ Database>" >> /etc/rc.conf #i.e. Europe/Berlin
```

### 启动服务

```bash
chmod +x /usr/local/etc/rc.d/teslamate
service teslamate start
```

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
