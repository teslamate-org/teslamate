# Upgrading to a new version

## Docker Containers

1. Check out the [Changelog](/CHANGELOG.md) before upgrading!

2. Ensure your credentials are correct in `docker-compose.yml` (or `.env` if you are using [Docker (advanced)](docs/installation/docker_advanced.md))

3. Pull the new images and restart the stack:

```bash
docker-compose pull

docker-compose up
```

3. Log in and check

## Manual Installation

1. Check out the [Changelog](/CHANGELOG.md) before upgrading!

2. Pull the new changes from the git repository, checkout the new version and then build the new release:

   ```bash
   git pull
   git checkout $(git describe --tags)

   mix deps.get --only prod
   npm install --prefix ./assets && npm run deploy --prefix ./assets
   mix phx.digest
   MIX_ENV=prod mix release
   ```

3. Most upgrades requires to run new database migrations. If so continue with the following command:

   ```bash
    _build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
   ```

4. Finally, re-import the dashboards.
