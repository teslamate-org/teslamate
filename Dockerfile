FROM elixir:1.14.1 AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - && \
    apt-get update && apt-get install -y --no-install-recommends nodejs

RUN mix local.rebar --force && \
    mix local.hex --force

ENV MIX_ENV=prod
WORKDIR /opt/app

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY config/$MIX_ENV.exs config/$MIX_ENV.exs
COPY config/config.exs config/config.exs
RUN mix deps.compile

COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix ./assets --progress=false --no-audit --loglevel=error

COPY assets assets
COPY priv/static priv/static
RUN mix assets.deploy

COPY lib lib
COPY priv/repo/migrations priv/repo/migrations
COPY priv/gettext priv/gettext
COPY grafana/dashboards grafana/dashboards
COPY VERSION VERSION
RUN mix compile

COPY config/runtime.exs config/runtime.exs
RUN SKIP_LOCALE_DOWNLOAD=true mix release --path /opt/built

########################################################################

FROM debian:bullseye-slim AS app

ENV LANG=C.UTF-8 \
    SRTM_CACHE=/opt/app/.srtm_cache \
    HOME=/opt/app

WORKDIR $HOME

RUN apt-get update && apt-get install -y --no-install-recommends \
        libodbc1  \
        libsctp1  \
        libssl1.1  \
        libstdc++6 \
        netcat \
        tini  \
        tzdata && \
    rm -rf /var/lib/apt/lists/* && \
    addgroup --gid 10001 --system nonroot && \
    adduser  --uid 10000 --system --ingroup nonroot --home /home/nonroot nonroot && \
    chown -R nonroot:nonroot .

USER nonroot:nonroot
COPY --chown=nonroot:nonroot entrypoint.sh /
COPY --from=builder --chown=nonroot:nonroot /opt/built .
RUN mkdir $SRTM_CACHE

EXPOSE 4000

ENTRYPOINT ["tini", "--", "/bin/sh", "/entrypoint.sh"]
CMD ["bin/teslamate", "start"]
