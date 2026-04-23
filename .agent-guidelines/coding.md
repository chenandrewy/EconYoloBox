# Coding Guidelines

## Naming
- Use kebab-case for file and folder names.

## Script Headers
- Top comment in every script: how to run, inputs, outputs.

## Error Handling
- Do not create fallback or try-catch statements unless they are strictly necessary.

## Forbidden Actions
- **Never create virtual environments**
- **Never create libraries to avoid sandbox issues**  

## Latex
- For citations use `biber`, `\citet{}` and `\citealt{}`
- To compile, use `pdflatex` and `biber`. 

## R
- Use `dplyr` for most data manipulation. Use `data.table` for large datasets.
- Use `ggplot2` for plotting. 