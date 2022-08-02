---
title: 从TeslaFi导入（BETA）
sidebar_label: TeslaFi
---

## 要求

- **创建一个[备份](../maintenance/backup_restore.md)的数据‼️**

- 如果你从 1.16 版本之前就开始使用 TeslaMate，则需要更新 [docker-compose.yml](../installation/docker.md)。在 `teslamate` 服务中添加以下卷映射：

  ```yml {4-5}
  services:
    teslamate:
      # ...
      volumes:
        - ./import:/opt/app/import
  ```

- 按月将你的 TeslaFi 数据（一辆车）导出为 CSV。 `Settings -> Account -> Download TeslaFi Data`.
  - 如果你有大量的 TeslaFi 数据，并且不想处理用户界面，你可以运行这个 python 脚本来导出所有数据：[Export from TeslaFi #563](https://github.com/adriankumpf/teslamate/issues/563)

## 步骤

1. 将导出的 CSV 文件复制到 _docker-compose.yml_ 旁边的一个**名为 `import` 的目录中**。

   ```console
   .
   ├── docker-compose.yml
   └── import
       ├── TeslaFi82019.csv
       ├── TeslaFi92019.csv
       ├── TeslaFi102019.csv
       ├── TeslaFi112019.csv
       └── TeslaFi122019.csv
   ```

   :::tip
   导入目录的路径可以通过 **IMPORT_DIR** [环境变量](../configuration/environment_variables.md)来定制。
   :::

2. **重新启动** teslamate 服务并打开 TeslaMate 管理界面。现在应该显示导入表格而不是车辆摘要。
3. 由于原始数据是在本地时区（由 TeslaFi 设置页面中的家庭地址分配），你需要**选择你的本地时区**。然后开始导入。在树莓派这样的低端硬件上，导入一个跨越几年的大数据集需要几个小时。
4. 导入完成后，**清空 `import` 目录**（或删除，但确保 docker 没有卷映射），**重新启动** `teslamate` 服务。

:::note
如果已经存在的 TeslaMate 和 TeslaFi 数据之间有重叠，那么只有第一个 TeslaMate 数据之前的数据会被导入。
:::

:::note
由于导出的 CSV 文件不包含地址，它们是在导入期间和之后自动添加的。所以请注意，并不是所有的地址在导入或重新启动后都能立即看到。取决于导入的数据量，可能需要一段时间才能出现。这同样适用于海拔数据。
:::
