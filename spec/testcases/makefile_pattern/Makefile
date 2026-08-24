CC = gcc

app: main.o util.o
	$(CC) -o $@ $^

%.o: %.c
	$(CC) -c $< -o $@

.PHONY: clean
clean:
	rm -f *.o app
