# ABOUTME: Shared credential retrieval module for R.
# ABOUTME: Resolves credentials from the environment or the host store.
#
# Run:     source("infra/credentials/get-credentials.R")
# Inputs:  Environment variables (in the container, set at creation from the
#          host's --env-file), the host credential store, and credentials-map.json
# Outputs: Credential values returned by get_credential() or get_all_credentials()

.credentials_source_file <- tryCatch(
  normalizePath(sys.frame(1)$ofile, mustWork = TRUE),
  error = function(e) normalizePath("infra/credentials/get-credentials.R", mustWork = FALSE)
)
.credentials_dir <- dirname(.credentials_source_file)
.credentials_json <- file.path(.credentials_dir, "credentials-map.json")

.load_credential_map <- function() {
  jsonlite::fromJSON(.credentials_json, simplifyVector = TRUE)
}

.run_secret_command <- function(command, args) {
  output <- suppressWarnings(tryCatch(
    system2(command, args, stdout = TRUE, stderr = TRUE),
    error = function(e) structure(character(), status = 1L)
  ))
  status <- attr(output, "status", exact = TRUE)
  if (!is.null(status) && status != 0L) {
    return("")
  }
  trimws(paste(output, collapse = "\n"))
}

.read_macos_secret <- function(target) {
  .run_secret_command(
    "security",
    c("find-generic-password", "-s", shQuote(target), "-w")
  )
}

.read_windows_secret <- function(target) {
  escaped_target <- gsub("'", "''", target, fixed = TRUE)
  script <- paste0(
    "if (-not (Get-Command Get-StoredCredential -ErrorAction SilentlyContinue)) ",
    "{ Write-Error 'Get-StoredCredential command not available. Install CredentialManager module.'; exit 1 }\n",
    "$cred = Get-StoredCredential -Target '", escaped_target, "'\n",
    "if (-not $cred) { Write-Error \"Credential '", escaped_target,
    "' not found in Windows Credential Manager.\"; exit 1 }\n",
    "$cred.GetNetworkCredential().Password"
  )
  .run_secret_command(
    "powershell",
    c("-NoProfile", "-Command", shQuote(script))
  )
}

.read_from_store <- function(target) {
  system <- Sys.info()[["sysname"]]
  if (identical(system, "Darwin")) {
    return(.read_macos_secret(target))
  }
  if (identical(system, "Windows")) {
    return(.read_windows_secret(target))
  }
  ""
}

# The environment first (in the container Docker sets every credential there
# at creation), then the host credential store.
get_credential <- function(env_var, keychain_target) {
  value <- Sys.getenv(env_var, unset = "")
  if (nzchar(value)) {
    return(value)
  }
  .read_from_store(keychain_target)
}

get_all_credentials <- function() {
  credential_map <- .load_credential_map()
  found <- character()
  missing <- character()
  for (target in names(credential_map)) {
    env_var <- unname(credential_map[[target]])
    value <- get_credential(env_var, target)
    if (nzchar(value)) {
      found[[env_var]] <- value
    } else {
      missing <- c(missing, target)
    }
  }
  list(found = found, missing = missing)
}
