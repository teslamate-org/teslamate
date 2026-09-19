FROM elixir:1.20.2-otp-29 AS builder

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
WORKDIR /opt/app/elixir

COPY elixir/mix.exs elixir/mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY elixir/config/$MIX_ENV.exs config/$MIX_ENV.exs
COPY elixir/config/config.exs config/config.exs
RUN mix deps.compile

COPY elixir/assets/package.json elixir/assets/package-lock.json ./assets/
RUN npm ci --prefix ./assets --progress=false --no-audit --loglevel=error

COPY elixir/assets assets
COPY elixir/priv/static priv/static
RUN mix assets.deploy

COPY elixir/lib lib
COPY elixir/priv/repo/migrations priv/repo/migrations
COPY elixir/priv/gettext priv/gettext
COPY grafana/dashboards ../grafana/dashboards
COPY VERSION ../VERSION
RUN mix compile

COPY elixir/config/runtime.exs config/runtime.exs
RUN mix release --path /opt/built

########################################################################

FROM debian:trixie-slim AS app

ENV LANG=C.UTF-8 \
    SRTM_CACHE=/opt/app/.srtm_cache \
    HOME=/opt/app

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
RUN mkdir $SRTM_CACHE

EXPOSE 4000

ENTRYPOINT ["tini", "--", "/bin/dash", "/entrypoint.sh"]
CMD ["bin/teslamate", "start"]
