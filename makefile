.PHONY: compile test install docs clean build

compile:
	raco make -j 8 main.rkt

test: clean
	raco test -j 8 .

install: clean compile docs
	raco pkg install --auto --link

docs:
	raco scribble --htmls +m --dest-name docs --redirect-main http://docs.racket-lang.org/ scribblings/manual.scrbl

clean:
	find . -type f -wholename "*/compiled/*" -delete

build: clean test compile docs
