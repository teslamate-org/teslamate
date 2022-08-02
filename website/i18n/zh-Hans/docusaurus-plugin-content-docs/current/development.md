---
id: development
title: 开发和维护
sidebar_label: 开发和维护
---

## 要求

- **Elixir** >= 1.12
- **Postgres** >= 10
- An **MQTT broker** e.g. mosquitto (_optional_)
- **NodeJS** >= 14

## 初始设置

为了运行 TeslaMate 测试套件，你需要一个名为 `teslamate_test` 的数据库：

```bash
# download dependencies, create the dev database and run migrations
mix setup

# create the test database
MIX_ENV=test mix ecto.setup
```

## 本地运行

在另一个终端窗口启动一个 iex 会话：

```elixir
iex -S mix phx.server
```

然后用特斯拉账户登录。

## 热加载

要立即应用你的本地修改，打开或重新加载 [http://localhost:4000](http://localhost:4000)。你也可以通过 `iex` 重新加载特定的模块，例如：

```elixir
iex> r TeslaMate.Vehicles.Vehicle
```

若只编译修改内容：

```bash
mix compile
```

## 代码格式化

```bash
mix format
```

## 测试

为了确保提交通过 CI，你应该在本地运行 `mix ci`，它执行以下命令：

- 检查代码格式化 (`mix format --check-formatted`)
- 运行所有测试 (`mix test`)

## 对 Grafana 仪表板进行修改

要更新仪表盘，你需要在本地运行 Grafana。以下 _docker-compose.yml_ 可用于此目的。

```yml
version: "3"
services:
  grafana:
    image: teslamate-grafana:latest
    environment:
      - DATABASE_USER=postgres
      - DATABASE_PASS=postgres
      - DATABASE_NAME=teslamate_dev
      - DATABASE_HOST=host.docker.internal
    ports:
      - 3000:3000
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
```

_(在 Linux 上使用主机的实际 IP 地址作为 `DATABASE_HOST`，而不是 `host.docker.internal`)_

然后用 `make grafana` 构建镜像，通过 `docker-compose up grafana` 运行容器。

在 [http://localhost:3000](http://localhost:3000) 访问 Grafana，使用默认用户 `admin` 和密码 `admin` 登录。

然后在本地编辑相应的仪表板。要导出一个仪表盘，请点击 `保存` 按钮，并选择 `保存 JSON 到文件`。最终的 JSON 文件属于 `./grafana/dashboards/` 目录。要应用这些变化，请重建镜像并启动容器。
