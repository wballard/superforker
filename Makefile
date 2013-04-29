DIFF ?= git --no-pager diff --ignore-all-space --color-words --no-index
CURL ?= curl --silent

.PHONY: test

test: 
	$(MAKE)	works_with_sockets works_with_watch works_with_static

test_pass:
	DIFF=cp $(MAKE) test

works_with_sockets:
	echo "test('localhost', 8080, '/echo', {'a': 'b'}, ['arg1', 'arg2'])" \
	| ./bin/poke \
	| tee /tmp/$@
	$(DIFF) /tmp/$@ test/expected/$@

works_with_watch:
	echo "test_watch('localhost', 8080, 'test/watch')" \
	| ./bin/poke \
	| tee /tmp/$@
	$(DIFF) /tmp/$@ test/expected/$@

works_with_static:
	curl "http://localhost:8080/hello.txt" \
	| tee /tmp/$@
	$(DIFF) /tmp/$@ test/expected/$@

#Do this in one window, then run make test in another
test_start:
	forever --watch --watchDirectory src bin/superforker 8080 test/handlers test/static
