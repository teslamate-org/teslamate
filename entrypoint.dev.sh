#!/bin/sh

mix deps.get
npm install --prefix ./assets/

mix ecto.setup
MIX_ENV=test mix ecto.setup

mix phx.server