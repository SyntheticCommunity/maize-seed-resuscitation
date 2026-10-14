# =============================================================================
# export-figure.R
#
# 目标：在 Quarto + knitr 文档里，用 chunk 选项声明式地“一次画图，多格式导出”，
#       并自动把下载链接追加到 figure / table 的 caption 里。
#
# 文档里只写（图）：
#
#   ```{r}
#   #| label: fig-pcoa
#   #| fig-cap: "β 多样性 PCoA 分析"
#   #| fig-export: [png, pdf, pptx]
#   ggplot(...) + ...
#   ```
#
# 结果：figures/fig-pcoa.png / .pdf / .pptx 三份文件，
#       图注自动变成 “β 多样性 PCoA 分析 [PNG](...) [PDF](...) [PPTX](...)”。
#
# 全局配置写在 _quarto.yml 里（不需要在 R 里重复写）：
#
#   knitr:
#     opts_chunk:
#       export-config:
#         figure: {dir: figures, formats: [png, pdf, pptx], width: 7, height: 4.5, dpi: 300}
#         table:  {dir: tables,  formats: [csv, xlsx]}
#       fig-export: false        # 默认不导出；改成 true 就是“所有图都导出”，单个 chunk 可用
#       tbl-export: false        # fig-export: false 关掉
#
# base R 图（plot / hist / barplot …）同样支持导出：在 plot 钩子里用
# grDevices::recordPlot() 拿到显示列表，再重放到 pdf / svg / 300dpi png，PPTX 则交给
# export::graph2ppt(fun = ...) 画成矢量。限制：一个 chunk 里有多张 base 图时，knitr
# 的设备状态是累积的，无法逐张取到绘图对象，此时退化为复制 knitr 的位图并给出提示。
#
# 表格同理，只是 caption 要借 !expr 写进 chunk 选项（原因见下）：
#
#   ```{r}
#   #| label: tbl-alpha
#   #| tbl-cap: !expr tbl_cap("各样本 α 多样性指数", "tbl-alpha")
#   #| tbl-export: [csv, xlsx]
#   alpha           # 代码块最后一个表达式直接返回 data.frame
#   ```
#
# 为什么不是单纯的 chunk hook：
#   * chunk hook 的 after 阶段拿到的 options 是副本，改 fig.cap 已经太晚
#     （knitr 在求值过程中就把 caption 渲染进输出了）；
#   * chunk hook 也拿不到真实的 ggplot 对象，只能拿到已经渲染好的图片文件，
#     那样 PPTX 里嵌的只能是位图。
#   * Quarto 的表格 caption 不走 knitr 输出，而是直接取自 chunk 选项本身
#     （写进 cell div 的 tbl-cap 属性），所以只能在选项里就带上链接。
#
# 这里改用四个协作点：
#   1) render 钩子（opts_chunk$set(render = ...)）—— 在对象被打印前拿到真正的
#      ggplot 对象 / data.frame（key 为 chunk label）；
#   2) plot 钩子（knit_hooks$set(plot = ...)）—— 每个图输出时执行导出，
#      此时 fig.cur / fig.num 已知，可以生成确定性的文件名并改 fig.cap；
#   3) 自定义 chunk hook（fig.export / tbl.export）—— 负责前后清理与提示；
#   4) opts_hooks(tbl.cap) —— R Markdown 等场景下（tbl-cap 会变成 knitr 选项
#      tbl.cap）在求值前把链接写进表注。
# =============================================================================


# --- 内部状态 ----------------------------------------------------------------

.exp <- new.env(parent = emptyenv())

# 全局默认值（可由 use_export() 覆盖，也可由单个 chunk 的 fig-export / tbl-export 覆盖）
.exp$fig <- list(
  dir     = "figures",
  formats = c("png", "pdf", "pptx"),
  width   = 7,
  height  = 4.5,
  dpi     = 300,
  labels  = NULL   # 自定义链接文字，如 c(png = "PNG 原图")
)

.exp$tbl <- list(
  dir     = "tables",
  formats = c("csv", "xlsx"),
  labels  = NULL
)

# 支持的导出格式
.exp$known_formats <- c("png", "pdf", "svg", "tiff", "jpg", "jpeg", "pptx")
.exp$known_table_formats <- c("csv", "tsv", "xlsx", "rds")

# 每个 chunk 捕获到的绘图对象 / 数据框 / 已写出的文件（key = chunk label）
.exp$plots   <- list()
.exp$tables  <- list()
.exp$written <- list()

# 导出了但没地方放链接的（缺 fig-cap / 表注没用 tbl_cap()），文档末尾汇总提示一次
.exp$unlinked_fig <- character(0)
.exp$unlinked_tbl <- character(0)

.exp$plot_hook <- NULL    # use_export() 之前的原始 plot hook
.exp$document_hook <- NULL
.exp$active    <- FALSE   # 钩子是否已经注册过


# --- 小工具 ------------------------------------------------------------------

.or <- function(x, y) if (is.null(x) || length(x) == 0) y else x

.is_on <- function(x) !is.null(x) && !isFALSE(x)

# --- 来自 _quarto.yml 的全局配置 --------------------------------------------
#
# _quarto.yml 里 knitr.opts_chunk 下的默认值会原样进入每个 chunk 的 options，
# 所以这里既能读到项目级配置，也允许单个 chunk 用同名选项局部覆盖。
.config <- function(options = NULL) {
  cfg <- if (!is.null(options)) options[["export-config"]] else NULL
  if (!is.list(cfg)) {
    cfg <- tryCatch(knitr::opts_chunk$get("export-config"), error = function(e) NULL)
  }
  if (!is.list(cfg)) list() else cfg
}

.merge_options <- function(base, extra) {
  if (!is.list(extra)) return(base)
  for (nm in names(extra)) {
    if (!is.null(extra[[nm]]) && nm %in% names(base)) base[[nm]] <- extra[[nm]]
  }
  base
}

# 文档所在目录（绝对路径）
.doc_dir <- function() {
  input <- tryCatch(knitr::current_input(dir = TRUE), error = function(e) NULL)
  if (is.null(input) || !length(input) || is.na(input) || !nzchar(input)) return(NULL)
  dirname(input)
}

.is_abs <- function(path) {
  grepl("^(/|[A-Za-z]:|~)", path)
}

# 项目根：从文档目录向上找 _quarto.yml / _quarto.yaml；找不到就退回 knitr 的 root.dir
.project_root <- function() {
  doc <- .doc_dir()
  if (!is.null(doc)) {
    d <- tryCatch(normalizePath(doc, mustWork = FALSE), error = function(e) doc)
    for (i in 1:5) {
      if (file.exists(file.path(d, "_quarto.yml")) ||
          file.exists(file.path(d, "_quarto.yaml"))) {
        return(d)
      }
      parent <- dirname(d)
      if (identical(parent, d)) break
      d <- parent
    }
  }
  .knit_root()
}

# 文档目录相对项目根的前缀（analysis/ 下是 "../"，项目根文档是 ""）
.rel_prefix_to_root <- function() {
  doc <- .doc_dir()
  if (is.null(doc)) return("")
  doc  <- tryCatch(normalizePath(doc, mustWork = FALSE), error = function(e) doc)
  root <- tryCatch(normalizePath(.project_root(), mustWork = FALSE),
                   error = function(e) .project_root())
  doc <- sub("/+$", "", doc); root <- sub("/+$", "", root)
  if (identical(doc, root)) return("")
  if (!startsWith(doc, paste0(root, "/"))) return("")
  strrep("../", length(strsplit(substring(doc, nchar(root) + 2L), "/")[[1]]))
}

# Quarto 有时会把 _quarto.yml 里的相对路径按文档目录改写（figures -> ../figures，
# 而且是否改写取决于 .quarto 缓存）。这里统一剥掉，让目录始终以项目根为基准。
.strip_root_prefix <- function(path) {
  if (is.null(path) || !is.character(path) || !length(path) || !nzchar(path[[1]])) {
    return(path)
  }
  if (.is_abs(path[[1]])) return(path)
  prefix <- .rel_prefix_to_root()
  if (nzchar(prefix) && startsWith(path[[1]], prefix)) {
    return(substring(path, nchar(prefix) + 1L))
  }
  path
}

# figure / table 当前的默认值：内置默认 -> _quarto.yml -> use_export() -> chunk 级 export-config
.kind_defaults <- function(kind, options = NULL) {
  base <- if (identical(kind, "table")) .exp$tbl else .exp$fig
  cfg <- .config(options)[[kind]]
  if (is.list(cfg) && !is.null(cfg$dir)) cfg$dir <- .strip_root_prefix(cfg$dir)
  .merge_options(base, cfg)
}

# 这个选项是 chunk 自己写的，还是从全局默认继承来的？（后者不重复提示）
.is_local_option <- function(options, name) {
  global <- tryCatch(.opt(as.list(knitr::opts_chunk$get()), name),
                     error = function(e) NULL)
  !identical(.opt(options, name), global)
}

.is_caption <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
}

# 图注里是否已经链接到这个图（例如作者自己用了 fig_cap()）：避免重复追加
.caption_has_links <- function(cap, stem) {
  if (!.is_caption(cap)) return(FALSE)
  any(vapply(.exp$known_formats, function(ext) {
    grepl(paste0(stem, ".", ext), cap, fixed = TRUE)
  }, logical(1)))
}

# 读 chunk 选项：Quarto 会把 fig-cap 规范化成 fig.cap，但自定义选项
# （fig-export / tbl-export）保持连字符写法，所以两种都要认
.opt <- function(options, name) {
  value <- options[[name]]
  if (is.null(value)) {
    dashed <- sub("^([^.]+)\\.", "\\1-", name)
    if (!identical(dashed, name)) value <- options[[dashed]]
  }
  value
}

.warn <- function(fmt, ...) {
  warning(sprintf(paste0("export-figure: ", fmt, " ", collapse = ""), ...),
          call. = FALSE)
}

# knitr / Quarto 给代码块设置的执行目录（execute-dir: project 时是项目根）
.knit_root <- function() {
  root <- tryCatch(knitr::opts_knit$get("root.dir"), error = function(e) NULL)
  if (is.null(root) || !length(root) || is.na(root) || !nzchar(root)) root <- getwd()
  root
}

# 导出目录一律相对项目根解析，所以写文件前切到项目根。
# 注意：chunk 里的代码可能跑在 root.dir（execute-dir: project 时=项目根），
# plot / chunk 钩子却跑在进程工作目录（文档目录），必须显式切一次。
.in_root <- function(expr) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  root <- tryCatch(normalizePath(.project_root(), mustWork = FALSE),
                   error = function(e) .project_root())
  if (!identical(root,
                 normalizePath(old, mustWork = FALSE))) {
    setwd(root)
  }
  force(expr)
}

# 文档在子目录时，把 figures/x.png 写成 ../figures/x.png
.link_prefix <- function() .rel_prefix_to_root()

# 生成 markdown 链接：[PNG](figures/fig-x.png) [PDF](...) [PPTX](...)
.md_links <- function(stem, formats, dir, labels = NULL) {
  if (!length(formats)) return("")
  txt <- if (!is.null(labels)) {
    out <- unname(labels[tolower(formats)])
    ifelse(is.na(out), toupper(formats), out)
  } else {
    toupper(formats)
  }
  paths <- file.path(dir, paste0(stem, ".", tolower(formats)))
  paste(sprintf("[%s](%s%s)", txt, .link_prefix(), paths), collapse = " ")
}

# 同上，但直接按“真实存在的文件路径”来生成
.md_links_from_paths <- function(paths, labels = NULL) {
  if (!length(paths)) return("")
  ext <- tolower(tools::file_ext(paths))
  txt <- if (!is.null(labels)) {
    out <- unname(labels[ext])
    ifelse(is.na(out), toupper(ext), out)
  } else {
    toupper(ext)
  }
  paste(sprintf("[%s](%s%s)", txt, .link_prefix(), paths), collapse = " ")
}

# 解析 chunk 选项 fig-export / tbl-export
.parse_spec <- function(spec, defaults, what, known = .exp$known_formats) {
  if (!.is_on(spec)) return(NULL)
  formats <- NULL
  extra <- list()
  if (is.character(spec)) {
    formats <- spec
  } else if (is.list(spec)) {
    formats <- spec$formats
    extra <- spec[setdiff(names(spec), "formats")]
  }
  out <- list(
    dir     = .or(extra$dir, NULL),
    formats = tolower(.or(formats, defaults$formats)),
    labels  = .or(extra$labels, defaults$labels),
    name    = .or(extra$name, NULL)
  )
  if (!is.null(out$dir)) out$dir <- .strip_root_prefix(out$dir)
  for (nm in c("width", "height", "dpi")) {
    if (!is.null(defaults[[nm]])) out[[nm]] <- .or(extra[[nm]], defaults[[nm]])
  }
  out$dir <- .or(out$dir, defaults$dir)
  if (!length(out$formats)) return(NULL)
  bad <- setdiff(out$formats, known)
  if (length(bad)) {
    .warn("%s 里出现不支持的格式：%s", what, paste(bad, collapse = ", "))
    out$formats <- intersect(out$formats, known)
  }
  if (!length(out$formats)) return(NULL)
  out
}

.fig_spec <- function(options) {
  defaults <- .kind_defaults("figure", options)
  # 【本地补丁】导出尺寸默认跟随 chunk 的 fig-width / fig-height（chunk 里没写时
  # 就是 _quarto.yml 里的默认值），这样图注链接下载到的图与正文里显示的尺寸一致。
  # chunk 里仍可用 #| fig-export: {width: 4, height: 3} 单独覆盖。
  defaults$width  <- .or(options$fig.width,  defaults$width)
  defaults$height <- .or(options$fig.height, defaults$height)
  .parse_spec(.opt(options, "fig.export"), defaults, "fig-export")
}

.tbl_spec <- function(options) {
  .parse_spec(.opt(options, "tbl.export"), .kind_defaults("table", options),
              "tbl-export", known = .exp$known_table_formats)
}

# 文件名：单图用 label，一个 chunk 出多张图时加序号（plot hook 里 fig.num 已知）
.stem <- function(label, spec, index = NULL) {
  base <- .or(spec$name, label)
  # 【本地补丁】knitr 给未命名 chunk 的自动 label（unnamed-chunk-N）是按文档编号的，
  # 不同章节之间会撞名，导出到同一个 output/figures/ 下互相覆盖、图注链接也会指错图。
  # 这里给这类 label 补上章节名前缀，保证一个项目里文件名唯一。
  if (is.null(spec$name) && grepl("^unnamed-chunk-", base)) {
    doc <- tryCatch(knitr::current_input(), error = function(e) NULL)
    if (is.character(doc) && length(doc) == 1 && nzchar(doc)) {
      base <- paste0(tools::file_path_sans_ext(basename(doc)), "-", base)
    }
  }
  if (is.null(index)) base else sprintf("%s-%d", base, index)
}


# --- 导出实现 ----------------------------------------------------------------

.write_ggsave <- function(plot, dest, fmt, width, height, dpi) {
  device <- switch(
    fmt,
    png = if (requireNamespace("ragg", quietly = TRUE)) ragg::agg_png else "png",
    pdf = if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else "pdf",
    svg = if (requireNamespace("svglite", quietly = TRUE)) {
      svglite::svglite
    } else if (isTRUE(capabilities("cairo"))) {
      grDevices::svg
    } else {
      "svg"
    },
    NULL
  )
  tryCatch({
    args <- list(filename = dest, plot = plot, width = width, height = height,
                 dpi = dpi, limitsize = FALSE)
    if (!is.null(device)) args$device <- device
    do.call(ggplot2::ggsave, args)
    TRUE
  }, error = function(e) {
    .warn("ggsave 写出 %s 失败：%s", fmt, conditionMessage(e))
    FALSE
  })
}

# 目标设备工厂：base 图重放时要自己开设备
.device_for <- function(fmt, dpi) {
  switch(
    fmt,
    png = function(file, width, height) {
      if (requireNamespace("ragg", quietly = TRUE)) {
        ragg::agg_png(file, width = width, height = height, units = "in", res = dpi)
      } else {
        grDevices::png(file, width = width, height = height, units = "in", res = dpi)
      }
    },
    pdf = function(file, width, height) {
      if (isTRUE(capabilities("cairo"))) {
        grDevices::cairo_pdf(file, width = width, height = height)
      } else {
        grDevices::pdf(file, width = width, height = height)
      }
    },
    svg = function(file, width, height) {
      if (requireNamespace("svglite", quietly = TRUE)) {
        svglite::svglite(file, width = width, height = height)
      } else {
        grDevices::svg(file, width = width, height = height)
      }
    },
    tiff = function(file, width, height) {
      grDevices::tiff(file, width = width, height = height, units = "in",
                      res = dpi, compression = "lzw")
    },
    jpg = function(file, width, height) {
      grDevices::jpeg(file, width = width, height = height, units = "in",
                      res = dpi, quality = 95)
    },
    jpeg = function(file, width, height) {
      grDevices::jpeg(file, width = width, height = height, units = "in",
                      res = dpi, quality = 95)
    },
    NULL
  )
}

# 在指定格式的设备上“画”一遍：draw 可以是显示列表重放，也可以是用户给的画图函数
.write_draw <- function(draw, fmt, dest, width, height, dpi) {
  device <- .device_for(fmt, dpi)
  if (is.null(device)) {
    .warn("不支持的导出格式：%s", fmt)
    return(FALSE)
  }
  ok <- TRUE
  opened <- FALSE
  tryCatch({
    device(dest, width, height)
    opened <- TRUE
    grDevices::dev.control("enable")
    draw()
  }, error = function(e) {
    ok <<- FALSE
    .warn("重绘并写出 %s 失败：%s", toupper(fmt), conditionMessage(e))
  })
  if (opened) try(grDevices::dev.off(), silent = TRUE)
  isTRUE(ok) && file.exists(dest) && file.size(dest) > 0
}

.write_recorded <- function(rp, fmt, dest, width, height, dpi) {
  .write_draw(function() grDevices::replayPlot(rp), fmt, dest, width, height, dpi)
}

.write_fun <- function(fun, fmt, dest, width, height, dpi) {
  .write_draw(fun, fmt, dest, width, height, dpi)
}

# base R 图：knitr 的设备开启了显示列表，重放它就能拿到矢量图
.record_current <- function(options) {
  # 一个 chunk 多张图时设备状态是累积的，取不到“单张”，只有单图 chunk 才可靠
  if (!identical(as.integer(.or(options$fig.num, 1L)), 1L)) return(NULL)
  tryCatch({
    rp <- grDevices::recordPlot()
    if (inherits(rp, "recordedplot") && length(rp[[1]]) > 0) rp else NULL
  }, error = function(e) NULL)
}

# 【本地补丁】ggtree 系图形（系统发育树、microeco 的 cladogram）在 export 的 DML
# 设备上偶发 grid 段错误（traceback 停在 grid.Call.graphics(C_polygon, ...)）。
# 段错误 R 的 tryCatch 拦不住，会直接带走整个渲染进程，所以这类对象改到子进程里导出：
# 崩了只损失这一张 PPTX，主进程继续，并退化到后面的 officer + 位图回退。
.write_pptx_subprocess <- function(plot, dest, width, height) {
  if (!requireNamespace("callr", quietly = TRUE)) return(FALSE)
  ok <- tryCatch(callr::r(
    function(obj, file, width, height) {
      utils::capture.output(suppressMessages(
        export::graph2ppt(x = obj, file = file, width = width, height = height)))
      file.exists(file)
    },
    args = list(obj = plot, file = dest, width = width, height = height),
    libpath = .libPaths()
  ), error = function(e) {
    .warn("PPTX 子进程导出失败（%s），退回位图", class(e)[1])
    FALSE
  })
  isTRUE(ok) && file.exists(dest) && file.size(dest) > 0
}

.write_pptx <- function(plot, dest, width, height, dpi) {
  # 首选 export::graph2ppt()，图形以矢量（DrawingML）写入 PPTX，可继续编辑
  if (inherits(plot, "ggtree")) {
    if (.write_pptx_subprocess(plot, dest, width, height)) return(TRUE)
    # 子进程崩溃 / 不可用：落到下面的 officer + 位图回退
  } else if (requireNamespace("export", quietly = TRUE)) {
    draw <- if (is.function(plot)) {
      plot
    } else if (inherits(plot, "recordedplot")) {
      function() grDevices::replayPlot(plot)
    } else {
      NULL
    }
    return(tryCatch({
      utils::capture.output(suppressMessages(
        if (is.null(draw)) {
          export::graph2ppt(x = plot, file = dest, width = width, height = height)
        } else {
          # base R 图：export 通过 fun 参数逐设备重画
          export::graph2ppt(fun = draw, file = dest, width = width, height = height)
        }
      ))
      file.exists(dest)
    }, error = function(e) {
      .warn("export::graph2ppt() 失败：%s", conditionMessage(e))
      FALSE
    }))
  }
  # 退路：officer + 位图
  if (requireNamespace("officer", quietly = TRUE)) {
    return(tryCatch({
      tmp <- tempfile(fileext = ".png")
      on.exit(unlink(tmp), add = TRUE)
      ok <- if (is.function(plot) || inherits(plot, "recordedplot")) {
        .write_one(plot, "png", tmp, width, height, dpi)
      } else {
        .write_ggsave(plot, tmp, "png", width, height, dpi)
      }
      if (!isTRUE(ok)) return(FALSE)
      doc <- officer::read_pptx()
      doc <- officer::add_slide(doc, layout = "Title and Content",
                                master = "Office Theme")
      doc <- officer::ph_with(
        doc, officer::external_img(tmp, width = width, height = height),
        location = officer::ph_location_type(type = "body")
      )
      print(doc, target = dest)
      file.exists(dest)
    }, error = function(e) {
      .warn("officer 写出 PPTX 失败：%s", conditionMessage(e))
      FALSE
    }))
  }
  .warn("导出 PPTX 需要 export 包（或 officer）：install.packages(\"export\")")
  FALSE
}

.write_one <- function(plot, fmt, dest, width, height, dpi) {
  fmt <- tolower(fmt)
  if (identical(fmt, "pptx")) return(.write_pptx(plot, dest, width, height, dpi))
  if (inherits(plot, "recordedplot")) {
    return(.write_recorded(plot, fmt, dest, width, height, dpi))
  }
  if (is.function(plot)) return(.write_fun(plot, fmt, dest, width, height, dpi))
  .write_ggsave(plot, dest, fmt, width, height, dpi)
}

#' 导出图形为多种格式
#'
#' @param plot ggplot 对象（patchwork / cowplot 组合图也可以）、
#'   `recordedplot`（`grDevices::recordPlot()` 的结果），
#'   或者一个“画图函数”（base R 图用这个，例如 `function() plot(1:10)`）
#' @param name 文件名（不含扩展名），例如 "fig-pcoa"
#' @param formats 目标格式，默认取 use_export() 里的设置
#' @param dir 输出目录
#' @return 实际写出的文件路径（不可见返回）
export_figure <- function(plot, name, formats = NULL, dir = NULL,
                          width = NULL, height = NULL, dpi = NULL) {
  formats <- tolower(.or(formats, .exp$fig$formats))
  dir     <- .or(dir, .exp$fig$dir)
  width   <- .or(width, .exp$fig$width)
  height  <- .or(height, .exp$fig$height)
  dpi     <- .or(dpi, .exp$fig$dpi)

  .in_root({
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    paths <- character(0)
    for (fmt in formats) {
      dest <- file.path(dir, paste0(name, ".", fmt))
      if (isTRUE(.write_one(plot, fmt, dest, width, height, dpi))) {
        paths <- c(paths, dest)
      } else {
        .warn("导出 %s 失败：%s", toupper(fmt), dest)
      }
    }
    invisible(paths)
  })
}

.write_table_xlsx <- function(data, dest, name) {
  sheet <- gsub("[\\[\\]\\*\\?/\\\\:]", "_", name)
  sheet <- substr(sheet, 1, 31)
  if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(data, file = dest, sheetName = sheet)
    return(TRUE)
  }
  .warn("导出 XLSX 需要 openxlsx 包")
  FALSE
}

#' 导出一张数据框为多种格式（默认 CSV + XLSX）
export_table <- function(data, name, formats = NULL, dir = NULL) {
  formats <- tolower(.or(formats, .exp$tbl$formats))
  dir     <- .or(dir, .exp$tbl$dir)

  .in_root({
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    paths <- character(0)
    for (fmt in formats) {
      dest <- file.path(dir, paste0(name, ".", fmt))
      ok <- tryCatch(switch(
        fmt,
        csv  = { utils::write.csv(data, dest, row.names = FALSE,
                                  fileEncoding = "UTF-8"); TRUE },
        tsv  = { utils::write.table(data, dest, sep = "\t", row.names = FALSE,
                                    fileEncoding = "UTF-8"); TRUE },
        xlsx = .write_table_xlsx(data, dest, name),
        rds  = { saveRDS(data, dest); TRUE },
        { .warn("导表时不支持的格式：%s", fmt); FALSE }
      ), error = function(e) {
        .warn("写出 %s 失败：%s", fmt, conditionMessage(e))
        FALSE
      })
      if (isTRUE(ok)) paths <- c(paths, dest)
    }
    invisible(paths)
  })
}


# --- 供手写 caption 使用 ------------------------------------------------------

#' 手工拼一个带下载链接的图注（chunk 选项里用 !expr 调用）
#'
#' #| fig-cap: !expr fig_cap("β 多样性 PCoA 分析", "fig-pcoa")
fig_cap <- function(title, name, formats = NULL, dir = NULL, labels = NULL) {
  paste0(title, " ", .md_links(name, tolower(.or(formats, .exp$fig$formats)),
                               .or(dir, .exp$fig$dir), .or(labels, .exp$fig$labels)))
}

#' 同上，用于表格
tbl_cap <- function(title, name, formats = NULL, dir = NULL, labels = NULL) {
  paste0(title, " ", .md_links(name, tolower(.or(formats, .exp$tbl$formats)),
                               .or(dir, .exp$tbl$dir), .or(labels, .exp$tbl$labels)))
}

#' 列出已导出的文件清单（方便在文档里做一张“下载索引”表）
list_exports <- function(dirs = NULL) {
  dirs <- .or(dirs, c(.exp$fig$dir, .exp$tbl$dir))
  files <- .in_root(unlist(lapply(dirs, function(d) {
    if (dir.exists(d)) list.files(d, full.names = TRUE) else character(0)
  })))
  files <- sort(files[file.exists(files)])
  if (!length(files)) {
    return(data.frame(file = character(0), dir = character(0),
                      size = character(0), modified = character(0)))
  }
  info <- file.info(files)
  data.frame(
    file     = basename(files),
    dir      = dirname(files),
    size     = vapply(info$size, .fmt_size, character(1)),
    modified = format(info$mtime, "%Y-%m-%d %H:%M"),
    row.names = NULL, stringsAsFactors = FALSE
  )
}

.fmt_size <- function(bytes) {
  if (is.na(bytes)) return(NA_character_)
  if (bytes < 1024) sprintf("%d B", bytes)
  else if (bytes < 1024^2) sprintf("%.1f KB", bytes / 1024)
  else sprintf("%.1f MB", bytes / 1024^2)
}


# --- 钩子 --------------------------------------------------------------------

# 1) plot hook：每个图输出时执行导出，并给 fig.cap 追加链接
.hook_plot <- function(x, options) {
  spec <- .fig_spec(options)
  if (!is.null(spec)) {
    label <- .or(options$label, "")
    index <- if (isTRUE(.or(options$fig.num, 1L) > 1L)) {
      as.integer(.or(options$fig.cur, 1L))
    } else {
      NULL
    }
    stem  <- .stem(label, spec, index)
    paths <- .export_current(x, options, spec, stem)
    if (length(paths)) {
      .exp$written[[label]] <- unique(c(.exp$written[[label]], paths))
      if (.is_caption(options$fig.cap) && !.caption_has_links(options$fig.cap, stem)) {
        links <- .md_links_from_paths(paths, spec$labels)
        if (nzchar(links) && !grepl(links, options$fig.cap, fixed = TRUE)) {
          options$fig.cap <- paste0(options$fig.cap, " ", links)
        }
      } else if (!.is_caption(options$fig.cap)) {
        # 导出了文件却没有图注可挂链接，记下来在文档末尾统一提示
        .exp$unlinked_fig <- unique(c(.exp$unlinked_fig, label))
      }
    }
  }
  .exp$plot_hook(x, options)
}

# 拿到当前这张图对应的对象并导出；base R 图走“显示列表重放”，ggplot 走原对象渲染
.export_current <- function(x, options, spec, stem) {
  label <- .or(options$label, "")
  index <- as.integer(.or(options$fig.cur, 1L))
  objects <- .exp$plots[[label]]
  plot <- if (length(objects) >= index) objects[[index]] else NULL
  # knitr 给的图片路径是相对“文档所在目录”的，先转成绝对路径再切目录
  x <- vapply(x, function(p) {
    if (file.exists(p)) normalizePath(p, mustWork = FALSE) else p
  }, character(1), USE.NAMES = FALSE)

  .in_root({
    if (inherits(plot, "ggplot")) {
      dir.create(spec$dir, recursive = TRUE, showWarnings = FALSE)
      paths <- character(0)
      for (fmt in spec$formats) {
        dest <- file.path(spec$dir, paste0(stem, ".", fmt))
        if (isTRUE(.write_one(plot, fmt, dest, spec$width, spec$height, spec$dpi))) {
          paths <- c(paths, dest)
        } else {
          .warn("chunk '%s' 的 %s 导出失败", label, toupper(fmt))
        }
      }
      paths
    } else {
      # base R 图：优先用显示列表重放（可拿到 pdf / svg / 高分辨率 png / 矢量 pptx），
      # 重放不可用时退化为复制 knitr 已经渲染出来的位图
      src    <- x[[1]]
      srcext <- tolower(tools::file_ext(src))
      replay <- .record_current(options)
      can    <- inherits(replay, "recordedplot")
      many   <- isTRUE(.or(options$fig.num, 1L) > 1L)
      dir.create(spec$dir, recursive = TRUE, showWarnings = FALSE)
      paths   <- character(0)
      missing <- character(0)
      for (fmt in spec$formats) {
        dest <- file.path(spec$dir, paste0(stem, ".", fmt))
        ok <- can && isTRUE(.write_one(replay, fmt, dest,
                                       spec$width, spec$height, spec$dpi))
        if (!ok && identical(fmt, srcext)) {
          ok <- isTRUE(file.copy(src, dest, overwrite = TRUE))
        }
        if (ok) paths <- c(paths, dest) else missing <- c(missing, fmt)
      }
      if (length(missing)) {
        hint <- if (many) {
          sprintf("一个 chunk 里有 %s 张图时，base R 图的设备状态是累积的，取不到单张",
                  .or(options$fig.num, "?"))
        } else if (!can) {
          "拿不到显示列表（recordPlot）"
        } else {
          "显示列表重放失败"
        }
        .warn("chunk '%s' 第 %s 张图是 base R 图，%s；无法导出 %s。建议每个 chunk 只放一张 base 图，或用 export_figure(function() ...) 显式导出。",
              label, index, hint, paste(toupper(missing), collapse = "/"))
      }
      paths
    }
  })
}

# 2) fig.export chunk hook：前清理 / 后检查提示
.hook_chunk_fig <- function(before, options, envir = NULL, name = NULL) {
  label <- .or(options$label, "")
  if (isTRUE(before)) {
    .exp$plots[[label]] <- NULL
    .exp$written[[label]] <- NULL
    return(invisible(NULL))
  }
  if (!is.null(.fig_spec(options))) {
    written <- .exp$written[[label]]
    local <- .is_local_option(options, "fig.export")
    if (!length(written)) {
      # 全局默认打开导出时，普通代码块也会走到这里，不必每条都提示
      if (local) .warn("chunk '%s' 设置了 fig-export，但没有检测到可导出的图。", label)
    } else if (local && !.is_caption(options$fig.cap)) {
      .warn("chunk '%s' 设置了 fig-export 但没有 fig-cap，导出文件不会出现在图注里：%s",
            label, paste(basename(written), collapse = ", "))
    }
  }
  .exp$plots[[label]] <- NULL
  .exp$written[[label]] <- NULL
  invisible(NULL)
}

# 3) tbl.export chunk hook：导出 chunk 里最后一个数据框
.hook_chunk_tbl <- function(before, options, envir = NULL, name = NULL) {
  label <- .or(options$label, "")
  if (isTRUE(before)) {
    .exp$tables[[label]] <- NULL
    return(invisible(NULL))
  }
  spec <- .tbl_spec(options)
  if (is.null(spec)) return(invisible(NULL))

  tabs <- .exp$tables[[label]]
  .exp$tables[[label]] <- NULL
  if (!length(tabs)) {
    # 全局打开 tbl-export 时，普通代码块也会走到这里，不必每条都提示
    if (.is_local_option(options, "tbl.export")) {
      .warn("chunk '%s' 设置了 tbl-export，但没有捕获到数据框（请让代码块最后一个表达式直接返回 data.frame）。",
            label)
    }
    return(invisible(NULL))
  }
  if (length(tabs) > 1L) {
    .warn("chunk '%s' 里有 %d 个数据框，tbl-export 只导出最后一个；需要逐个导出请调用 export_table()。",
          label, length(tabs))
  }
  stem <- .or(spec$name, label)
  paths <- export_table(tabs[[length(tabs)]], name = stem,
                        formats = spec$formats, dir = spec$dir)
  # 表格 caption 由 Quarto 从 chunk 选项本身生成（不像图片那样经过 knitr 输出），
  # 所以链接必须一开始就在 tbl-cap 里，这里只做提醒。
  cap <- .opt(options, "tbl.cap")
  has_links <- .is_caption(cap) && length(paths) > 0 &&
    any(vapply(paths, function(p) grepl(p, cap, fixed = TRUE), logical(1)))
  if (!has_links) {
    .exp$unlinked_tbl <- unique(c(.exp$unlinked_tbl, label))
    if (.is_local_option(options, "tbl.export")) {
      .warn("chunk '%s' 设置了 tbl-export，但 tbl-cap 里没有下载链接。Quarto 的表格 caption 直接取自 chunk 选项，请写成：\n  #| tbl-cap: !expr tbl_cap(\"标题\", \"%s\")",
            label, stem)
    }
  }
  invisible(NULL)
}

# 4) opts hook：R Markdown 等场景下 tbl-cap 会变成 knitr 选项 tbl.cap，
#    这时可以在求值前把链接写进 caption（Quarto 下该选项为 NULL，走不到这里）
.hook_opts_tbl_cap <- function(options) {
  spec <- .tbl_spec(options)
  if (!is.null(spec) && .is_caption(options$tbl.cap)) {
    links <- .md_links(.stem(.or(options$label, "table"), spec), spec$formats,
                       spec$dir, spec$labels)
    if (nzchar(links) && !grepl(links, options$tbl.cap, fixed = TRUE)) {
      options$tbl.cap <- paste0(options$tbl.cap, " ", links)
    }
  }
  options
}

# 5) render 钩子：在对象被打印前拿到真正的 ggplot / data.frame
#    （行为与 knitr 默认 render 一致，只是顺手把对象按 label 记下来）
.render_capture <- function(x, options) {
  label <- .or(options$label, "")
  if (.is_on(.opt(options, "fig.export")) && inherits(x, "ggplot")) {
    .exp$plots[[label]] <- c(.exp$plots[[label]], list(x))
  }
  if (.is_on(.opt(options, "tbl.export")) && is.data.frame(x)) {
    .exp$tables[[label]] <- c(.exp$tables[[label]], list(x))
  }
  res <- withVisible(knitr::knit_print(x, options = options))
  if (inherits(x, "htmlwidget")) {
    class(res$value) <- c(class(res$value), "knit_asis_htmlwidget")
  }
  if (res$visible) res$value else invisible(res$value)
}

# 文档钩子：整篇渲染完，把"导出了但没挂上链接"的 chart 汇总提示一次
.hook_document <- function(x) {
  if (length(.exp$unlinked_fig) || length(.exp$unlinked_tbl)) {
    parts <- character(0)
    if (length(.exp$unlinked_fig)) {
      parts <- c(parts, sprintf("%d 张图（%s）没有 fig-cap", length(.exp$unlinked_fig),
                                paste(.exp$unlinked_fig, collapse = ", ")))
    }
    if (length(.exp$unlinked_tbl)) {
      parts <- c(parts, sprintf("%d 张表（%s）的表注没有用 tbl_cap()",
                                length(.exp$unlinked_tbl),
                                paste(.exp$unlinked_tbl, collapse = ", ")))
    }
    .warn("文件已导出，但%s，因此文档里没有下载链接。",
          paste(parts, collapse = "；"))
    .exp$unlinked_fig <- character(0)
    .exp$unlinked_tbl <- character(0)
  }
  if (is.function(.exp$document_hook)) .exp$document_hook(x) else x
}

.register_hooks <- function() {
  if (isTRUE(.exp$active)) return(invisible(FALSE))
  .exp$plot_hook <- knitr::knit_hooks$get("plot")
  .exp$document_hook <- knitr::knit_hooks$get("document")
  knitr::knit_hooks$set(
    plot       = .hook_plot,
    document   = .hook_document,
    fig.export = .hook_chunk_fig,
    tbl.export = .hook_chunk_tbl,
    `fig-export` = .hook_chunk_fig,
    `tbl-export` = .hook_chunk_tbl
  )
  knitr::opts_hooks$set(tbl.cap = .hook_opts_tbl_cap)
  knitr::opts_chunk$set(render = .render_capture)
  .exp$active <- TRUE
  invisible(TRUE)
}


# --- 入口 --------------------------------------------------------------------

#' 打开多格式导出（在文档开头的 setup chunk 里调用一次）
#'
#' @param fig_formats 默认导出格式，默认 c("png", "pdf", "pptx")
#' @param fig_dir 图件输出目录，默认 "figures"
#' @param width,height 图尺寸（英寸）
#' @param dpi 位图分辨率
#' @param tbl_formats 表格默认导出格式，默认 c("csv", "xlsx")
#' @param tbl_dir 表格输出目录，默认 "tables"
#' @param fig_labels,tbl_labels 自定义链接文字，如 c(png = "PNG 原图", xlsx = "Excel")
#' @param quiet 是否打印一行启动信息
use_export <- function(fig_formats = NULL, fig_dir = NULL, width = NULL, height = NULL,
                       dpi = NULL, tbl_formats = NULL, tbl_dir = NULL,
                       fig_labels = NULL, tbl_labels = NULL, quiet = FALSE) {
  # 先吃 _quarto.yml 里的 export-config，再用这里的显式参数覆盖
  cfg <- .config()
  if (is.list(cfg$figure) && !is.null(cfg$figure$dir)) {
    cfg$figure$dir <- .strip_root_prefix(cfg$figure$dir)
  }
  if (is.list(cfg$table) && !is.null(cfg$table$dir)) {
    cfg$table$dir <- .strip_root_prefix(cfg$table$dir)
  }
  .exp$fig <- .merge_options(.exp$fig, cfg$figure)
  .exp$tbl <- .merge_options(.exp$tbl, cfg$table)

  if (!is.null(fig_formats))  .exp$fig$formats <- tolower(fig_formats)
  if (!is.null(fig_dir))      .exp$fig$dir     <- fig_dir
  if (!is.null(width))        .exp$fig$width   <- width
  if (!is.null(height))       .exp$fig$height  <- height
  if (!is.null(dpi))          .exp$fig$dpi     <- dpi
  if (!is.null(fig_labels))   .exp$fig$labels  <- fig_labels
  if (!is.null(tbl_formats))  .exp$tbl$formats <- tolower(tbl_formats)
  if (!is.null(tbl_dir))      .exp$tbl$dir     <- tbl_dir
  if (!is.null(tbl_labels))   .exp$tbl$labels  <- tbl_labels

  .register_hooks()

  if (!isTRUE(quiet)) {
    message(sprintf(
      "export-figure: 图 -> %s/ (%s) | 表 -> %s/ (%s)",
      .exp$fig$dir, paste(.exp$fig$formats, collapse = ", "),
      .exp$tbl$dir, paste(.exp$tbl$formats, collapse = ", ")
    ))
  }
  invisible(list(fig = .exp$fig, tbl = .exp$tbl))
}
