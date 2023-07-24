MAKEFLAGS += --warn-undefined-variables --always-make
.DEFAULT_GOAL := _

IMAGE=$(shell docker run -i --rm mikefarah/yq '.env.DOCKER_IMAGE' < .github/workflows/publish.yaml)
IMAGE_TAG=${IMAGE}:$(shell (git describe --tags --exact-match || git symbolic-ref --short HEAD || git rev-parse --short HEAD) | sed 's\/\-\')

exec_docker=docker run $(shell [ "$$CI" = true ] && echo "-t" || echo "-it") -e CI -u "$(shell id -u):$(shell id -g)" --rm -v "$(shell pwd):/app" -w /app

PHP_VERSION=$(shell cat Dockerfile | grep 'FROM php:' | cut -f2 -d':' | cut -f1 -d '-')

lint:
	${exec_docker} hadolint/hadolint hadolint --ignore DL3008 --ignore DL3059 Dockerfile
release: lint
	git fetch --all --prune --tags --prune-tags --force --quiet
	@[ "$$(git status --porcelain)" ] && echo "Commit your changes" && exit 1 || true
	@[ "$$(git log --branches --not --remotes)" ] && echo "Push your commits" && exit 1 || true
	@[ "$$(git describe --tags --abbrev=0 --exact-match)" ] && echo "Commit already tagged" && exit 1 || true
	git tag "${PHP_VERSION}-$$(($(shell git describe --tags --abbrev=0 | cut -f2 -d '-') + 1))"
	@read -p "Continue? (y/N) " REPLY && [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ] || exit
	git push --tags
build: lint
	docker buildx build --load --tag "${IMAGE_TAG}" .
cli: clean build
	docker run -it --rm "${IMAGE_TAG}" bash
clean:
	docker rm $(shell docker ps -aq -f "ancestor=${IMAGE_TAG}") --force || true
	docker rmi $(shell docker images -q "${IMAGE}") --force || true
test: build
	docker run --rm "${IMAGE_TAG}" php -v
	docker run --rm "${IMAGE_TAG}" php -m | paste -sd ","
