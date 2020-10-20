.PHONY: help vsn grafana teslamate

APP_NAME ?= `grep 'app:' mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
APP_VSN ?= `cat VERSION`
BUILD ?= `git rev-parse --short HEAD`

help: vsn
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

vsn:
	@echo "$(APP_NAME):$(APP_VSN)-$(BUILD)"

teslamate: vsn ## Build teslamate Docker image
	@docker build --pull \
			-t $(APP_NAME):$(APP_VSN)-$(BUILD) \
			-t $(APP_NAME) .

grafana: vsn ## Build  teslamate-grafana Docker image
	@cd grafana && docker build --pull -t teslamate-grafana .
