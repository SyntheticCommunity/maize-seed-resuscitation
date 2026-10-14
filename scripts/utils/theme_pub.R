# ============================================================
# theme_pub.R — 全篇统一 ggplot2 主题
#
# 用法:
#   source("scripts/utils/theme_pub.R")
#   ggplot(...) + theme_pub()
#
# 配合 registry.R 使用:
#   source("scripts/utils/registry.R")
#   source("scripts/utils/theme_pub.R")
#   ggplot(...) + theme_pub() + scale_color_treatment()
# ============================================================

#' 论文级 ggplot2 统一主题
#'
#' @param base_size 基准字体大小（pt），默认 8
#' @param family    字体族，默认 "sans"
#'
#' @details
#' 字体层级（以 base_size = 8 为例）：
#'   Figure Label (A/B/C)  : 11 pt
#'   Panel / Axis Title    :  9 pt
#'   Axis Text             :  8 pt
#'   Legend Text           :  7 pt
#'   Annotation            :  7 pt
#'
#' 线宽规范：
#'   axis.line   : 0.4 pt
#'   axis.ticks  : 0.4 pt
#'   geom_line   : 0.6 pt（全局默认）
#'   regression  : 0.7 pt
#'   point       : 2   pt（全局默认）
#'   boxplot     : 0.45 pt
#'   errorbar    : 0.4 pt
#'
#' @export
theme_pub <- function(base_size = 8, family = "sans") {
  theme_bw(base_size = base_size, base_family = family) %+replace%
    theme(
      # ---- 坐标轴 ----
      axis.line    = element_line(linewidth = 0.4, color = "black"),
      axis.ticks   = element_line(linewidth = 0.4),
      axis.title   = element_text(size = base_size + 1, color = "black",
                                  family = family),
      axis.text    = element_text(size = base_size, color = "black",
                                 family = family),

      # ---- 面板 ----
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(linewidth = 0.2, color = "#e1e0d9"),
      panel.border     = element_blank(),

      # ---- 分面标签（strip） ----
      strip.background = element_rect(fill = "grey95", color = NA),
      strip.text       = element_text(size = base_size + 1, color = "black",
                                      family = family),

      # ---- 图例 ----
      legend.text       = element_text(size = base_size - 1, family = family),
      legend.title      = element_text(size = base_size, family = family),
      legend.key.size   = unit(base_size * 0.6, "pt"),
      legend.spacing.x  = unit(2, "pt"),
      legend.spacing.y  = unit(1, "pt"),

      # ---- 标题 ----
      plot.title    = element_text(size = base_size + 3, face = "bold",
                                   family = family),
      plot.subtitle = element_text(size = base_size + 1,
                                   color = "grey40", family = family),
      plot.caption  = element_text(size = base_size - 1,
                                   color = "grey60", family = family),

      # ---- 整体 ----
      plot.margin = margin(4, 4, 2, 2, unit = "pt"),
      complete = TRUE
    )
}


# ============================================================
# 辅助：设置全局 geom 默认值
# ============================================================

#' 设置全篇统一的几何对象默认值
#'
#' 在 source("scripts/utils/theme_pub.R") 后调用。
#' 确保所有图（包括未显式使用 theme_pub() 的图）的
#' 点、线、误差线等基础几何样式一致。
#'
#' @export
set_pub_defaults <- function() {
  update_geom_defaults("point", list(size = 1))
  update_geom_defaults("line",  list(linewidth = 0.6))
  update_geom_defaults("smooth", list(linewidth = 0.7))
  update_geom_defaults("errorbar", list(linewidth = 0.4))
  update_geom_defaults("boxplot", list(linewidth = 0.45))
  update_geom_defaults("hline", list(linewidth = 0.4))
  update_geom_defaults("vline", list(linewidth = 0.4))
}


# ============================================================
# 主题预设别名（按图片类型）
# ============================================================

#' 单栏图主题（宽 8.5 cm / 3.35 in）
#' @export
theme_pub_single <- function(...) {
  theme_pub(...)
}

#' 双栏图主题（宽 17 cm / 6.69 in）
#' @export
theme_pub_double <- function(...) {
  theme_pub(...)
}
