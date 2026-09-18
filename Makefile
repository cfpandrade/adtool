# Maintainer: Carlos Andrade <carlos@perezandrade.com>
.PHONY: test lint

test:
	./tests/smoke.sh

lint:
	bash -n adtool install.sh tests/smoke.sh
	shellcheck -x adtool install.sh tests/smoke.sh
