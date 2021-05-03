FROM erlang:24 AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV ELIXIR_VERSION="v1.12.0-rc.1" \
    LANG=C.UTF-8

RUN set -xe \
    && ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz" \
    && ELIXIR_DOWNLOAD_SHA256="f04142fb0a6c3f27a342109308085aaa75b95dbf4782d9c7be12446150b2b4be" \
    && curl -fSL -o elixir-src.tar.gz $ELIXIR_DOWNLOAD_URL \
    && echo "$ELIXIR_DOWNLOAD_SHA256  elixir-src.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/local/src/elixir \
    && tar -xzC /usr/local/src/elixir --strip-components=1 -f elixir-src.tar.gz \
    && rm elixir-src.tar.gz \
    && cd /usr/local/src/elixir \
    && make install clean

RUN apt-get update && apt-get install -y --no-install-recommends \ 
    curl ca-certificates git

RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
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
RUN npm run deploy --prefix ./assets
RUN mix phx.digest

COPY lib lib
COPY priv/repo/migrations priv/repo/migrations
COPY priv/gettext priv/gettext
COPY grafana/dashboards grafana/dashboards
COPY VERSION VERSION
RUN mix compile

COPY config/runtime.exs config/runtime.exs
RUN mix release --path /opt/built

########################################################################

FROM debian:buster-slim AS app

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
