.PHONY: help vsn grafana teslamate

APP_NAME ?= `grep 'app:' elixir/mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
APP_VSN ?= `cat VERSION`
# Full commit hash, -dirty if git status reports anything (untracked files included)
REVISION := $(shell rev=$$(git rev-parse --verify HEAD) && st=$$(git --no-optional-locks status --porcelain) && echo "$$rev$${st:+-dirty}")

help: vsn
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

vsn:
	@echo "$(APP_NAME):$(APP_VSN)-$(REVISION)"

teslamate: vsn ## Build teslamate Docker image
	@docker build --pull \
			--build-arg TESLAMATE_REVISION=$(REVISION) \
			-t $(APP_NAME):$(APP_VSN)-$(REVISION) \
			-t $(APP_NAME) .

grafana: vsn ## Build  teslamate-grafana Docker image
	@docker build --pull -f grafana/Dockerfile -t teslamate-grafana .
