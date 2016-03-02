CC     = gcc
CFLAGS = -O2 -std=c99

all:kseq.h fastool.c
	$(CC) $(CFLAGS) fastool.c -o fastool -lz

clean:
	rm -f *.o fastool