---
title: 从 tesla-apiscraper 导入（BETA）
sidebar_label: tesla-apiscraper
---

这是一个多步骤的过程，从 [tesla-apiscraper](https://github.com/lephisto/tesla-apiscraper) InfluxDB 后端导出你的数据，将其转换为可导入 TeslaMate 的格式（特别是 TeslaFi CSV），同时修复 scraper 产生的一些典型数据故障，然后再导入。

## 要求

- 由 `tesla-apiscraper` 存储的数据副本 - 特别是挂载在标准 apiscraper Docker 配置中的 `/opt/apiscraper/influxdb` 文件夹。在尝试导出和转换之前，**创建一个备份**，以备不时之需。

- 一个运行 Docker 的系统，有足够的内存让 InfluxDB 执行 CSV 导出。这并**不需要**是运行 API Scraper 和/或 TeslaMate 的同一台机器，你可以在你的 PC/Mac 上进行导出和转换。重要的是给 Docker 机器提供 2GB 以上的内存，否则 InfluxDB 的导出可能会失败。

- 在试图将任何东西导入 TeslaMate 之前，**创建一个你的数据的[备份](../maintenance/backup_restore.md)**。测试版可能不稳定 :)

## 步骤

:::note 故障排除
所有这些都是实验性的，还没有经过广泛的测试。如果你在第一部分或第二部分中遇到错误，请在 GitHub 上的 [tesla-apiscraper-to-teslafi-export](https://github.com/olexs/tesla-apiscraper-to-teslafi-export) 项目中创建一个问题，因为它与 TeslaMate 没有直接关系。
:::

### 第一部分：将 API Scraper InfluxDB 的数据导出到 CSV 中

1. 下载或克隆 [tesla-apiscraper-to-teslafi-export](https://github.com/olexs/tesla-apiscraper-to-teslafi-export) 资源库到你机器上的一个文件夹。

2. 将 `tesla-apiscraper` 数据文件夹 _contents_（_data_、_meta_ 和 _wal_ 文件夹）放入 `influxdb-data` 文件夹，在 `influxdb-export.sh` 文件旁边。文件夹结构必须是这样的：

   ```console
   .
   ├── influxdb-export.sh
   ├── influxdb-export.bat
   ├── (other stuff)
   └── influxdb-data
       ├── README.md
       ├── data
       ├── meta
       └── wal
   ```

3. 运行 `influxdb-export.sh` 脚本（如果你使用的是 Windows，则是 `influxdb-export.bat`）。如果你的 Docker 安装需要 root 权限，你可能需要 `sudo` 它或在管理员命令行提示下运行它。它将做以下工作：

   - 创建 `influxdb-csv` 输出文件夹，如果它还不存在的话
   - 启动 InfluxDB Docker 容器，挂载 `influxdb-data` 和 `influxdb-csv` 文件夹（在 Windows 下，你可能需要允许 Docker 访问你正在工作的驱动器，以便挂载工作）。
   - 等待容器报告为 _healthy_
   - 对 apiscraper 存储的所有数据执行导出命令，将 CSV 文件放在 `influxdb-csv` 文件夹中。
   - 停止并删除 InfluxDB 容器

   这可能需要一点时间。过程结束后，如果没有错误报告，继续进行步骤的下一部分。

### 第 2 部分：将导出的 InfluxDB CSV 文件转换为 TeslaFi CSV

1. 获得你的特斯拉的 **vehicle ID** 号。这是一个 10 位或 11 位的数字，唯一标识你的车，是 TeslaFi 数据格式的一部分，但它不包括在 tesla-apiscraper 数据中 - 所以你需要单独获取它。有几种方法可以得到它：

   - 手动使用 Tesla API。这个数字在 `vehicles` 响应中的 `vehicle_id` 下列出，这里有记载：[https://tesla-api.timdorr.com/api-basics/vehicles](https://tesla-api.timdorr.com/api-basics/vehicles)。
   - 从你已经使用的另一个特斯拉 API 跟踪器的数据库中，比如 TeslaMate(**docker-compose exec database psql teslamate teslamate -c 'select vid from cars;'**)。

2. 运行 `teslafi-convert.sh` 脚本（或者在 Windows 上 `teslafi-convert.bat`）。如果你的 Docker 安装需要 root 权限，你可能需要 `sudo` 它/在管理员命令行提示下运行它。它将做以下工作。

   - 创建 `teslafi-csv` 输出文件夹，如果它还不存在的话
   - 建立并启动一个 Docker 容器，其中包含 `converter` 应用程序及其几个依赖项，并挂载 `influxdb-csv` 和 `teslafi-csv` 文件夹（在 Windows 上，你可能需要允许 Docker 访问你正在工作的驱动器，以便挂载工作）
   - 要求你提供上面提到的车辆 ID
   - 处理 `influxdb-csv` 文件夹中的 CSV 文件。这可能需要几分钟的时间。当转换器处理这些文件时，会显示进度
   - 停止并删除 Docker 容器

   完成的与 TeslaFi 兼容的 CSV 文件现在位于 `teslafi-csv` 文件夹中。

### 第三部分：将处理过的 CSV 数据导入 TeslaMate 中

- 使用你刚刚创建的 CSV 文件继续进行 [TeslaFi 导入](teslafi.md)步骤。
