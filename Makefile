# Maintainer: Carlos Andrade <carlos@perezandrade.com>
.PHONY: test lint deb clean

test:
	./tests/smoke.sh
	./tests/installer.sh

lint:
	bash -n adtool install.sh tests/smoke.sh tests/installer.sh contrib/adtool.bash
	shellcheck -x adtool install.sh tests/smoke.sh tests/installer.sh contrib/adtool.bash

deb: test lint
	dpkg-buildpackage -us -uc -b

clean:
	dh_clean
