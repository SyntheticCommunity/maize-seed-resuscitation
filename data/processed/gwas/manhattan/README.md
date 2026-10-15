# Figure 5 GWAS data

`fig5_asv1_asv2_manhattan.rds` is a compact representation of the BLINK GWAS
results used for Figure 5. It contains only the two datasets used by the
figure:

- ASV1, labelled `Pantoea`
- ASV2, labelled `Burkholderia`

The RDS object contains:

- `chr`: chromosome number for 2,847,573 variants
- `pos`: variant position
- `p_value`: a numeric matrix with one column per ASV
- `trait`: trait labels corresponding to the columns of `p_value`

The original per-ASV text result files are not bundled. All fields not used by
Figure 5, including `taxa` and `maf`, were removed during preparation.

The complete p-value vectors remain in the RDS file and are used to determine
significance. For rendering only, Figure 5 keeps every significant variant and
summarizes non-significant background variants by retaining the minimum
p-value in each 5 kb window. This preserves the visible Manhattan peaks while
keeping the exported PNG, PDF, and PPTX files practical for public release.
