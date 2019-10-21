# Upgrading to a new version

> Check out the [Changelog](/CHANGELOG.md) before upgrading!

## Docker Containers

Pull the new images and restart the stack:

```bash
docker-compose pull

docker-compose up
```

## Manual Installation

1. Pull the new changes from the git repository, checkout the new version and then build the new release:

   ```bash
   git pull
   git checkout $(git describe --tags)

   mix deps.get --only prod
   npm install --prefix ./assets && npm run deploy --prefix ./assets
   mix phx.digest
   MIX_ENV=prod mix release
   ```

2. Most upgrades requires to run new database migrations. If so continue with the following command:

   ```bash
    _build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
   ```

3. Finally, re-import the dashboards.
