.PHONY: build push

BUILDVERSION ?= latest
DOCKERUSER ?= goeshere


build:
	DOCKER_DEFAULT_PLATFORM=linux/amd64 docker buildx build --load --platform linux/amd64 . -t $(DOCKERUSER)/mastodon:$(BUILDVERSION)

push:
	docker push  $(DOCKERUSER)/mastodon:$(BUILDVERSION)
