FROM elixir:1.9-alpine AS builder

RUN apk add --update --no-cache nodejs yarn git build-base python && \
    mix local.rebar --force && \
    mix local.hex --force

ENV MIX_ENV=prod

WORKDIR /opt/app

COPY mix.exs mix.lock ./
RUN mix do deps.get --only $MIX_ENV, deps.compile

COPY assets assets
RUN cd assets && \
  yarn install && \
  yarn deploy && \
  cd ..

COPY config config
COPY lib lib
COPY priv priv

RUN mix do phx.digest, compile

RUN mkdir -p /opt/built && mix release --path /opt/built

########################################################################

FROM alpine:3.9 AS app

ENV LANG=C.UTF-8 \
    TZ=Europe/Berlin

RUN apk add --update --no-cache bash openssl

WORKDIR /opt/app

COPY --from=builder /opt/built .
RUN chown -R nobody: .

USER nobody

EXPOSE 4000

CMD trap 'exit' INT; bin/teslamate start
