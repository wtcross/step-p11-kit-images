SHELL := /bin/bash

include versions.env

BATS ?= bats

REGISTRY ?= ghcr.io
OWNER ?= wtcross

STEP_CA_IMAGE ?= $(REGISTRY)/$(OWNER)/step-ca-p11-kit
SOFTHSM_IMAGE ?= $(REGISTRY)/$(OWNER)/softhsm2-p11-kit
STEP_TEST_INIT_IMAGE ?= $(REGISTRY)/$(OWNER)/step-ca-p11-kit-test-init
SYSTEMD_TESTING_IMAGE ?= $(REGISTRY)/$(OWNER)/step-ca-p11-kit-systemd-testing
STEP_CLI_IMAGE ?= docker.io/smallstep/step-cli:latest

UNIT_TEST_LOGS_PATH ?= $(shell realpath -m tests/unit/logs)
FUNCTIONAL_TEST_LOGS_PATH ?= $(shell realpath -m tests/functional/logs)
SYSTEMD_TEST_IMAGE_TAR_DIR ?= $(shell realpath -m .tmp/image-tars)
SYSTEMD_TEST_RUNTIME_DIR ?= $(shell realpath -m .tmp/systemd-testing)
SYSTEMD_TEST_INSTANCE ?= test

.PHONY: build-step-ca build-softhsm build-test-init build-systemd-testing build-all build-systemd-testing-stack save-systemd-testing-image-tars run-systemd-testing test test-unit test-functional
build-step-ca:
	@podman build \
		--build-arg STEP_CA_VERSION=$(STEP_CA_VERSION) \
		--build-arg STEP_CLI_VERSION=$(STEP_CLI_VERSION) \
		--build-arg P11_KIT_VERSION=$(P11_KIT_VERSION) \
		--build-arg DEBIAN_TRIXIE_DIGEST=$(DEBIAN_TRIXIE_DIGEST) \
		-t $(STEP_CA_IMAGE):latest \
		-f images/step-ca-p11-kit/Containerfile .

build-softhsm:
	@podman build \
		--build-arg P11_KIT_VERSION=$(P11_KIT_VERSION) \
		--build-arg DEBIAN_TRIXIE_DIGEST=$(DEBIAN_TRIXIE_DIGEST) \
		-t $(SOFTHSM_IMAGE):latest \
		-f images/softhsm2-p11-kit/Containerfile .

build-test-init:
	@podman build \
		--build-arg P11_KIT_VERSION=$(P11_KIT_VERSION) \
		-t $(STEP_TEST_INIT_IMAGE):latest \
		-f images/step-ca-p11-kit-test-init/Containerfile .

build-systemd-testing:
	@podman build \
		--build-arg P11_KIT_VERSION=$(P11_KIT_VERSION) \
		--build-arg DEBIAN_TRIXIE_DIGEST=$(DEBIAN_TRIXIE_DIGEST) \
		-t $(SYSTEMD_TESTING_IMAGE):latest \
		-f images/step-ca-p11-kit-systemd-testing/Containerfile .

build-all: build-step-ca build-softhsm build-test-init build-systemd-testing

build-systemd-testing-stack: build-all build-systemd-testing

save-systemd-testing-image-tars: build-all
	@./scripts/save-systemd-testing-image-tars.sh \
		--tar-dir "$(SYSTEMD_TEST_IMAGE_TAR_DIR)" \
		--step-ca-image "$(STEP_CA_IMAGE):latest" \
		--softhsm-image "$(SOFTHSM_IMAGE):latest" \
		--step-test-init-image "$(STEP_TEST_INIT_IMAGE):latest"

run-systemd-testing: build-systemd-testing save-systemd-testing-image-tars
	@./scripts/run-systemd-testing-container.sh \
		--image "$(SYSTEMD_TESTING_IMAGE):latest" \
		--image-tar-dir "$(SYSTEMD_TEST_IMAGE_TAR_DIR)" \
		--runtime-dir "$(SYSTEMD_TEST_RUNTIME_DIR)" \
		--instance "$(SYSTEMD_TEST_INSTANCE)" \
		--step-ca-image "$(STEP_CA_IMAGE):latest" \
		--softhsm-image "$(SOFTHSM_IMAGE):latest" \
		--step-test-init-image "$(STEP_TEST_INIT_IMAGE):latest"

test: build-all test-unit test-functional

test-unit: build-all
	@mkdir -p $(UNIT_TEST_LOGS_PATH)
	@bash -c 'set -euo pipefail; \
		command -v "$(BATS)" >/dev/null 2>&1 || { echo "bats is required"; exit 1; }; \
		mapfile -t suites < <(find tests/unit -type f -name "*.bats" | sort); \
		[ $${#suites[@]} -gt 0 ] || { echo "No unit test suites found"; exit 1; }; \
		for suite in "$${suites[@]}"; do \
			name="$$(basename "$$suite" .bats)"; \
			suite_label="unit/$${name}.bats"; \
			log_file="$(UNIT_TEST_LOGS_PATH)/$${name}.log"; \
			echo "[unit tests] running $${suite_label}"; \
			"$(BATS)" --formatter tap "$$suite" 2>&1 | tee "$$log_file"; \
			echo; \
		done'

test-functional: build-all
	@mkdir -p $(FUNCTIONAL_TEST_LOGS_PATH)
	@bash -c 'set -euo pipefail; \
		command -v "$(BATS)" >/dev/null 2>&1 || { echo "bats is required"; exit 1; }; \
		shopt -s nullglob; \
		suites=(tests/functional/images/*.bats); \
		[ $${#suites[@]} -gt 0 ] || { echo "No functional test suites found"; exit 1; }; \
		for suite in "$${suites[@]}"; do \
			name="$$(basename "$$suite" .bats)"; \
			suite_label="functional/$${name}.bats"; \
			log_file="$(FUNCTIONAL_TEST_LOGS_PATH)/$${name}.log"; \
			echo "[functional tests] running $${suite_label}"; \
			SOFTHSM_TEST_IMAGE="$(SOFTHSM_IMAGE):latest" \
			STEP_CA_INIT_TEST_IMAGE="$(STEP_TEST_INIT_IMAGE):latest" \
			STEP_CA_TEST_IMAGE="$(STEP_CA_IMAGE):latest" \
			"$(BATS)" --formatter tap "$$suite" 2>&1 | tee "$$log_file"; \
			echo; \
		done'
