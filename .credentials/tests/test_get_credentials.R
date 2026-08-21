# Run:     Rscript .credentials/tests/test_get_credentials.R
# Inputs:  Temporary credential files created during the test
# Outputs: Test status; no project files are modified

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_file <- sub("^--file=", "", script_arg[[1]])
source(file.path(dirname(normalizePath(script_file)), "..", "get-credentials.R"))

secret_file <- tempfile()
.mounted_credentials_file <- secret_file
old_value <- Sys.getenv("TEST_TOKEN", unset = NA_character_)
on.exit({
  if (is.na(old_value)) Sys.unsetenv("TEST_TOKEN") else Sys.setenv(TEST_TOKEN = old_value)
  unlink(secret_file)
}, add = TRUE)

writeLines("TEST_TOKEN=mounted", secret_file)
Sys.setenv(TEST_TOKEN = "environment")
stopifnot(identical(get_credential("TEST_TOKEN", "test-token"), "environment"))

Sys.unsetenv("TEST_TOKEN")
writeLines(c("# comment", "TEST_TOKEN=value=with=equals", "MALFORMED"), secret_file)
stopifnot(identical(get_credential("TEST_TOKEN", "test-token"), "value=with=equals"))

writeLines("TEST_TOKEN=mounted", secret_file)
stopifnot(identical(get_credential("TEST_TOKEN", "test-token"), "mounted"))
writeLines(character(), secret_file)
old_store_reader <- .read_from_store
.read_from_store <- function(target) "host-value"
stopifnot(identical(get_credential("TEST_TOKEN", "test-token"), "host-value"))
.read_from_store <- old_store_reader

message("All R credential tests passed.")
