#!/bin/sh

mix ecto.setup
MIX_ENV=test mix ecto.setup

mix phx.server