# 0925a — Bioconductor and the firewall toggle

`BiocManager` comes from CRAN/P3M, but installing `pcaMethods` fetches packages from Bioconductor. The firewall allowlist has no Bioconductor hosts; downloads may redirect to mirrors with changing IPs, making a reliable allowlist more involved than adding one domain. This is another reason to keep `firewall = false` as an explicit option for installation work. No install or firewall test was run for this note.
