#!/usr/bin/env Rscript
# Report the alpha channel of every committed figure.
#
# Written ad hoc while chasing a STROBE diagram that was 72% transparent, and
# kept because the failure is invisible by inspection: black text on a
# transparent background looks correct on a white page and vanishes in a dark
# viewer. `figures/opaque-background` in the scientific gate enforces this in
# CI; this is the version to run by hand when you want the numbers.
#
#   Rscript tools/check_figure_opacity.R [figure_dir]

figure_dir <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(figure_dir)) figure_dir <- "mysterycall_outputs/figures"

if (!requireNamespace("png", quietly = TRUE))
  stop("the png package is required to read alpha channels")

figures <- list.files(figure_dir, pattern = "[.]png$", full.names = TRUE)
if (!length(figures)) stop("no PNG figures found in ", figure_dir)

for (f in figures) {
  img <- png::readPNG(f)
  channels <- if (length(dim(img)) == 3) dim(img)[3] else 1L
  transparent <- if (channels == 4) 100 * mean(img[, , 4] == 0) else 0
  cat(sprintf("  %-46s %dch  transparent %5.1f%%%s\n",
              basename(f), channels, transparent,
              if (transparent > 1) "   <- FIX" else ""))
}
