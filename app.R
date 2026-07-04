library(shiny)
library(bslib)
library(plotly)
library(DT)
library(dplyr)
library(forcats)
library(crosstalk)

# ── Load data ──────────────────────────────────────────────────────────────────
dat_all <- read.csv(
  file.path("mysterycall_outputs", "labubu_cleaned_analysis.csv"),
  stringsAsFactors = FALSE
)

dat_all <- dat_all |>
  mutate(
    scenario = factor(scenario,
                      levels = c("Straight couple", "Lesbian couple", "Single mother")),
    call_date       = as.Date(call_date),
    first_appt_date = as.Date(first_appt_date),
    contact_office  = as.logical(contact_office),
    analytic_inclusion = as.logical(analytic_inclusion)
  )

# Colour palette
pal <- c(
  "Straight couple" = "#2166AC",
  "Lesbian couple"  = "#D6604D",
  "Single mother"   = "#4DAC26"
)

# Semi-transparent versions for violin fill
rgba_pal <- sapply(pal, function(h) {
  v <- col2rgb(h)
  paste0("rgba(", v[1], ",", v[2], ",", v[3], ",0.25)")
})

# ── Crosstalk shared dataset (all records, key columns only) ──────────────────
ct_df <- dat_all |>
  transmute(
    Record   = as.character(record_id),
    Practice = ifelse(is.na(practice_key) | practice_key == "", "(unknown)", practice_key),
    Scenario = as.character(scenario),
    `Bus. days`    = business_days,
    `Cal. days`    = wait_days,
    Offered        = ifelse(is.na(contact_office), "Unknown",
                            ifelse(contact_office, "Yes", "No")),
    `Call date`    = as.character(call_date),
    Included       = ifelse(is.na(analytic_inclusion), "Unknown",
                            ifelse(analytic_inclusion, "Yes", "No")),
    `Excl. reason` = ifelse(is.na(exclusion_reason) | exclusion_reason == "",
                            "—", exclusion_reason)
  )

shared <- SharedData$new(ct_df)

# ── UI ─────────────────────────────────────────────────────────────────────────
ui <- page_navbar(
  title = "LABUBU Audit Explorer",
  theme = bs_theme(bootswatch = "flatly", base_font = font_google("Inter")),
  fillable = FALSE,

  # ── Tab 1: Dashboard ─────────────────────────────────────────────────────────
  nav_panel(
    "Dashboard",
    icon = icon("gauge"),
    layout_columns(
      col_widths = c(4, 4, 4),
      value_box(
        title = "Total calls",
        value = textOutput("n_total"),
        showcase = icon("phone"),
        theme  = "primary"
      ),
      value_box(
        title = "Practices contacted",
        value = textOutput("n_practices"),
        showcase = icon("hospital"),
        theme  = "success"
      ),
      value_box(
        title = "Calls offered an appointment",
        value = textOutput("n_included"),
        showcase = icon("calendar-check"),
        theme  = "info"
      )
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Appointment Offer Rate by Scenario"),
        plotlyOutput("bar_acceptance", height = "320px")
      ),
      card(
        card_header("Scenario Coverage per Practice"),
        plotlyOutput("bar_coverage", height = "320px")
      )
    )
  ),

  # ── Tab 2: Wait Time Explorer ─────────────────────────────────────────────────
  nav_panel(
    "Wait Times",
    icon = icon("clock"),
    layout_sidebar(
      sidebar = sidebar(
        width = 240,
        checkboxGroupInput(
          "wait_scenarios", "Scenarios",
          choices  = c("Straight couple", "Lesbian couple", "Single mother"),
          selected = c("Straight couple", "Lesbian couple", "Single mother")
        ),
        radioButtons(
          "wait_unit", "Time unit",
          choices  = c("Business days" = "business_days", "Calendar days" = "wait_days"),
          selected = "business_days"
        ),
        hr(),
        radioButtons(
          "wait_plot_type", "Chart type",
          choices  = c("Violin + box" = "violin", "ECDF" = "ecdf", "Histogram" = "hist"),
          selected = "violin"
        )
      ),
      layout_columns(
        col_widths = 12,
        card(
          card_header(textOutput("wait_chart_title")),
          plotlyOutput("wait_plot", height = "440px")
        )
      ),
      layout_columns(
        col_widths = 12,
        card(
          card_header("Summary statistics"),
          tableOutput("wait_summary_table")
        )
      )
    )
  ),

  # ── Tab 3: Practice Explorer ──────────────────────────────────────────────────
  nav_panel(
    "Practices",
    icon = icon("list"),
    layout_sidebar(
      sidebar = sidebar(
        width = 240,
        selectInput(
          "practice_filter", "Filter by scenario coverage",
          choices = c(
            "All practices"       = "all",
            "Complete triads (3)" = "3",
            "Dyads (2)"           = "2",
            "Singletons (1)"      = "1"
          )
        ),
        checkboxInput("practice_only_included", "Analytic inclusions only", value = TRUE)
      ),
      card(
        card_header("Practice × Scenario grid"),
        DTOutput("practice_table")
      )
    )
  ),

  # ── Tab 4: Raw records ────────────────────────────────────────────────────────
  nav_panel(
    "Records",
    icon = icon("table"),
    layout_sidebar(
      sidebar = sidebar(
        width = 240,
        checkboxGroupInput(
          "rec_scenarios", "Scenarios",
          choices  = c("Straight couple", "Lesbian couple", "Single mother"),
          selected = c("Straight couple", "Lesbian couple", "Single mother")
        ),
        checkboxGroupInput(
          "rec_inclusion", "Include / exclude",
          choices  = c("Analytic inclusion" = "TRUE", "Excluded" = "FALSE"),
          selected = c("TRUE", "FALSE")
        ),
        downloadButton("download_csv", "Download filtered CSV", class = "btn-sm btn-outline-secondary w-100")
      ),
      card(
        card_header("Individual call records"),
        DTOutput("records_table")
      )
    )
  ),

  # ── Tab 5: Linked Explorer ────────────────────────────────────────────────────
  nav_panel(
    "Linked Explorer",
    icon = icon("magnifying-glass"),
    p(class = "text-muted mt-3 mb-1 px-2",
      HTML("Draw a <b>lasso</b> or <b>box</b> on the scatter to highlight those records
            in the table and histogram. Use the filters to narrow first.")),
    layout_columns(
      col_widths = c(4, 4, 4),
      card(
        card_header("Scenario"),
        filter_checkbox("ct_scen", NULL, shared, ~Scenario, inline = FALSE)
      ),
      card(
        card_header("Business days (wait)"),
        filter_slider("ct_days", NULL, shared, ~`Bus. days`, step = 1, ticks = FALSE)
      ),
      card(
        card_header("Appointment offered?"),
        filter_checkbox("ct_off", NULL, shared, ~Offered, inline = TRUE)
      )
    ),
    layout_columns(
      col_widths = c(7, 5),
      card(
        card_header("Scatter — business days by call date  (lasso / box-select to link)"),
        plotlyOutput("ct_scatter", height = "360px")
      ),
      card(
        card_header("Distribution of selected records"),
        plotlyOutput("ct_hist", height = "360px")
      )
    ),
    card(
      card_header("Selected records — click any row to inspect"),
      DTOutput("ct_table")
    )
  )
)

# ── Server ─────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Dashboard ───────────────────────────────────────────────────────────────
  output$n_total     <- renderText(nrow(dat_all))
  output$n_practices <- renderText(n_distinct(dat_all$practice_id[!is.na(dat_all$practice_id)]))
  output$n_included  <- renderText({
    n  <- sum(dat_all$analytic_inclusion, na.rm = TRUE)
    tot <- nrow(dat_all)
    paste0(n, " / ", tot, " (", round(100 * n / tot), "%)")
  })

  output$bar_acceptance <- renderPlotly({
    df <- dat_all |>
      filter(!is.na(scenario)) |>
      group_by(scenario) |>
      summarise(
        offered = sum(contact_office, na.rm = TRUE),
        total   = n(),
        rate    = round(100 * offered / total, 1),
        .groups = "drop"
      )
    plot_ly(df, x = ~scenario, y = ~rate, color = ~scenario,
            colors = pal, type = "bar",
            text  = ~paste0(offered, "/", total, " (", rate, "%)"),
            textposition = "outside",
            hovertemplate = "%{x}<br>%{text}<extra></extra>") |>
      layout(
        yaxis  = list(title = "Appointment offer rate (%)", range = c(0, 115)),
        xaxis  = list(title = ""),
        showlegend = FALSE,
        margin = list(t = 10)
      ) |>
      config(displayModeBar = FALSE)
  })

  output$bar_coverage <- renderPlotly({
    coverage <- dat_all |>
      filter(!is.na(practice_id), !is.na(scenario)) |>
      group_by(practice_id) |>
      summarise(n_scenarios = n_distinct(as.character(scenario)), .groups = "drop") |>
      count(n_scenarios) |>
      mutate(label = paste0(n_scenarios, " scenario", ifelse(n_scenarios == 1, "", "s")))

    plot_ly(coverage, x = ~label, y = ~n, type = "bar",
            marker = list(color = c("#ABDDA4", "#66C2A5", "#3288BD")),
            text = ~n, textposition = "outside",
            hovertemplate = "%{x}: %{y} practices<extra></extra>") |>
      layout(
        yaxis = list(title = "Number of practices"),
        xaxis = list(title = ""),
        showlegend = FALSE,
        margin = list(t = 10)
      ) |>
      config(displayModeBar = FALSE)
  })

  # ── Wait times ───────────────────────────────────────────────────────────────
  wait_data <- reactive({
    dat_all |>
      filter(
        analytic_inclusion == TRUE,
        !is.na(scenario),
        as.character(scenario) %in% input$wait_scenarios,
        !is.na(.data[[input$wait_unit]]),
        .data[[input$wait_unit]] >= 0
      )
  })

  output$wait_chart_title <- renderText({
    unit <- if (input$wait_unit == "business_days") "business days" else "calendar days"
    paste0("Wait time (", unit, ") by scenario — ", input$wait_plot_type)
  })

  output$wait_plot <- renderPlotly({
    df   <- wait_data()
    unit <- input$wait_unit
    scens <- levels(df$scenario)[levels(df$scenario) %in% unique(as.character(df$scenario))]

    if (input$wait_plot_type == "violin") {
      p <- plot_ly()
      for (s in scens) {
        sub <- df[as.character(df$scenario) == s, ]
        p <- add_trace(p,
          type   = "violin",
          y      = sub[[unit]],
          name   = s,
          box    = list(visible = TRUE),
          points = "all",
          jitter = 0.4,
          pointpos = 0,
          marker = list(size = 5, opacity = 0.7),
          line      = list(color = pal[[s]]),
          fillcolor = rgba_pal[[s]],
          hovertemplate = paste0(s, ": %{y} days<extra></extra>")
        )
      }
      p |> layout(
        yaxis = list(title = if (unit == "business_days") "Business days" else "Calendar days"),
        xaxis = list(title = ""),
        violinmode = "group",
        showlegend = TRUE,
        legend = list(orientation = "h", y = -0.15)
      ) |> config(displayModeBar = FALSE)

    } else if (input$wait_plot_type == "ecdf") {
      p <- plot_ly()
      for (s in scens) {
        vals <- sort(df[[unit]][as.character(df$scenario) == s])
        n    <- length(vals)
        p <- add_trace(p,
          type = "scatter", mode = "lines",
          x = vals, y = seq_along(vals) / n,
          name = s,
          line = list(color = pal[[s]], width = 2.5),
          hovertemplate = paste0(s, "<br>%{x} days → %{y:.0%}<extra></extra>")
        )
      }
      p |> layout(
        xaxis = list(title = if (unit == "business_days") "Business days" else "Calendar days"),
        yaxis = list(title = "Cumulative proportion", tickformat = ".0%"),
        legend = list(orientation = "h", y = -0.2)
      ) |> config(displayModeBar = FALSE)

    } else {
      p <- plot_ly()
      for (s in scens) {
        sub <- df[[unit]][as.character(df$scenario) == s]
        p <- add_trace(p,
          type = "histogram", x = sub,
          name = s,
          opacity = 0.65,
          marker = list(color = pal[[s]]),
          hovertemplate = paste0(s, ": %{x} days, count %{y}<extra></extra>")
        )
      }
      p |> layout(
        barmode = "overlay",
        xaxis = list(title = if (unit == "business_days") "Business days" else "Calendar days"),
        yaxis = list(title = "Count"),
        legend = list(orientation = "h", y = -0.2)
      ) |> config(displayModeBar = FALSE)
    }
  })

  output$wait_summary_table <- renderTable({
    df   <- wait_data()
    unit <- input$wait_unit
    df |>
      group_by(Scenario = scenario) |>
      summarise(
        N      = n(),
        Mean   = round(mean(.data[[unit]], na.rm = TRUE), 1),
        Median = round(median(.data[[unit]], na.rm = TRUE), 1),
        SD     = round(sd(.data[[unit]], na.rm = TRUE), 1),
        Min    = min(.data[[unit]], na.rm = TRUE),
        Max    = max(.data[[unit]], na.rm = TRUE),
        .groups = "drop"
      )
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # ── Practice table ───────────────────────────────────────────────────────────
  output$practice_table <- renderDT({
    df <- dat_all
    if (input$practice_only_included) df <- df[df$analytic_inclusion == TRUE, ]

    wide <- df |>
      filter(!is.na(practice_id), !is.na(scenario)) |>
      group_by(practice_id, practice_key) |>
      summarise(
        Straight = if (any(scenario == "Straight couple")) {
          bd <- business_days[scenario == "Straight couple"]
          paste0("✓ (", ifelse(all(is.na(bd)), "—", paste0(round(mean(bd, na.rm=TRUE),0), "d")), ")")
        } else "—",
        Lesbian  = if (any(scenario == "Lesbian couple")) {
          bd <- business_days[scenario == "Lesbian couple"]
          paste0("✓ (", ifelse(all(is.na(bd)), "—", paste0(round(mean(bd, na.rm=TRUE),0), "d")), ")")
        } else "—",
        `Single mother` = if (any(scenario == "Single mother")) {
          bd <- business_days[scenario == "Single mother"]
          paste0("✓ (", ifelse(all(is.na(bd)), "—", paste0(round(mean(bd, na.rm=TRUE),0), "d")), ")")
        } else "—",
        n_scenarios = n_distinct(as.character(scenario)),
        .groups = "drop"
      )

    if (input$practice_filter != "all") {
      wide <- wide[wide$n_scenarios == as.integer(input$practice_filter), ]
    }

    wide |>
      select(Practice = practice_key, Straight, Lesbian, `Single mother`, `# Scenarios` = n_scenarios) |>
      datatable(
        rownames  = FALSE,
        filter    = "top",
        options   = list(pageLength = 20, scrollX = TRUE),
        escape    = FALSE
      )
  })

  # ── Records table ────────────────────────────────────────────────────────────
  records_data <- reactive({
    dat_all |>
      filter(
        !is.na(scenario),
        as.character(scenario) %in% input$rec_scenarios,
        as.character(analytic_inclusion) %in% input$rec_inclusion
      ) |>
      select(
        Record      = record_id,
        Practice    = practice_key,
        Scenario    = scenario,
        `Call date` = call_date,
        `Appt date` = first_appt_date,
        `Bus. days` = business_days,
        `Cal. days` = wait_days,
        Included    = analytic_inclusion,
        `Excl. reason` = exclusion_reason
      )
  })

  output$records_table <- renderDT({
    datatable(
      records_data(),
      rownames = FALSE,
      filter   = "top",
      options  = list(pageLength = 25, scrollX = TRUE)
    )
  })

  output$download_csv <- downloadHandler(
    filename = function() paste0("labubu_filtered_", Sys.Date(), ".csv"),
    content  = function(f) write.csv(records_data(), f, row.names = FALSE)
  )

  # ── Linked Explorer ──────────────────────────────────────────────────────────
  output$ct_scatter <- renderPlotly({
    plot_ly(
      shared,
      x         = ~`Call date`,
      y         = ~`Bus. days`,
      color     = ~Scenario,
      colors    = pal,
      type      = "scatter",
      mode      = "markers",
      marker    = list(size = 10, opacity = 0.8, line = list(width = 1, color = "white")),
      text      = ~paste0(
        "<b>", Practice, "</b><br>",
        Scenario, "<br>",
        "Wait: ", ifelse(is.na(`Bus. days`), "—", paste0(`Bus. days`, " business days")), "<br>",
        "Offered: ", Offered, "<br>",
        "Call date: ", `Call date`
      ),
      hoverinfo = "text"
    ) |>
      highlight(
        on        = "plotly_selected",
        off       = "plotly_deselect",
        color     = toRGB("orange"),
        opacityDim = 0.15,
        selected  = attrs_selected(showlegend = FALSE)
      ) |>
      layout(
        dragmode = "lasso",
        xaxis    = list(title = "Call date"),
        yaxis    = list(title = "Business days until appointment"),
        legend   = list(orientation = "h", y = -0.22),
        margin   = list(t = 10)
      ) |>
      config(
        displayModeBar  = TRUE,
        modeBarButtonsToRemove = list("autoScale2d", "zoomIn2d", "zoomOut2d")
      )
  })

  output$ct_hist <- renderPlotly({
    plot_ly(
      shared,
      x       = ~`Bus. days`,
      color   = ~Scenario,
      colors  = pal,
      type    = "histogram",
      opacity = 0.72,
      nbinsx  = 20,
      hovertemplate = "%{x} days: %{y} calls<extra></extra>"
    ) |>
      layout(
        barmode = "overlay",
        xaxis   = list(title = "Business days"),
        yaxis   = list(title = "Count"),
        legend  = list(orientation = "h", y = -0.22),
        margin  = list(t = 10)
      ) |>
      config(displayModeBar = FALSE)
  })

  output$ct_table <- renderDT(server = FALSE, {
    datatable(
      shared,
      rownames  = FALSE,
      filter    = "top",
      selection = "single",
      options   = list(
        pageLength = 15,
        scrollX    = TRUE,
        columnDefs = list(list(width = "260px", targets = 1))
      )
    )
  })
}

shinyApp(ui, server)
