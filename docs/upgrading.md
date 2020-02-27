# Upgrading to a new version

## Docker

1. Check out the [Changelog](https://github.com/adriankumpf/teslamate/releases) before upgrading!

2. Ensure your credentials are correct in `docker-compose.yml` (or `.env` if you are using [Docker (advanced)](installation/docker_advanced))

3. Pull the new images and restart the stack:

   ```bash
   docker-compose pull
   docker-compose up
   ```

## Manual Installation

1. Check out the [Changelog](https://github.com/adriankumpf/teslamate/releases) before upgrading!

2. Pull the new changes from the git repository, checkout the new version and then build the new release:

   ```bash
   git pull
   git checkout $(git describe --tags `git rev-list --tags --max-count=1`)

   mix deps.get --only prod
   npm install --prefix ./assets && npm run deploy --prefix ./assets

   MIX_ENV=prod mix do phx.digest, release --overwrite
   ```

3. Most upgrades requires to run new database migrations. If so continue with the following command:

   ```bash
    _build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
   ```

4. Finally, re-import the Grafana dashboards:

   ```bash
   LOGIN="user:pass" ./grafana/dashboards.sh restore
    ```
