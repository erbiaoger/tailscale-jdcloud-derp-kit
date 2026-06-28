SHELL := /bin/bash

.PHONY: help install-vps install-mac-cert install-linux-cert derpmap derpmap-fallback verify recover check

help:
	@echo "Targets:"
	@echo "  make install-vps         Install/update derper on VPS"
	@echo "  make install-mac-cert    Install DERP cert into Mac login keychain"
	@echo "  make install-linux-cert  Install DERP cert into lab Linux CA store"
	@echo "  make derpmap             Print force-only DERPMap"
	@echo "  make derpmap-fallback    Print DERPMap with official fallback"
	@echo "  make verify              Verify DERP and SSH"
	@echo "  make recover             Print official DERP recovery steps"
	@echo "  make check               Syntax-check shell scripts"

install-vps:
	bash scripts/vps_install_derper.sh

install-mac-cert:
	bash scripts/mac_install_derp_cert.sh

install-linux-cert:
	bash scripts/linux_install_derp_cert.sh

derpmap:
	bash scripts/generate_derpmap.sh --force-only

derpmap-fallback:
	bash scripts/generate_derpmap.sh --with-fallback

verify:
	bash scripts/verify_derp.sh

recover:
	bash scripts/recover_official_derp.sh

check:
	@for f in scripts/*.sh; do echo "bash -n $$f"; bash -n "$$f"; done
