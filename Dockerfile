FROM elixir:1.9-alpine AS builder

RUN apk add --update --no-cache nodejs yarn git build-base python && \
    mix local.rebar --force && \
    mix local.hex --force

ENV MIX_ENV=prod

WORKDIR /opt/app

COPY mix.exs mix.lock ./
RUN mix do deps.get --only $MIX_ENV, deps.compile

COPY assets assets
RUN (cd assets && yarn install && yarn deploy)

COPY config config
COPY lib lib
COPY priv priv

RUN mix do phx.digest, compile

RUN mkdir -p /opt/built && mix release --path /opt/built

########################################################################

FROM alpine:3.9 AS app

ENV LANG=C.UTF-8 \
    SRTM_CACHE=/opt/app/.srtm_cache

RUN apk add --update --no-cache bash openssl tzdata

WORKDIR /opt/app

COPY --chown=nobody entrypoint.sh /
COPY --from=builder --chown=nobody /opt/built .
RUN mkdir .srtm_cache && chown -R nobody: .

USER nobody

EXPOSE 4000

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]

CMD ["bin/teslamate", "start"]
