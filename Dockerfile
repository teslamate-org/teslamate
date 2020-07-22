FROM elixir:1.10-alpine AS builder

RUN apk add --update --no-cache nodejs npm git build-base python && \
    mix local.rebar --force && \
    mix local.hex --force

ENV MIX_ENV=prod

WORKDIR /opt/app

COPY mix.exs mix.lock ./
COPY config config
RUN mix "do" deps.get --only $MIX_ENV, deps.compile

COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix ./assets --progress=false --no-audit --loglevel=error

COPY assets assets
RUN npm run deploy --prefix ./assets
RUN mix phx.digest

COPY lib lib
COPY priv/repo/migrations priv/repo/migrations
COPY priv/gettext priv/gettext
COPY grafana/dashboards grafana/dashboards

RUN mkdir -p /opt/built && \
    mix "do" compile, release --path /opt/built

########################################################################

FROM alpine:3.12.0 AS app

ENV LANG=C.UTF-8 \
    SRTM_CACHE=/opt/app/.srtm_cache \
    HOME=/opt/app

RUN apk add --no-cache ncurses-libs openssl tini tzdata

WORKDIR $HOME
RUN chown -R nobody:nobody .
USER nobody:nobody

COPY --chown=nobody:nobody entrypoint.sh /
COPY --from=builder --chown=nobody:nobody /opt/built .
RUN mkdir .srtm_cache

EXPOSE 4000

ENTRYPOINT ["/sbin/tini", "--", "/bin/sh", "/entrypoint.sh"]
CMD ["bin/teslamate", "start"]
