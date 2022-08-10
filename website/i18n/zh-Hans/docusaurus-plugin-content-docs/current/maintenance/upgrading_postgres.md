---
title: 将 PostgreSQL 升级到一个新的主要版本
sidebar_label: 升级 PostgreSQL
---

1. 创建一个[备份](backup_restore.md)
2. 停止所有 TeslaMate 容器

   ```bash
   docker-compose down
   ```

3. 删除数据库卷。**小心**，这将删除你以前记录的所有数据！在你开始之前，请确保你的备份可以被恢复。

   ```bash
   docker volume rm "$(basename "$PWD")_teslamate-db"
   ```

4. 在 docker-compose.yml 中改变 postgres 的版本并启动容器

   ```yml {2}
   database:
     image: postgres:xx
   ```

   ```bash
   docker-compose up -d database
   ```

5. [还原](backup_restore.md)备份
