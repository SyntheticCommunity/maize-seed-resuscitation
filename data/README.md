# Bundled input data

This directory contains only the processed and preparation data required to
render Figures 1-5. The files preserve their original paths so the figure
source code can read them without path rewriting.

Raw sequencing reads, assemblies, intermediate alignment files, and the
upstream workflows that produced these tables are not bundled. See
[`../PROVENANCE.md`](../PROVENANCE.md) and
[`../DATA_AVAILABILITY.md`](../DATA_AVAILABILITY.md) for the analysis boundary
and source-data locations.

`MANIFEST.tsv` records the relative path, byte size, and SHA256 checksum of
every bundled input file. Run:

```bash
make check
```
