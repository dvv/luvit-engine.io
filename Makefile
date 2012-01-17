all: lib

lib:
	-which moonc && rm -fr lib && ( cd src ; moonc -t ../lib * )

.PHONY: all lib
