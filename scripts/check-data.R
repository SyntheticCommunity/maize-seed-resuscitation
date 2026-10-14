manifest_path <- "data/MANIFEST.tsv"

if (!file.exists(manifest_path)) {
  stop("Missing data manifest: ", manifest_path, call. = FALSE)
}

manifest <- read.delim(
  manifest_path,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

required_columns <- c("path", "bytes", "sha256")
missing_columns <- setdiff(required_columns, names(manifest))
if (length(missing_columns)) {
  stop("Manifest is missing columns: ", paste(missing_columns, collapse = ", "), call. = FALSE)
}

errors <- character()

for (i in seq_len(nrow(manifest))) {
  path <- manifest$path[[i]]
  expected_bytes <- as.numeric(manifest$bytes[[i]])
  expected_sha256 <- manifest$sha256[[i]]

  if (!file.exists(path)) {
    errors <- c(errors, paste0("missing file: ", path))
    next
  }

  actual_bytes <- file.info(path)$size
  if (is.na(actual_bytes) || actual_bytes != expected_bytes) {
    errors <- c(
      errors,
      sprintf("size mismatch: %s (expected %s, got %s)", path, expected_bytes, actual_bytes)
    )
  }

  hash_line <- system2("sha256sum", args = path, stdout = TRUE, stderr = TRUE)
  actual_sha256 <- sub("[[:space:]].*$", "", hash_line[[1]])
  if (!identical(actual_sha256, expected_sha256)) {
    errors <- c(errors, paste0("sha256 mismatch: ", path))
  }
}

if (length(errors)) {
  stop(paste(errors, collapse = "\n"), call. = FALSE)
}

cat("Data manifest verified:", nrow(manifest), "files.\n")
