---
title: 备份和还原
---

## 备份

创建备份文件 `teslamate.bck`：

```bash
docker-compose exec -T database pg_dump -U teslamate teslamate > /backuplocation/teslamate.bck
```

:::note
如果你在 crontab 中加入这一行，那么 `T` 是很重要的，否则备份将无法工作，因为 docker 会产生这样的错误 `the input device is not a TTY`
:::

:::note
一定要把 `teslamate.bck` 文件移到另一个安全的地方，因为如果你使用 docker-compose GUI 来升级你的 teslamate 配置，可能会丢失这个备份文件。有些 GUI 在更新时删除了存放 `docker-compose.yml` 的文件夹。
:::

:::note
如果你得到错误 `No such service: database`，请更新你的 _docker-compose.yml_ 或在上述命令中使用 `db` 而不是 `database`。
:::

:::note
如果你从某个高级指南中改变了 .env 文件中的 `TM_DB_USER`，请确保将上述命令中的第一个 `teslamate` 实例替换为 `TM_DB_USER` 的值。
:::

## 还原

:::note
如果你有 .env 文件（TM_DB_USER 和 TM_DB_NAME），用该文件中定义的值替换下面默认的 `teslamate` 值。
:::

```bash
# Stop the teslamate container to avoid write conflicts
docker-compose stop teslamate

# Drop existing data and reinitialize
docker-compose exec -T database psql -U teslamate << .
drop schema public cascade;
create schema public;
create extension cube;
create extension earthdistance;
CREATE OR REPLACE FUNCTION public.ll_to_earth(float8, float8)
    RETURNS public.earth
    LANGUAGE SQL
    IMMUTABLE STRICT
    PARALLEL SAFE
    AS 'SELECT public.cube(public.cube(public.cube(public.earth()*cos(radians(\$1))*cos(radians(\$2))),public.earth()*cos(radians(\$1))*sin(radians(\$2))),public.earth()*sin(radians(\$1)))::public.earth';
.

# Restore
docker-compose exec -T database psql -U teslamate -d teslamate < teslamate.bck

# Restart the teslamate container
docker-compose start teslamate
```
