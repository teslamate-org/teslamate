FROM elixir:1.8-alpine AS builder

ARG APP_NAME
ARG APP_VSN

ENV APP_NAME=${APP_NAME} \
    APP_VSN=${APP_VSN} \
    MIX_ENV=prod

WORKDIR /opt/app

RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache nodejs yarn git build-base && \
    mix local.rebar --force && \
    mix local.hex --force

COPY mix.* ./
RUN mix do deps.get --only $MIX_ENV, deps.compile

COPY assets assets
RUN cd assets && \
  yarn install && \
  yarn deploy && \
  cd ..

COPY . .
RUN mix do phx.digest, compile

RUN \
  mkdir -p /opt/built && \
  mix release && \
  cp _build/${MIX_ENV}/rel/${APP_NAME}/releases/${APP_VSN}/${APP_NAME}.tar.gz /opt/built && \
  cd /opt/built && \
  tar -xzf ${APP_NAME}.tar.gz && \
  rm ${APP_NAME}.tar.gz

########################################################################

FROM alpine:3.9

ENV LANG=en_US.UTF-8 \
    TZ=Europe/Berlin \
    TERM=xterm

ARG APP_NAME

RUN apk update && \
    apk --no-cache upgrade && \
    apk add --no-cache bash openssl-dev erlang-crypto

ENV REPLACE_OS_VARS=true \
    APP_NAME=${APP_NAME}

WORKDIR /opt/app

RUN addgroup -g 4005 $APP_NAME && \
    adduser -u 4005 -D -h . -G $APP_NAME $APP_NAME

USER $APP_NAME

COPY --from=builder /opt/built .

CMD trap 'exit' INT; /opt/app/bin/${APP_NAME} foreground
