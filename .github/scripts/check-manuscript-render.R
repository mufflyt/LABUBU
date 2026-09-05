#!/usr/bin/env Rscript
# ── Manuscript render check ───────────────────────────────────────────────────
# Nothing previously proved the manuscript still knits. The scientific gate
# only asserts that its statistics are not hardcoded -- a manuscript that fails
# to render would pass that check happily.
#
# Renders from whatever analysis outputs are present and fails on any R error,
# missing object, missing figure, or broken inline calculation. rmarkdown
# already errors on those; this adds the assertions rmarkdown does NOT make:
# that the expected outputs exist, that no inline expression silently rendered
# as an R error string, and that the document is not suspiciously short.

manuscript_rmd <- "labubu_mysterycall_manuscript.Rmd"
render_dir     <- "rendered-manuscript"
ci_dir         <- "ci-results"
dir.create(render_dir, showWarnings = FALSE)
dir.create(ci_dir, showWarnings = FALSE)

fail <- function(msg) {
  cat(sprintf("::error title=MANUSCRIPT FAILURE::%s\n", msg))
  base::message("\nMANUSCRIPT      FAIL: ", msg)
  quit(status = 1)
}

if (!file.exists(manuscript_rmd)) fail(paste(manuscript_rmd, "is absent"))

# Figures the manuscript embeds must exist before rendering, otherwise
# include_graphics() silently omits them.
required_figures <- c("mysterycall_outputs/figures/fig0_strobe_flow.png")
absent_figures <- required_figures[!file.exists(required_figures)]
if (length(absent_figures))
  fail(paste("figures the manuscript embeds are missing:",
             paste(absent_figures, collapse = ", ")))

rendered_html <- tryCatch(
  rmarkdown::render(manuscript_rmd, output_format = "html_document",
                    output_dir = render_dir, quiet = TRUE),
  error = function(e) fail(paste("render failed:", conditionMessage(e))))

manuscript_text <- paste(readLines(rendered_html, warn = FALSE), collapse = "\n")

# An inline expression that errored can still render, leaving the error text in
# the document. Catch the shapes knitr emits rather than trusting exit status.
error_signatures <- c(
  "Error in ", "could not find function", "object '[^']*' not found",
  "\\bNA%", "not estimable", "no paired practices", "no observations")
present_signatures <- error_signatures[
  vapply(error_signatures, function(p) grepl(p, manuscript_text), logical(1))]
if (length(present_signatures))
  fail(paste("rendered manuscript contains unresolved expressions:",
             paste(present_signatures, collapse = ", ")))

# A manuscript that rendered to a stub is a failure even without an error.
word_count <- length(strsplit(gsub("<[^>]+>", " ", manuscript_text), "\\s+")[[1]])
if (word_count < 1500)
  fail(paste("rendered manuscript is only", word_count,
             "words; expected a full paper"))

writeLines(c(
  paste("rendered:", basename(rendered_html)),
  paste("words:", word_count),
  paste("figures verified:", length(required_figures))),
  file.path(ci_dir, "manuscript-render.txt"))

base::message("MANUSCRIPT      PASS (", word_count, " words)")
