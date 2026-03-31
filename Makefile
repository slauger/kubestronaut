.PHONY: serve build install clean

install: .venv/.installed

.venv/.installed: requirements.txt
	python3 -m venv .venv
	.venv/bin/pip install -r requirements.txt
	@touch $@

serve: install
	.venv/bin/mkdocs serve

build: install
	.venv/bin/mkdocs build

clean:
	rm -rf site .venv
