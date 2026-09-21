.PHONY: help vsn grafana teslamate check

APP_NAME ?= `grep 'app:' elixir/mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
APP_VSN ?= `cat VERSION`
BUILD ?= `git rev-parse --short HEAD`

help: vsn
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

check: ## Verify VERSION and Cargo.toml are in sync
	@version=$$(cat VERSION); \
	cargo_version=$$(grep '^version = ' rust/Cargo.toml | sed 's/version = "\(.*\)"/\1/'); \
	if [ "$$version" != "$$cargo_version" ]; then \
		echo "Version mismatch: VERSION='$$version' rust/Cargo.toml='$$cargo_version'"; \
		exit 1; \
	fi
	@echo "Versions in sync: $(APP_VSN)"

vsn:
	@echo "$(APP_NAME):$(APP_VSN)-$(BUILD)"

teslamate: vsn ## Build teslamate Docker image
	@docker build --pull \
			-t $(APP_NAME):$(APP_VSN)-$(BUILD) \
			-t $(APP_NAME) .

grafana: vsn ## Build  teslamate-grafana Docker image
	@docker build --pull -f grafana/Dockerfile -t teslamate-grafana .
