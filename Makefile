.PHONY: build push lint lint-ruby rubocop lint-js lint-css format format-check

BUILDVERSION ?= latest
DOCKERUSER ?= goeshere

# Docker image versions (must match Dockerfile)
RUBY_VERSION = 3.4.7
NODE_VERSION = 24

# Build and push targets
build:
	DOCKER_DEFAULT_PLATFORM=linux/amd64 docker buildx build --load --platform linux/amd64 . -t $(DOCKERUSER)/mastodon:$(BUILDVERSION)

push:
	docker push  $(DOCKERUSER)/mastodon:$(BUILDVERSION)

# Linting targets using Docker (no local Ruby/Node installation required)

# Ruby linting with Rubocop
rubocop:
	@echo "Running Rubocop via Docker (Ruby $(RUBY_VERSION))..."
	docker run --rm -v $$(pwd):/app -w /app ruby:$(RUBY_VERSION)-slim-trixie sh -c \
	  "apt-get update -qq && apt-get install -y -qq build-essential git > /dev/null 2>&1 && \
	   gem install --silent rubocop rubocop-rails rubocop-rspec rubocop-rspec_rails rubocop-capybara rubocop-performance rubocop-i18n && \
	   rubocop"

lint-ruby: rubocop

# JavaScript/TypeScript linting with ESLint
lint-js:
	@echo "Running ESLint via Docker (Node $(NODE_VERSION))..."
	docker run --rm -v $$(pwd):/app -w /app node:$(NODE_VERSION)-trixie-slim sh -c \
	  "corepack enable && yarn install --immutable --silent && \
	   yarn lint:js"

# CSS linting with Stylelint
lint-css:
	@echo "Running Stylelint via Docker (Node $(NODE_VERSION))..."
	docker run --rm -v $$(pwd):/app -w /app node:$(NODE_VERSION)-trixie-slim sh -c \
	  "corepack enable && yarn install --immutable --silent && \
	   yarn lint:css"

# Prettier format check (read-only)
format-check:
	@echo "Checking formatting with Prettier via Docker (Node $(NODE_VERSION))..."
	docker run --rm -v $$(pwd):/app -w /app node:$(NODE_VERSION)-trixie-slim sh -c \
	  "corepack enable && yarn install --immutable --silent && \
	   yarn format:check"

# Prettier format (writes changes to files)
format:
	@echo "Formatting files with Prettier via Docker (Node $(NODE_VERSION))..."
	docker run --rm -v $$(pwd):/app -w /app node:$(NODE_VERSION)-trixie-slim sh -c \
	  "corepack enable && yarn install --immutable --silent && \
	   yarn format"

# Run all linters (convenience target for pre-commit checks)
lint: lint-ruby lint-js lint-css format-check
	@echo ""
	@echo "✅ All linting checks passed!"
