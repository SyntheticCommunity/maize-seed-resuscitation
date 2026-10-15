# Provenance

This repository was extracted from the `analysis/figures/` chapter of the
source project `maize-seed-microbiome` at commit `769edba` (2026-10-10).

The included data are processed inputs or preparation resources. The Quarto
documents execute the figure-level analyses but intentionally do not repeat
sequencing read processing, assembly, binning, reference comparison, or any
other step requiring raw sequencing data.

## Figure-to-upstream mapping

| Figure | Analysis scope | Upstream analysis represented by bundled inputs |
|---|---|---|
| Figure 1 | Soil, OC, and RC amplicon communities | DADA2, ASV table construction, taxonomy assignment, and phylogenetic tree construction |
| Figure 2 | Seed-water amplicon communities across maize genetic groups | DADA2, ASV table construction, batch adjustment, taxonomy assignment, and sample metadata assembly |
| Figure 3 | Metagenome-assembled genome bins | Metagenomic assembly, binning, bin quality assessment, taxonomic annotation, and phylogenetic tree inference |
| Figure 4 | Cultured isolates and comparative genomics | Sanger/16S identification, isolate composition, complete-genome ANI, nucmer alignment, MAG-to-complete-genome synteny, and SNP calling |
| Figure 5 | GWAS Manhattan plots for ASV1 and ASV2 | BLINK GWAS of Pantoea (ASV1) and Burkholderia (ASV2); the bundled RDS contains chromosome, position, and p-values only |
| Figure 6 | BIOLOG, metabolomics, and RNA-seq | BIOLOG preprocessing, metabolomics differential analysis, RNA-seq quantification, DESeq2 analysis, annotation, and KEGG pathway construction |

## Preservation choices

- Original relative paths under `data/processed/` and `data/prep/` were kept where possible so the figure source code remains directly traceable to the project that produced the paper.
- The Figure 5 GWAS inputs were reduced to ASV1 and ASV2 and stored as a compressed RDS containing only chromosome, position, and p-values.
- Only files read by Figures 1-6 are included.
- Generated DEG workbooks are redirected to `output/tables/` rather than an input-data directory.
- Placeholder chapters from the wider analysis project are excluded.

The SHA256 checksums and byte sizes of all bundled data files are recorded in
`data/MANIFEST.tsv`.
