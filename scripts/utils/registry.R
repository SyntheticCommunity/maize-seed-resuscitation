# ============================================================
# registry.R — 全篇统一 Visual Registry
#
# 用法:
#   source("scripts/utils/registry.R")
#
#   按变量取值:
#     reg_color("genus")      → c(Pantoea = "#E64B35", Burkholderia = "#4DBBD5")
#     reg_shape("treatment")  → c(CK = 16, BG = 17, SynCom = 15)
#
#   作为 ggplot2 scale 使用:
#     ggplot(...) +
#       scale_color_manual(values = reg_color("genus")) +
#       scale_shape_manual(values = reg_shape("genus"))
#
#   或使用快捷函数:
#     ggplot(...) + scale_color_genus() + scale_shape_genus()
#
# 核心原则:
#   - 颜色绑定到变量（Treatment/Genus/…），不绑定到图
#   - 同一变量跨章节颜色一致
#   - 不同变量的颜色空间彼此隔离，避免语义冲突
# ============================================================

library(ggplot2)

# ============================================================
# 注册表核心数据
# ============================================================

.registry <- list(

  # ----------------------------------------------------------
  # 1. 属水平 Genus（全书最核心生物学变量）
  #    Pantoea = #E64B35（NPG 红/vermilion）
  #    Burkholderia = #4DBBD5（NPG 蓝/teal）
  # ----------------------------------------------------------
  genus = list(
    levels  = c("Pantoea", "Burkholderia"),
    color   = c("Pantoea" = "#E64B35", "Burkholderia" = "#4DBBD5"),
    shape   = c("Pantoea" = 16, "Burkholderia" = 17),
    linetype = c("Pantoea" = "solid", "Burkholderia" = "dashed")
  ),

  # ----------------------------------------------------------
  # 2. 处理水平 Treatment（CK / BG / SynCom）
  #    CK = 灰（对照，中性）
  #    BG = NPG 绿
  #    SynCom = 橙
  # ----------------------------------------------------------
  treatment = list(
    levels  = c("CK", "BG", "SynCom"),
    color   = c("CK" = "#808080", "BG" = "#00A087", "SynCom" = "#D55E00"),
    shape   = c("CK" = 16, "BG" = 17, "SynCom" = 15),
    linetype = c("CK" = "solid", "BG" = "dashed", "SynCom" = "dotdash")
  ),

  # ----------------------------------------------------------
  # 3. 样本类型（lanc 队列：soil / OC / RC）
  #    顺序：soil → OC → RC
  #    soil  = 暗棕色（土壤）
  #    OC    = 金黄色（玉米种子）
  #    RC    = 深绿色（复苏/生命色）
  # ----------------------------------------------------------
  sample_type = list(
    levels  = c("soil", "OC", "RC"),
    color   = c("soil" = "#5D3A1A", "OC" = "#DAA520", "RC" = "#2E7D32"),
    shape   = c("soil" = 16, "OC" = 17, "RC" = 15)
  ),

  # ----------------------------------------------------------
  # 4. 隔室（wucl 队列：seed / water）
  # ----------------------------------------------------------
  compartment = list(
    levels  = c("seed", "water"),
    color   = c("seed" = "#3C5488", "water" = "#91D1C2"),
    shape   = c("seed" = 16, "water" = 17)
  ),

  # ----------------------------------------------------------
  # 5. 种质类型 Material Type（自交系 vs 杂交种 → 不同色系）
  #
  #    自交系（inbred lines）：Blues 色系
  #      - inbred lines（类） = #2171B5（深蓝，基础类）
  #      - SS  = #DEEBF7（极浅蓝）
  #      - NSS = #6BAED6（中蓝）
  #      - TST = #9ECAE1（浅蓝）
  #
  #    杂交种（landraces）：Golden 色系
  #      - landraces（类） = #CC7A00（深金，基础类）
  #      - 3K   = #FEE7C0（浅金黄）
  #      - Tibet= #FDAA3A（中金黄）
  # ----------------------------------------------------------
  material_type = list(
    levels  = c("inbred lines", "landraces"),
    color   = c("inbred lines" = "#2171B5", "landraces" = "#CC7A00"),
    shape   = c("inbred lines" = 16, "landraces" = 17)
  ),

  # ----------------------------------------------------------
  # 6. 遗传群 Genetic Group
  #    顺序：SS → NSS → TST → 3K → Tibet
  #    按所属种质类型分属不同色系：
  #      自交系分支 → Blues：SS → NSS → TST（浅→深）
  #      杂交种分支 → Golden：3K → Tibet（浅→深）
  # ----------------------------------------------------------
  genetic_group = list(
    levels  = c("SS", "NSS", "TST", "3K", "Tibet"),
    color   = c("SS" = "#DEEBF7", "NSS" = "#6BAED6",
                "TST" = "#9ECAE1", "3K" = "#FEE7C0",
                "Tibet" = "#FDAA3A"),
    shape   = c("SS" = 16, "NSS" = 15, "TST" = 17,
                "3K" = 18, "Tibet" = 8)
  ),

  # ----------------------------------------------------------
  # 7. 种水平 Species（与属颜色对齐）
  #    顺序：Pantoea dispersa → Pantoea stewartii → Burkholderia gladioli
  #    P. dispersa  → Pantoea 红
  #    P. stewartii → Pantoea 红系（略暗）
  #    B. gladioli  → Burkholderia 蓝
  # ----------------------------------------------------------
  species = list(
    levels  = c("Pantoea dispersa", "Pantoea stewartii", "Burkholderia gladioli"),
    color   = c("Pantoea dispersa" = "#E64B35",
                "Pantoea stewartii" = "#C43A23",
                "Burkholderia gladioli" = "#4DBBD5"),
    shape   = c("Pantoea dispersa" = 16,
                "Pantoea stewartii" = 15,
                "Burkholderia gladioli" = 17)
  ),

  # ----------------------------------------------------------
  # 8. 温室处理（SMT / WMT）
  #    保持 greenhouse-trials.qmd 现有赋值
  # ----------------------------------------------------------
  greenhouse_treatment = list(
    levels  = c("SMT", "WMT"),
    color   = c("SMT" = "#E69F00", "WMT" = "#56B4E9"),
    shape   = c("SMT" = 16, "WMT" = 17)
  ),

  # ----------------------------------------------------------
  # 9. 转录组比较组（Control / Treatment）
  #    Control  = CK 灰
  #    Treatment = SynCom 橙
  #    跨章节颜色一致
  # ----------------------------------------------------------
  group_comparison = list(
    levels  = c("Control", "Treatment"),
    color   = c("Control" = "#808080", "Treatment" = "#D55E00"),
    shape   = c("Control" = 16, "Treatment" = 17)
  ),

  # ----------------------------------------------------------
  # 10. 变化方向（统一：RNA-seq / Metabolite / BIOLOG）
  #     增 / Up / Produced        = 红 #D73027
  #     减 / Down / Consumed      = 蓝 #4575B4
  #     不变 / NotSig / NoChange  = 浅灰 #BDBDBD
  #
  #     与属颜色（#E64B35 / #4DBBD5）有所区别以防混淆
  #     但保持红-蓝语义对立
  # ----------------------------------------------------------
  direction = list(
    levels  = c("Up", "Down", "NotSig",
                "Produced", "Consumed",
                "Increase", "Decrease", "NoChange"),
    color   = c("Up" = "#D73027", "Down" = "#4575B4", "NotSig" = "#BDBDBD",
                "Produced" = "#D73027", "Consumed" = "#4575B4",
                "Increase" = "#D73027", "Decrease" = "#4575B4",
                "NoChange" = "#BDBDBD")
  ),

  # ----------------------------------------------------------
  # 11. 染色体（Burkholderia Chr1 / Chr2）
  #     与 Burkholderia 统一色调（NPG 蓝系）
  #     Chr1 = 主染色体 → 标准 Burkholderia 蓝
  #     Chr2 = 次染色体 → 略暗同色系
  # ----------------------------------------------------------
  chromosome = list(
    levels  = c("Chr1", "Chr2"),
    color   = c("Chr1" = "#4DBBD5", "Chr2" = "#2A8B9E"),
    shape   = c("Chr1" = 16, "Chr2" = 17)
  ),

  # ----------------------------------------------------------
  # 12. 共线性方向（+ / -）
  # ----------------------------------------------------------
  orientation = list(
    levels  = c("+", "-"),
    color   = c("+" = "#E64B35", "-" = "#4DBBD5")
  ),

  # ----------------------------------------------------------
  # 13. PGP 功能分组（KEGG 功能注释）
  #     注意：此处的 CK = Cytokinin（植物激素），
  #     与 treatment 的 CK（Control）含义不同，勿混淆
  # ----------------------------------------------------------
  pgp_group = list(
    levels  = c("Nitrogen", "Phosphorus", "Siderophore", "IAA",
                "GA", "CK", "ACC_deaminase", "ET", "ABA", "SA"),
    color   = c("Nitrogen" = "#08306B",
                "Phosphorus" = "#08519C",
                "Siderophore" = "#3182CE",
                "IAA" = "#00441B",
                "GA" = "#1A9850",
                "CK" = "#A1D99B",
                "ACC_deaminase" = "#6B0000",
                "ET" = "#E6550D",
                "ABA" = "#FEE6CE",
                "SA" = "#fdfdfc")
  )
)


# ============================================================
# 取值函数
# ============================================================

#' 获取变量的颜色映射
#' @param var 变量名（如 "genus", "treatment", "sample_type"）
#' @return 命名字符向量，可用作 scale_color_manual(values = ...)
#' @export
reg_color <- function(var) {
  .registry[[var]]$color
}

#' 获取变量的形状映射
#' @param var 变量名
#' @return 命名字符向量
#' @export
reg_shape <- function(var) {
  .registry[[var]]$shape
}

#' 获取变量的线型映射
#' @param var 变量名
#' @return 命名字符向量
#' @export
reg_linetype <- function(var) {
  .registry[[var]]$linetype
}

#' 获取变量的规范水平顺序
#'
#' 返回变量在全书统一的因子水平顺序，用于:
#'   factor(x, levels = reg_levels("genus"))
#' 或直接用 reg_factor() 一步到位。
#'
#' @param var 变量名
#' @return 字符向量，水平从先到后
#' @export
reg_levels <- function(var) {
  .registry[[var]]$levels
}

#' 将向量转为规范因子的便捷函数
#'
#' @param x   待转换的字符/因子向量
#' @param var 变量名（在 registry 中定义的）
#' @return factor，水平顺序与全书一致
#' @export
reg_factor <- function(x, var) {
  factor(x, levels = reg_levels(var))
}

#' 获取变量的所有映射
#' @param var 变量名
#' @return 包含 levels, color, shape, linetype 的列表
#' @export
reg_get <- function(var) {
  .registry[[var]]
}

#' 列出注册表中所有变量
#' @export
reg_list <- function() {
  names(.registry)
}


# ============================================================
# 快捷 scale 函数
# ============================================================
# 每个变量提供 scale_color_*() 和 scale_fill_*()
# 例: ggplot(...) + scale_color_genus() + scale_shape_genus()
# ============================================================

# ---- genus ----
#' @export
scale_color_genus <- function(...) {
  scale_color_manual(values = reg_color("genus"), ...)
}
#' @export
scale_fill_genus <- function(...) {
  scale_fill_manual(values = reg_color("genus"), ...)
}
#' @export
scale_shape_genus <- function(...) {
  scale_shape_manual(values = reg_shape("genus"), ...)
}

# ---- treatment ----
#' @export
scale_color_treatment <- function(...) {
  scale_color_manual(values = reg_color("treatment"), ...)
}
#' @export
scale_fill_treatment <- function(...) {
  scale_fill_manual(values = reg_color("treatment"), ...)
}
#' @export
scale_shape_treatment <- function(...) {
  scale_shape_manual(values = reg_shape("treatment"), ...)
}

# ---- sample_type (soil/OC/RC) ----
#' @export
scale_color_sample_type <- function(...) {
  scale_color_manual(values = reg_color("sample_type"), ...)
}
#' @export
scale_fill_sample_type <- function(...) {
  scale_fill_manual(values = reg_color("sample_type"), ...)
}

# ---- compartment (seed/water) ----
#' @export
scale_color_compartment <- function(...) {
  scale_color_manual(values = reg_color("compartment"), ...)
}
#' @export
scale_fill_compartment <- function(...) {
  scale_fill_manual(values = reg_color("compartment"), ...)
}

# ---- material_type ----
#' @export
scale_color_material_type <- function(...) {
  scale_color_manual(values = reg_color("material_type"), ...)
}
#' @export
scale_fill_material_type <- function(...) {
  scale_fill_manual(values = reg_color("material_type"), ...)
}

# ---- genetic_group ----
#' @export
scale_color_genetic_group <- function(...) {
  scale_color_manual(values = reg_color("genetic_group"), ...)
}
#' @export
scale_fill_genetic_group <- function(...) {
  scale_fill_manual(values = reg_color("genetic_group"), ...)
}
#' @export
scale_shape_genetic_group <- function(...) {
  scale_shape_manual(values = reg_shape("genetic_group"), ...)
}

# ---- species ----
#' @export
scale_color_species <- function(...) {
  scale_color_manual(values = reg_color("species"), ...)
}
#' @export
scale_fill_species <- function(...) {
  scale_fill_manual(values = reg_color("species"), ...)
}

# ---- greenhouse_treatment ----
#' @export
scale_color_greenhouse <- function(...) {
  scale_color_manual(values = reg_color("greenhouse_treatment"), ...)
}
#' @export
scale_fill_greenhouse <- function(...) {
  scale_fill_manual(values = reg_color("greenhouse_treatment"), ...)
}

# ---- group_comparison (Control/Treatment) ----
#' @export
scale_color_comparison <- function(...) {
  scale_color_manual(values = reg_color("group_comparison"), ...)
}
#' @export
scale_fill_comparison <- function(...) {
  scale_fill_manual(values = reg_color("group_comparison"), ...)
}

# ---- direction（统一：RNA-seq/Metabolite/BIOLOG） ----
#' @export
scale_color_direction <- function(...) {
  scale_color_manual(values = reg_color("direction"), ...)
}
#' @export
scale_fill_direction <- function(...) {
  scale_fill_manual(values = reg_color("direction"), ...)
}

# ---- chromosome ----
#' @export
scale_color_chromosome <- function(...) {
  scale_color_manual(values = reg_color("chromosome"), ...)
}
#' @export
scale_fill_chromosome <- function(...) {
  scale_fill_manual(values = reg_color("chromosome"), ...)
}
