FROM erlang:23-alpine AS builder

ENV ELIXIR_VERSION="v1.11.1" \
   LANG=C.UTF-8

RUN set -xe \
  && ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz" \
  && ELIXIR_DOWNLOAD_SHA256="724774eb685b476a42c838ac8247787439913667fe023d2f1ed9c933d08dc57c" \
  && buildDeps=' \
    ca-certificates \
    curl \
    make \
  ' \
  && apk add --no-cache --virtual .build-deps $buildDeps \
  && curl -fSL -o elixir-src.tar.gz $ELIXIR_DOWNLOAD_URL \
  && echo "$ELIXIR_DOWNLOAD_SHA256  elixir-src.tar.gz" | sha256sum -c - \
  && mkdir -p /usr/local/src/elixir \
  && tar -xzC /usr/local/src/elixir --strip-components=1 -f elixir-src.tar.gz \
  && rm elixir-src.tar.gz \
  && cd /usr/local/src/elixir \
  && make install clean \
  && apk del .build-deps

RUN apk add --update --no-cache nodejs npm git build-base && \
    mix local.rebar --force && \
    mix local.hex --force

ENV MIX_ENV=prod

WORKDIR /opt/app

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY config config
RUN mix deps.compile

COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix ./assets --progress=false --no-audit --loglevel=error

COPY assets assets
RUN npm run deploy --prefix ./assets
RUN mix phx.digest

COPY lib lib
COPY priv/repo/migrations priv/repo/migrations
COPY priv/gettext priv/gettext
COPY grafana/dashboards grafana/dashboards
COPY VERSION VERSION

RUN mkdir -p /opt/built && \
    mix "do" compile, release --path /opt/built

########################################################################

FROM alpine:3.12.1 AS app

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
