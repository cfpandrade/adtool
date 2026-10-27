# Maintainer: Carlos Andrade <carlos@perezandrade.com>
.PHONY: test lint deb clean completions

# the packaged completion scripts are generated from adtool itself
completions:
	./adtool completion bash > contrib/adtool.bash
	./adtool completion zsh > contrib/_adtool

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
