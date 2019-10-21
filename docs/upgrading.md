# Upgrading to a new version

> Check out the [Changelog](/CHANGELOG.md) before upgrading!

## Instructions

    Export the environment variable DATABASE_URL if not already done
    Disconnect all users by flushing all sessions: miniflux -flush-sessions
    Stop the process
    Backup your database
    Check that your backup is really working
    Run database migrations: miniflux -migrate
    Start the process again

## Debian Systems

Follow instructions mentioned above and run: dpkg -i miniflux_2.x.x_amd64.deb.

## RPM Systems

Follow instructions mentioned above and run: rpm -Uvh miniflux-2.x.x-1.0.x86_64.rpm.

## Docker Containers

    Pull the new image with the new tag: docker pull miniflux/miniflux:2.x.x
    Stop and remove the old container: docker stop <container_name> && docker rm <container_name>
    Start a new container with the latest tag: docker run -d -p 80:8080 miniflux/miniflux:2.x.x

If you use Docker Compose, define the new tag in the YAML file and restart the container. Do not forget to run the database migrations if necessary.

## Upgrading to a new version

Pull the new changes from the git repository, checkout the new version and then build the new release as described [above](#compile-elixir-project).

If an upgrade requires to run new database migrations continue with the following command:

```bash
 _build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
```

Finally, re-import the dashboards.
