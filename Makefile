all: test coverage

build: bin/hace
bin/hace:
	shards build
test:
	shards install
	crystal spec -v --error-trace
coverage: coverage/index.html
bin/crytic:
	rm -rf lib/crytic
	shards install
mutation: bin/crytic
	bin/crytic test -s src/hace.cr
coverage/index.html: bin/run_tests spec/*cr spec/testcases/*/Hacefile.yml
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
	crystal tool format src/*.cr spec/*.cr
	bin/ameba --all --fix
docs:   src/*.cr *.md
	crystal docs

changelog:
	git cliff -o --sort=newest

.PHONY: clean coverage mutation test all build
