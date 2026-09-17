# UI 2.0 深度打磨设计（纸感风格保留升级）

日期：2026-09-16
方向：保留现有米白/墨色/橘色的纸感清单风格，做深度打磨（不换设计语言）。
前提：不回退已接入的 13 项 API 26 特性（Grid 多选、Refresh、systemMaterial、追焦、手势并行等）。

## 1. 设计令牌（Theme.ets 2.0）
- 阴影三级：`shadowSm`（卡片微浮）、`shadowMd`（弹层）、`shadowLg`（模态）
- 圆角令牌：RADIUS_SM=10 / RADIUS_MD=14 / RADIUS_LG=20 / RADIUS_PILL=999
- 间距常量：SPACE_XS=4 / SPACE_SM=8 / SPACE_MD=16 / SPACE_LG=24
- 新增色：`BADGE_BG = 'rgba(28,26,23,0.72)'`（网格徽章半透明墨底）

## 2. 按压反馈（utils/PressScaleModifier.ets）
- `PressScaleModifier extends CommonModifier`（kit 导出），重写 `applyNormalAttribute`（scale 1）
  与 `applyPressedAttribute`（scale 0.96），全局应用于可点击卡片/按钮/网格项。
- 依据：common.d.ts:16148 AttributeModifier 含 applyPressedAttribute；CommonAttribute 为全局声明。

## 3. Index 2.0
- 头部：日期行改为 overline 风格（11fp、letterSpacing 2、DIM 色），主标题 26fp Bold，副标题保留
- StatsHeader 重构：三张数字统计卡（色点 + 22fp tnum 大数字 + 11fp 标签，白底 RADIUS_MD + shadowSm），
  下方保留分组分布条
- CTA（拍一张）：墨色渐变（INK → #3A342D）+ PressScaleModifier + 快门圆点
- 空状态：重绘插画元素 + 呼吸动画（scale 1→1.04，iterations -1，playMode Alternate）
- 多选按钮加 PressScaleModifier

## 4. PhotoGridItem 2.0
- 寿命徽章：半透明墨底（BADGE_BG）白字，右下角 10fp，替代现有色块
- 整卡按压反馈（PressScaleModifier，scale 不影响 GridItem 布局）
- 图片圆角统一 RADIUS_SM；说明行颜色加深为 INK2 提升可读性

## 5. CameraPage 2.0
- 取景器内右上浮动控制条：闪光/翻转按钮（40vp 圆、rgba(255,255,255,0.92) 底、墨色 SVG 图标）
- 底部快门升级：外环 74vp 白 + 内芯 58vp 橘渐变，按压 PressScaleModifier
- 新增 SVG：ic_flash_on / ic_flash_off / ic_flip

## 6. DetailPage 2.0
- 剩余寿命区：环形进度（`Path` SVG arc 命令自绘进度弧 + `Circle` 浅色轨道，直径 108、
  strokeWidth 10、Round 端帽），颜色按紧急度：>50% ACCENT / 20~50% TODAY / <20% DANGER
  （Gauge 默认轨道色不可控、Arc 形状组件 API 26 已移除，故用 Path+Circle 确定性方案）
- 中心大号剩余时间文本（tnum）+ 小字状态
- 三联操作改图标卡片：改寿命（ic_timer）/ 转永久（ic_infinity）/ 删除（ic_delete）
- 分享/存相册按钮加 PressScaleModifier

## 7. 动效汇总
- 全局按压 scale 0.96（AttributeModifier，无动画直接切换，清脆）
- DurationSelector 选中态 `.animation({ duration: 180, curve: EaseOut })` 平滑过渡
- 空状态呼吸动画
- 技术依据：Arc 形状组件 API 26 已移除，环改用 Path+Circle 组合；Progress/Gauge 轨道色均不可控故弃用

## 8. 验收
- hvigor 构建零警告
- 视觉连续性：色板/字体不变，仅结构与层次升级
