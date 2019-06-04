# FROM elixir:1.9-alpine AS builder

# begin custom Elixir image
FROM erlang:21-alpine as builder

# elixir expects utf8.
ENV ELIXIR_VERSION="v1.9.0-rc.0" \
    LANG=C.UTF-8

RUN set -xe \
  && ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz" \
  && ELIXIR_DOWNLOAD_SHA256="fa019ba18556f53bfb77840b0970afd116517764251704b55e419becb0b384cf" \
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
# end cusom Elixir image

RUN apk add --update --no-cache nodejs yarn git build-base && \
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

COPY . .
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

CMD trap 'exit' INT; /opt/app/bin/teslamate start
