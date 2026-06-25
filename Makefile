.PHONY: test check check-vita

test:
	bash scripts/verify.sh

check:
	nim check --mm:orc --hints:off --path:src src/raddy.nim

check-vita:
	nim check --mm:arc --hints:off --path:src -d:vita src/raddy.nim
