.PHONY: test verify check check-vita

test verify:
	./scripts/verify.sh

# Quick single-file checks delegate to nimble tasks (canonical flag source).
check:
	nimble check

check-vita:
	nimble check_vita
