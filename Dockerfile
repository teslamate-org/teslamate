FROM elixir:1.19.5-otp-28 AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y ca-certificates curl gnupg brotli \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
     | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && NODE_MAJOR=22 \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" \
     | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install nodejs -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

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

FROM debian:trixie-slim AS app

ARG TESLAMATE_BUILD_DATE
ARG TESLAMATE_BUILD_REF
ARG TESLAMATE_BUILD_REVISION
ARG TESLAMATE_BUILD_SOURCE

ENV LANG=C.UTF-8 \
    SRTM_CACHE=/opt/app/.srtm_cache \
    HOME=/opt/app \
    TESLAMATE_BUILD_DATE=${TESLAMATE_BUILD_DATE} \
    TESLAMATE_BUILD_REF=${TESLAMATE_BUILD_REF} \
    TESLAMATE_BUILD_REVISION=${TESLAMATE_BUILD_REVISION} \
    TESLAMATE_BUILD_SOURCE=${TESLAMATE_BUILD_SOURCE}

WORKDIR $HOME

RUN apt-get update && apt-get install -y --no-install-recommends \
        libodbc2 \
        libsctp1 \
        libssl3t64 \
        libstdc++6 \
        netcat-openbsd \
        tini \
        tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 --system nonroot \
    && useradd  --uid 10000 --system --gid nonroot --home-dir /home/nonroot --shell /sbin/nologin nonroot \
    && chown -R nonroot:nonroot .

USER nonroot:nonroot
COPY --chown=nonroot:nonroot --chmod=555 entrypoint.sh /
COPY --from=builder --chown=nonroot:nonroot --chmod=555 /opt/built .
RUN mkdir -p "$SRTM_CACHE" data/logs

EXPOSE 4000

ENTRYPOINT ["tini", "--", "/bin/dash", "/entrypoint.sh"]
CMD ["bin/teslamate", "start"]
