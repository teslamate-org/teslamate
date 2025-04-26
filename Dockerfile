FROM elixir:1.17.3-otp-26 AS builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
     | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && NODE_MAJOR=20 \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" \
     | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install nodejs -y \
    && apt-get install -y git \
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

FROM debian:bookworm-slim AS app

ENV LANG=C.UTF-8 \
    SRTM_CACHE=/opt/app/.srtm_cache \
    HOME=/opt/app

WORKDIR $HOME

RUN apt-get update && apt-get install -y --no-install-recommends \
        libodbc1  \
        libsctp1  \
        libssl3  \
        libstdc++6 \
        netcat-openbsd \
        tini  \
        tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    addgroup --gid 10001 --system nonroot && \
    adduser  --uid 10000 --system --ingroup nonroot --home /home/nonroot nonroot && \
    chown -R nonroot:nonroot .

USER nonroot:nonroot
COPY --chown=nonroot:nonroot --chmod=555 entrypoint.sh /
COPY --from=builder --chown=nonroot:nonroot --chmod=555 /opt/built .
RUN mkdir $SRTM_CACHE

EXPOSE 4000

ENTRYPOINT ["tini", "--", "/bin/sh", "/entrypoint.sh"]
CMD ["bin/teslamate", "start"]
