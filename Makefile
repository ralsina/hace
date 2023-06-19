all: test coverage

test:
	shards install
	crystal spec -v --error-trace
coverage: coverage/index.html
bin/crytic:
	rm -rf lib/crytic
	shards install
mutation: bin/crytic
	bin/crytic test -s src/hace.cr
coverage/index.html: bin/run_tests
	rm -rf coverage/
	kcov --clean --include-path=./src coverage ./bin/run_tests
	xdg-open coverage/index.html
bin/run_tests: src/*.cr spec/*.cr
	shards install
	crystal build -o bin/run_tests src/run_tests.cr
clean:
	rm -rf lib/ bin/ coverage/
	git clean -f
lint:
	ameba --all --fix
docs:   src/*.cr *.md
	crystal docs
.PHONY: clean coverage mutation test all
