# Maize seed resuscitation figure repository

Reanalysis code, processed input data, and rendered figures for:

> **Resuscitation Drives the Emergence of Dominant Taxa in the Maize Seed Microbiota**

## Authors

Chenliao Wu^1,2,\#, Cong Lan^1,2,\#, Amina Hadayat^1,2,\#, En Luo^3,4,\#,
Jun-Hao Huang^1,2, Xuan Ming^1,2, Zhao-Shuo Zhang^1,2, Rui Zhang^1,
Xin-Hao Liu^1,2, Cheng Gao^5, Zuqing Meng^6, Kenichi Tsuda^3,4,
Xin-Yu Wang^2, Rui Chen^2, Zhuo Wang^2, Wei-Hang Wang^2, Jia-Yi Li^1,2,
Ning Yang^3,4, Fengping Song^6,\*, Jianbing Yan^3,4,\*, Peng Cai^1,2,7,\*,
Chun-Hui Gao^1,2,7,\*

\# These authors contributed equally to this work.

\* Corresponding authors: Fengping Song (zkxysfp@xza.edu.cn), Jianbing Yan
(yjianbing@mail.hzau.edu.cn), Peng Cai (cp@mail.hzau.edu.cn), and Chun-Hui Gao
(gaoch@mail.hzau.edu.cn).

1. National Key Laboratory of Agricultural Microbiology, Huazhong Agricultural University, Wuhan 430070, China
2. College of Resources and Environment, Huazhong Agricultural University, Wuhan 430070, China
3. Hubei Hongshan Laboratory, Huazhong Agricultural University, Wuhan 430070, China
4. College of Plant Science, Huazhong Agricultural University, Wuhan 430070, China
5. State Key Laboratory of Microbial Diversity and Innovative Utilization, Institute of Microbiology, Chinese Academy of Sciences, Beijing 100101, China
6. College of Plant Sciences, Xizang Agricultural and Animal Husbandry University, Xizang 860000, China
7. Key Laboratory of Farmland Remediation in Central China, Ministry of Agriculture and Rural Affairs, Wuhan 430206, China

## Scope

This repository provides a self-contained reproduction path from processed
input tables to Figures 1-5. The figure-level calculations, including
diversity statistics, differential abundance, co-occurrence analysis, genome
comparisons, and functional enrichment, are executed by the included Quarto
documents.

The repository does not bundle raw reads, assemblies, alignment intermediates,
or the upstream workflows for DADA2, metagenomic assembly and binning, ANI,
nucmer, or SNP calling. Those upstream sources are recorded in
[`PROVENANCE.md`](PROVENANCE.md), and public data-accession information is
maintained in [`DATA_AVAILABILITY.md`](DATA_AVAILABILITY.md).

Figures 6 and 7 were placeholders in the original analysis project and are not
included.

## Build

Requirements:

- R 4.3 or newer
- Quarto 1.4 or newer
- System libraries required by `sf` (GDAL, GEOS, PROJ), plus LibreOffice for PPTX export

Restore the R environment and render the book:

```bash
Rscript -e 'renv::restore()'
make check
make render
```

Render one figure while developing:

```bash
make render-fig FIG=fig1
```

The rendered book is written to `_book/`. Every figure chunk is exported as
PNG, PDF, and PPTX under `output/figures/`. Final composite figures are copied
to `figures/release/` with stable names such as `Figure1.pdf`.

## Repository layout

```text
.
├── analysis/figures/     # Figure 1-5 source code and shared figure setup
├── data/                 # Processed and preparation inputs, plus checksums
├── figures/release/      # Final composite figures with stable names
├── output/               # Generated panel figures and tables
├── scripts/              # Shared plotting, validation, and post-render helpers
├── _extensions/          # Quarto fig-export extension
├── _quarto.yml           # Quarto book configuration
└── Makefile              # Build, check, and clean entry points
```

## Citation and license

Citation metadata are provided in [`CITATION.cff`](CITATION.cff). Code, data,
documentation, and figures in this repository are released under the Creative
Commons Attribution 4.0 International License (CC BY 4.0). See
[`LICENSE`](LICENSE).
