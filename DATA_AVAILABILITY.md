# Data availability

## Figure reproduction

All processed input data required to reproduce Figures 1-4 and 6 are included in
this repository. The complete figure-level analysis is executable from these
files with the R and Quarto configuration recorded in this repository.

## Raw and upstream data

Raw sequencing reads and large upstream intermediates are not stored in this
Git repository. The manuscript's final data-availability statement and public
archive accession numbers should be used for those resources when available.

Upstream processing categories represented by the bundled tables are:

- 16S rRNA amplicon sequencing and DADA2 processing
- Metagenomic assembly, binning, and bin characterization
- Complete-genome and MAG comparative genomics, including ANI, synteny, and SNP analyses
- RNA-seq quantification and differential-expression analysis
- Metabolomics differential analysis
- BIOLOG phenotype processing

Repository-relative inputs for each figure are listed in
`data/MANIFEST.tsv`; the conceptual mapping to upstream steps is in
`PROVENANCE.md`.
