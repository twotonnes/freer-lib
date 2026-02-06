.PHONY: compile test install docs clean build

compile:
	raco make main.rkt

test: clean
	raco test -j 8 .

install: clean compile docs
	raco pkg install --auto --link

docs:
	raco scribble --htmls +m --dest-name docs --redirect-main http://docs.racket-lang.org/ scribblings/manual.scrbl

clean:
	powershell -Command "Get-ChildItem -Path . -Filter 'compiled' -Directory -Recurse | Remove-Item -Recurse -Force; Get-ChildItem -Path . -Filter 'doc' -Directory | Remove-Item -Recurse -Force"

build: clean test compile docs