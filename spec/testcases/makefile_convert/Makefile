CC = gcc
TARGET = hello

hello: main.o
	$(CC) -o $@ $^

main.o: sources/main.c
	@echo compiling $<
	$(CC) -c $<

.PHONY: greet
greet:
	echo "hello from converted Makefile"
