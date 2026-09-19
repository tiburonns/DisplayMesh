APP := displaymesh-virtual-display
SRC := main.m

.PHONY: all clean run

all: $(APP)

$(APP): $(SRC)
	clang -fobjc-arc -fblocks -Wall -Wextra -mmacosx-version-min=13.0 \
		-framework Cocoa -framework CoreGraphics \
		$(SRC) -o $(APP)

run: $(APP)
	./$(APP)

clean:
	rm -f $(APP)
