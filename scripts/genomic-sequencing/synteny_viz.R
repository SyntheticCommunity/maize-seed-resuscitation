#!/usr/bin/env Rscript
#
# 共线性点图与排列图可视化辅助函数
#
# 读取 show-coords 格式的比对坐标，生成:
#   1. Dot plot（点图，参考 vs 查询的比对位置）
#   2. Synteny diagram（共线性排列图，显示各 contig 的比对关系）

library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)

#' 读取 show-coords 输出
parse_show_coords <- function(filepath) {
  lines <- read_lines(filepath)

  # 跳过前 2 行（FASTA 路径和 NUCMER）
  data_lines <- lines[3:length(lines)]
  data_lines <- data_lines[!str_detect(data_lines, "^\\[S1\\]|^===")]
  data_lines <- data_lines[str_detect(data_lines, "[0-9]")]

  if (length(data_lines) == 0) return(NULL)

  # 解析制表符分隔的列
  df <- read_tsv(I(paste(data_lines, collapse = "\n")),
                 col_names = c("S1", "E1", "S2", "E2", "LEN1", "LEN2",
                               "PCT_IDY", "LEN_R", "LEN_Q", "COV_R", "COV_Q",
                               "TAG_R", "TAG_Q"),
                 show_col_types = FALSE) %>%
    mutate(
      # 方向: 正链或负链
      orientation = if_else(
        (S1 < E1 & S2 < E2) | (S1 > E1 & S2 > E2),
        "+", "-"
      ),
      # 统一坐标为正
      ref_start = pmin(S1, E1),
      ref_end = pmax(S1, E1),
      qry_start = pmin(S2, E2),
      qry_end = pmax(S2, E2),
      ref_len = as.numeric(LEN_R),
      qry_len = as.numeric(LEN_Q)
    )

  return(df)
}


#' 读取元信息文件
parse_meta <- function(dirpath, label) {
  meta_path <- file.path(dirpath, paste0(label, ".meta.txt"))
  if (!file.exists(meta_path)) return(list())

  lines <- read_lines(meta_path)
  info <- list()
  for (l in lines) {
    parts <- str_split_fixed(l, "=", 2)
    info[[parts[1]]] <- parts[2]
  }
  return(info)
}


#' 获取基因组最大坐标用于画布设置
get_genome_bounds <- function(coord_df, meta) {
  ref_max <- if (!is.null(coord_df)) max(coord_df$ref_end, na.rm = TRUE) else 1e7
  qry_max <- if (!is.null(coord_df)) max(coord_df$qry_end, na.rm = TRUE) else 1e7
  return(list(ref_max = ref_max, qry_max = qry_max))
}


#' 为多 contig 基因组计算累积偏移，把各染色体的局部坐标拼接为全基因组坐标
#'
#' show-coords 输出中每条 contig 的坐标都是各自的局部坐标（0..contig_len），
#' 多染色体基因组（如 B. gladioli 两条染色体）若直接绘制会重叠在同一坐标轴上，
#' 使轴范围只到最大单条染色体而非全基因组。此处按 contig 长度降序累积偏移，
#' 将各染色体沿对角线依次排开，并保留 S->E 方向使反向比对呈反对角线。
#'
#' 返回 list(df = 含 ref_s/ref_e/qry_s/qry_e 全基因组坐标的坐标框,
#'           ref_bounds/qry_bounds = 各 contig 边界位置)
add_genome_offsets <- function(coord_df) {
  if (is.null(coord_df) || nrow(coord_df) == 0) {
    return(list(df = coord_df, ref_bounds = numeric(0), qry_bounds = numeric(0)))
  }

  # 各 contig 按长度降序（最大染色体在前），计算累积偏移
  ref_ctg <- coord_df %>%
    distinct(TAG_R, ref_len) %>%
    arrange(desc(ref_len)) %>%
    mutate(ref_offset = lag(cumsum(as.numeric(ref_len)), default = 0))

  qry_ctg <- coord_df %>%
    distinct(TAG_Q, qry_len) %>%
    arrange(desc(qry_len)) %>%
    mutate(qry_offset = lag(cumsum(as.numeric(qry_len)), default = 0))

  df <- coord_df %>%
    left_join(ref_ctg, by = c("TAG_R", "ref_len")) %>%
    left_join(qry_ctg, by = c("TAG_Q", "qry_len")) %>%
    mutate(
      ref_s = S1 + ref_offset,
      ref_e = E1 + ref_offset,
      qry_s = S2 + qry_offset,
      qry_e = E2 + qry_offset
    )

  list(
    df = df,
    ref_bounds = c(0, cumsum(as.numeric(ref_ctg$ref_len))),
    qry_bounds = c(0, cumsum(as.numeric(qry_ctg$qry_len)))
  )
}


#' Dot plot：参考 vs 查询的点图（全基因组坐标，多染色体沿轴依次排开）
#' - 正链显示为红色对角线
#' - 负链显示为蓝色反对角线
#' - 灰色虚线标记 contig（染色体）边界
plot_dot <- function(coord_df, meta = list(),
                     ref_label = "Reference", qry_label = "Query") {

  ref_name <- if (!is.null(meta$ref)) meta$ref else ref_label
  qry_name <- if (!is.null(meta$qry)) meta$qry else qry_label

  if (is.null(coord_df) || nrow(coord_df) == 0) {
    return(
      ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No alignment found",
                 size = 5, color = "gray50") +
        xlim(0, 1) + ylim(0, 1) +
        labs(x = ref_name, y = qry_name) +
        theme_bw(base_size = 14)
    )
  }

  off <- add_genome_offsets(coord_df)
  df <- off$df

  p <- df %>%
    ggplot() +
    geom_segment(aes(x = ref_s / 1e6, xend = ref_e / 1e6,
                     y = qry_s / 1e6, yend = qry_e / 1e6,
                     color = orientation, alpha = PCT_IDY / 100),
                 linewidth = 0.5) +
    # contig（染色体）边界线
    geom_vline(xintercept = off$ref_bounds / 1e6,
               linetype = "dashed", color = "grey80", linewidth = 0.3) +
    geom_hline(yintercept = off$qry_bounds / 1e6,
               linetype = "dashed", color = "grey80", linewidth = 0.3) +
    scale_color_manual(values = c("+" = "#E64B35", "-" = "#4DBBD5"),
                       labels = c("+" = "Forward", "-" = "Reverse")) +
    scale_alpha(guide = "none") +
    labs(x = paste0(ref_name, " (Mb)"),
         y = paste0(qry_name, " (Mb)"),
         color = "Orientation") +
    coord_fixed() +
    theme_bw(base_size = 14) +
    theme(legend.position = "top")

  return(p)
}


#' Synteny diagram：上下两行表示两个基因组，连线表示比对关系
#' 显示 contig 级别的排列
plot_synteny_diagram <- function(coord_df, meta = list(),
                                 ref_label = "Reference", qry_label = "Query") {

  ref_name <- if (!is.null(meta$ref)) meta$ref else ref_label
  qry_name <- if (!is.null(meta$qry)) meta$qry else qry_label

  if (is.null(coord_df) || nrow(coord_df) == 0) {
    return(
      ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "No alignment found",
                 size = 5, color = "gray50") +
        xlim(0, 1) + ylim(0, 1) +
        labs(x = NULL, y = NULL) +
        theme_void()
    )
  }

  # 取每个比对块的代表性位置
  blocks <- coord_df %>%
    group_by(TAG_R, TAG_Q) %>%
    summarise(
      ref_min = min(ref_start), ref_max = max(ref_end),
      qry_min = min(qry_start), qry_max = max(qry_start),
      .groups = "drop"
    )

  # 简化为共线性图：上层 ref contig，下层 qry contig，线段连接
  # 先获取 contig 边界
  ref_contigs <- coord_df %>%
    group_by(TAG_R) %>%
    summarise(start = 0, end = max(ref_end), .groups = "drop")

  qry_contigs <- coord_df %>%
    group_by(TAG_Q) %>%
    summarise(start = 0, end = max(qry_end), .groups = "drop")


  # 构建可视化数据框
  ref_pos <- ref_contigs %>%
    mutate(
      y = 2,
      mid = (start + end) / 2,
      label = str_extract(TAG_R, "[^ ]+")
    )

  qry_pos <- qry_contigs %>%
    mutate(
      y = 1,
      mid = (start + end) / 2,
      label = str_extract(TAG_Q, "[^ ]+")
    )

  # 连线（取每个比对对的中心点）
  links <- coord_df %>%
    group_by(TAG_R, TAG_Q, orientation) %>%
    summarise(
      ref_mid = mean((ref_start + ref_end) / 2),
      qry_mid = mean((qry_start + qry_end) / 2),
      .groups = "drop"
    )

  ggplot() +
    # ref contig
    geom_segment(data = ref_pos,
                 aes(x = start / 1e6, xend = end / 1e6,
                     y = y, yend = y),
                 linewidth = 6, color = "#4DBBD5", alpha = 0.7) +
    geom_text(data = ref_pos,
              aes(x = mid / 1e6, y = y, label = label),
              size = 3, vjust = -0.5) +
    # qry contig
    geom_segment(data = qry_pos,
                 aes(x = start / 1e6, xend = end / 1e6,
                     y = y, yend = y),
                 linewidth = 6, color = "#E64B35", alpha = 0.7) +
    geom_text(data = qry_pos,
              aes(x = mid / 1e6, y = y, label = label),
              size = 3, vjust = -0.5) +
    # 连线
    geom_curve(data = links,
               aes(x = ref_mid / 1e6, xend = qry_mid / 1e6,
                   y = 2, yend = 1,
                   color = orientation),
               curvature = 0.1, alpha = 0.5, linewidth = 0.3) +
    scale_color_manual(values = c("+" = "gray40", "-" = "#E64B35"),
                       labels = c("+" = "Forward", "-" = "Reverse")) +
    scale_y_continuous(limits = c(0.5, 2.8), breaks = c(1, 2),
                       labels = c(qry_name, ref_name)) +
    labs(x = "Genome position (Mb)", y = NULL, color = "Orientation") +
    theme_bw(base_size = 14) +
    theme(panel.grid = element_blank(),
          legend.position = "top")
}


#' 对某个比较对生成完整报告
report_pair <- function(dotplot_dir, label) {
  coord_path <- file.path(dotplot_dir, paste0(label, ".coords"))
  meta <- parse_meta(dotplot_dir, label)

  if (!file.exists(coord_path)) {
    return(list(coord = NULL, meta = meta, plots = NULL))
  }

  coord <- parse_show_coords(coord_path)
  ref_name <- if (!is.null(meta$ref)) meta$ref else label
  qry_name <- if (!is.null(meta$qry)) meta$qry else "query"

  dot_plot <- plot_dot(coord, meta, ref_name, qry_name)
  syn_diagram <- plot_synteny_diagram(coord, meta, ref_name, qry_name)

  return(list(
    coord = coord,
    meta = meta,
    dot_plot = dot_plot,
    syn_diagram = syn_diagram
  ))
}


#' 提取方向判别统计
summarize_blocks <- function(coord_df) {
  if (is.null(coord_df) || nrow(coord_df) == 0) return(NULL)

  coord_df %>%
    summarise(
      n_blocks = n(),
      n_forward = sum(orientation == "+"),
      n_reverse = sum(orientation == "-"),
      mean_identity = mean(PCT_IDY),
      .groups = "drop"
    )
}
