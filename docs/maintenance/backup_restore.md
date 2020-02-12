# Backup and Restore

## Backup

Create backup file `teslamate.bck`:

```bash
docker-compose exec database pg_dump -U teslamate teslamate > teslamate.bck
```

If you see the error `ERROR: No such service: database`, please update your _docker-compose.yml_ or use `db` instead of `database` in the above command.

## Restore

```bash
# Stop the teslamate container to avoid write conflicts
docker-compose down teslamate

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
```
