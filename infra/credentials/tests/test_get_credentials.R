# Run:     Rscript infra/credentials/tests/test_get_credentials.R
# Inputs:  The environment and a stubbed host store
# Outputs: Test status; no project files are modified
pdf(NULL)

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_file <- sub("^--file=", "", script_arg[[1]])
source(file.path(dirname(normalizePath(script_file)), "..", "get-credentials.R"))

old_value <- Sys.getenv("TEST_TOKEN", unset = NA_character_)
on.exit({
  if (is.na(old_value)) Sys.unsetenv("TEST_TOKEN") else Sys.setenv(TEST_TOKEN = old_value)
}, add = TRUE)
.read_from_store <- function(target) "host-value"

Sys.setenv(TEST_TOKEN = "environment")
stopifnot(identical(get_credential("TEST_TOKEN", "test-token"), "environment"))

Sys.unsetenv("TEST_TOKEN")
stopifnot(identical(get_credential("TEST_TOKEN", "test-token"), "host-value"))

stopifnot(!exists(".read_mounted_credentials"), !exists(".mounted_credentials_file"))

message("All R credential tests passed.")
