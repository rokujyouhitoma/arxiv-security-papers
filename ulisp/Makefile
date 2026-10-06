.PHONY: test bootstrap clean run_42

CC = gcc
CFLAGS = -Wall -Wextra -O0 -g
ILISP = python3 -m ilisp
ROOT_DIR = $(shell dirname $(CURDIR))

test:
	./test.sh

bootstrap:
	./bootstrap.sh

run_42:
	@echo "42" | PYTHONPATH=$(ROOT_DIR) $(ILISP) compiler.scm > tmp.s
	@$(CC) $(CFLAGS) -o tmp runtime.c tmp.s
	@./tmp
	@rm -f tmp tmp.s

clean:
	rm -f tmp tmp_bin *.s *.o
	rm -rf build
