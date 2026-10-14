SHELL := /bin/bash

.DEFAULT_GOAL := help
.PHONY: help render render-fig check clean

help:
	@echo "make render              Render all figures into _book/"
	@echo "make render-fig FIG=fig1 Render one figure chapter"
	@echo "make check               Verify the bundled data manifest"
	@echo "make clean               Remove generated build and figure outputs"

render:
	quarto render

render-fig:
	@test -n "$(FIG)" || (echo "Set FIG, for example: make render-fig FIG=fig1"; exit 1)
	quarto render analysis/figures/$(FIG).qmd

check:
	Rscript scripts/check-data.R

clean:
	rm -rf _book _freeze output/figures output/tables
