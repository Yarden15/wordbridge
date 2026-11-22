.PHONY: app run install clean

app:
	./scripts/build-app.sh

run: app
	-pkill -x Wordbridge
	open build/Wordbridge.app

install: app
	-pkill -x Wordbridge
	rm -rf /Applications/Wordbridge.app
	cp -R build/Wordbridge.app /Applications/
	open /Applications/Wordbridge.app

clean:
	rm -rf .build build
