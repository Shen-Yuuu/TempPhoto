# 「临时相机」正式设计文档

> 版本：v1.1
> 日期：2026-09-15（2026-09-19 修订）
> 状态：已批准（用户确认方案C + 自定义相机 + MVP含备注标签）
> 目标平台：HarmonyOS NEXT（原定 API 21 / SDK 6.0.1(21)，实现期已升级至 **API 26 / SDK 26.0.0**，启用 Grid 多选、Refresh、systemMaterial、@Env 等新特性），phone

---

## 1. 产品概述

### 1.1 一句话定位

拍完就约定什么时候删除——为"工具性照片"服务的临时相机。

### 1.2 核心理念

普通相册默认每张照片都值得永久保存；本App默认**大多数工具性照片完成使命后就应该消失**。

用户拍照前先约定保存期限，照片只进入App的临时空间，**不污染系统相册**。到期后静默清理，无需用户操心。

### 1.3 典型场景

停车位置、快递取件码、临时白板、货架位置、家具尺寸、储物柜编号、酒店房间号、临时参考图、稍后要输入的号码。

### 1.4 MVP 范围（已确认）

| 能力 | 说明 | 优先级 |
| --- | --- | --- |
| 独立拍照 | 应用内自定义相机，照片不进系统相册 | P0 |
| 设置寿命 | 1小时 / 今天结束 / 3天 / 7天 / 永久 | P0 |
| 到期清理 | 静默删除，主机制延迟任务+启动兜底 | P0 |
| 转为永久 | 到期前一键转永久保留 | P0 |
| 本地存储 | 全量沙箱存储，不上传云端 | P0 |
| 备注标签 | 拍后可加一句话备注（如"3号储物柜"） | P0（用户追加） |
| 首页统计 | 今天/7天内/永久 三桶统计 | P0 |
| 修改寿命 | 详情页可延期或缩短寿命 | P1 |
| 设置页 | 默认寿命偏好记忆 | P1（简化为记忆上次选择） |

明确不做（YAGNI）：云端同步、分享导出到系统相册（P2再议）、相册导入、视频、多端。

---

## 2. 总体架构

### 2.1 架构形态

单HAP（entry模块），三层结构：

```
┌─────────────────────────────────────────────┐
│  UI层（ArkUI 声明式，状态管理 V2）              │
│  Index首页 / CameraPage拍照页 / DetailPage详情  │
├─────────────────────────────────────────────┤
│  业务层（Service）                             │
│  PhotoRepository    照片存取编排               │
│  ExpiryCalculator   寿命→到期时间计算          │
│  CleanupService     到期清理（UI与后台共用）     │
├─────────────────────────────────────────────┤
│  数据层                                       │
│  DbHelper(RelationalStore)  元数据             │
│  沙箱文件目录 filesDir/temp_photos/            │
└─────────────────────────────────────────────┘
        ▲ 后台入口
WorkSchedulerExtensionAbility（延迟任务回调，复用数据层+业务层）
```

### 2.2 技术选型

| 领域 | 选型 | 理由 |
| --- | --- | --- |
| UI框架 | ArkUI，状态管理V2（@Local/@Param/@ObservedV2/@Monitor） | API 21 推荐，观察粒度细 |
| 相机 | Camera Kit（`@ohos.multimedia.camera`）+ XComponent 自定义相机 | 拍照直接进沙箱，彻底不碰媒体库（用户已确认） |
| 图像编码 | `@ohos.multimedia.image`（ImageReceiver → ImagePacker） | 拍照YUV/RGBA流转JPEG文件 |
| 元数据 | RelationalStore（RDB/SQLite） | 结构化查询（按expire_at分桶统计、到期扫描） |
| 文件 | 应用沙箱 `context.filesDir` | 免存储权限，卸载即全清，天然隔离相册 |
| 后台清理 | workScheduler 延迟任务（方案C） | 平台约束下的最优解（见§4） |
| 路由 | 系统 `router`（@ohos.router） | 3个页面，无需Navigation复杂栈 |

### 2.3 目录结构（规划）

```
entry/src/main/ets/
├── entryability/EntryAbility.ets          # 启动补清理挂载点
├── workscheduler/CleanupExtension.ets     # WorkSchedulerExtensionAbility
├── pages/
│   ├── Index.ets                          # 首页：统计+宫格+拍照入口
│   ├── CameraPage.ets                     # 自定义相机
│   └── DetailPage.ets                     # 详情：备注/转永久/改寿命/删除
├── components/
│   ├── DurationSelector.ets               # 寿命选择条
│   ├── PhotoGridItem.ets                  # 照片卡片（倒计时徽标）
│   └── StatsHeader.ets                    # 三桶统计卡片
├── model/
│   ├── PhotoRecord.ets                    # 照片实体
│   └── DurationType.ets                   # 寿命枚举与工具
├── database/DbHelper.ets                  # RDB建表/CRUD/统计查询
├── service/
│   ├── PhotoRepository.ets                # 存取编排（文件+DB一致性）
│   ├── ExpiryCalculator.ets               # 到期时间计算
│   └── CleanupService.ets                 # 扫描并删除到期照片
└── utils/TimeUtil.ets
```

---

## 3. 数据模型

### 3.1 photos 表

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | INTEGER PK AUTOINCREMENT | 主键 |
| file_path | TEXT NOT NULL | 沙箱内相对路径（`temp_photos/xxx.jpg`） |
| note | TEXT | 备注标签，可空 |
| created_at | INTEGER NOT NULL | 拍摄时间（毫秒时间戳） |
| expire_at | INTEGER | 到期时间戳；**NULL = 永久** |
| duration_type | INTEGER NOT NULL | 1=1小时 2=今天结束 3=3天 4=7天 5=永久（记录用户原始选择，改寿命后同步更新） |

索引：`expire_at`（到期扫描、分桶统计）、`created_at DESC`（列表排序）。

### 3.2 到期时间计算规则（ExpiryCalculator）

| 寿命 | expire_at |
| --- | --- |
| 1小时 | created_at + 3_600_000 |
| 今天结束 | 本地时区当天 24:00:00.000 |
| 3天 | created_at + 3×86_400_000 |
| 7天 | created_at + 7×86_400_000 |
| 永久 | NULL |

注："今天结束"取本地时区次日零点，跨天拍摄（23:59拍）寿命可能只有1分钟，属预期行为，UI展示实际剩余时间。

### 3.3 文件组织

```
filesDir/temp_photos/{yyyyMMdd}/{timestamp}_{rand}.jpg
```

按天分目录便于排查；删除时先删记录再删文件（见§6.5一致性）。

---

## 4. 到期清理策略（核心设计，方案C）

### 4.1 平台约束（调研结论，必须遵守）

鸿蒙 workScheduler 延迟任务：
1. 单应用**最多同时10个**延迟任务；
2. 系统按内存/功耗/温度/用户习惯统一调度，**最小间隔2小时**（活跃分组），不保证准点；
3. "极少使用/受限"分组任务可能不被调度；
4. 单次 `onWorkStart` 回调最长运行 **2分钟**，超时进程被终止。

### 4.2 策略设计

- **主机制：单一可重复延迟任务**。全App仅注册 1 个 `WorkInfo`（`isRepeat: true`，触发条件尽量宽松：不要求网络/充电），系统每次调度时在 `onWorkStart` 中**批量清理所有 `expire_at <= now` 的照片**。天然支持10张以上照片，且改寿命/转永久无需增删任务。
- **兜底机制：启动/回前台补清理**。`EntryAbility.onCreate` 与 `onForeground` 调用同一 `CleanupService.sweepExpired()`，覆盖延迟任务未被调度的情形，并顺带修复"删除记录但文件残留"等不一致。
- **任务保活**：每次成功保存照片时检查任务是否在册（`obtainAllWorks`），不在则重新 `startWork`；应用被卸载重装后由首次拍照/启动重建。

### 4.3 清理语义（用户已确认）

静默处理：不发到期提醒通知、不弹窗、不打开App。照片到期后**通常在2小时内**被系统调度清理；极端情况（设备深度休眠、应用被降级）延迟至下次打开App时补删。设计文档如实向用户传达该非精确性。

### 4.4 清理流程

```
WorkSchedulerExtensionAbility.onWorkStart(work)
  → CleanupService.sweepExpired()
      → SELECT id,file_path FROM photos WHERE expire_at IS NOT NULL AND expire_at <= now
      → 逐条: 删除DB记录 → 删除沙箱文件（失败仅记日志，孤儿文件由下次sweep的孤儿扫描清理）
  → workScheduler.stopWork? 否（isRepeat任务保持重复）
  → onWorkStop 正常返回
```

2分钟时限评估：删除数千条记录+文件远小于2分钟，安全；仍需在回调内避免任何耗时网络操作。

---

## 5. 页面设计

### 5.1 首页 Index

- **顶部统计区（StatsHeader）**：三桶统计卡片
  - `今天将自动清理 X 张`：expire_at ∈ (now, 今日24点]
  - `7天内将清理 X 张`：expire_at ∈ (今日24点, now+7天]（因最大寿命档位为7天，实现取 expire_at > 今日24点）
  - `永久保留 X 张`：expire_at IS NULL
- **照片宫格**：3列，按 `created_at DESC`；卡片显示缩略图 + 底部剩余时间徽标（"剩2小时13分"/"今晚到期"/"剩3天"/"永久"）+ 备注文本（有则单行截断）；点击进详情。
- **底部拍照按钮**：居中大按钮，进入拍照页。
- 空态：引导插画 + "拍一张临时照片"。

### 5.2 拍照页 CameraPage

- **取景区**：XComponent 全屏预览，支持点击对焦（P1）、前后摄切换、闪光灯开关。
- **寿命选择条（DurationSelector）**：快门上方横向5档（1小时/今天/3天/7天/永久），**默认记忆上次选择**（Preferences 持久化）；选择"今天"档位下补充显示"今晚 24:00 删除"。
- **快门**：拍照 → 流转JPEG写沙箱 → 元数据入库（含用户选择档位）→ 确保延迟任务在册 → 轻提示"已保存 · 今晚24:00自动删除" → 返回首页（保持相机页可连拍：提示后留在取景界面，1.5s后提示消失，M1先做"拍后返回首页"，M5优化为连拍）。
- **权限**：首次进入申请 `ohos.permission.CAMERA`，拒绝则展示引导页（说明+跳设置）。

### 5.3 详情页 DetailPage

- **大图**：Image 加载沙箱文件，双指缩放（P1）。
- **信息区**：拍摄时间、所选寿命、剩余时间（实时倒计时文本）。
- **备注**：单行 TextEditor，失焦或点保存即更新DB。
- **操作条**：
  - `转为永久`：expire_at 置 NULL，duration_type=5，徽标即刻变"永久"，二次确认弹窗；
  - `修改寿命`（P1）：复用 DurationSelector 弹窗，重算 expire_at；
  - `立即删除`：二次确认，删除记录+文件，返回首页。

---

## 6. 核心功能链路

### 6.1 拍照保存链路

```
[拍照页] 快门按下
 → camera.PhotoSession.capture()
 → onPhotoAvailable(PhotoOutput)
 → Image → ImagePacker 编码JPEG(质量90)
 → fs 写入 filesDir/temp_photos/{yyyyMMdd}/{ts}_{rand}.jpg
 → DbHelper.insert(PhotoRecord{file_path, note:'', expire_at=ExpiryCalculator.calc(所选档), duration_type})
 → WorkSchedulerGuard.ensureRegistered()   // 幂等
 → 提示"已保存 · {到期描述}" → 返回首页 → 宫格刷新（@ObservedV2 数据源通知）
```

失败处理：相机启动失败/编码失败 → Toast + 停留在取景区；写文件成功但DB失败 → 回滚删除文件（见6.5）。

### 6.2 查看链路

```
[首页] onPageshow → PhotoRepository.listAll() → 宫格渲染
 点击卡片 → router.pushUrl(DetailPage, {id})
 → 查单条 → Image(source: file://filesDir/...) 渲染
```

### 6.3 清理链路（后台）

见 §4.4。前台触发版：`EntryAbility.onCreate/onForeground → CleanupService.sweepExpired()`。

### 6.4 转永久链路

```
[详情页] 点击"转为永久" → 确认弹窗
 → DbHelper.update(id, {expire_at: NULL, duration_type: 5})
 → 徽标变"永久"，首页统计桶即时刷新
 （延迟任务无需变更：sweep 查询天然跳过 NULL）
```

### 6.5 数据一致性（错误处理核心）

- **保存**：先写文件后写DB；DB失败则回滚删文件；DB成功即视为已保存（文件删除失败在清理期兜底）。
- **清理/手动删除**：先删DB记录后删文件；文件删除失败仅记日志（避免"记录在、文件丢"的坏图体验），孤儿文件由 sweep 的孤儿扫描（扫描目录中不在DB的文件，超过1天则删）回收。
- **DB损坏**：RDB 安全加密配置，DB异常时提示用户并降级为仅文件浏览（P2，MVP记日志即可）。

### 6.6 状态刷新机制

- 列表数据源用 `@ObservedV2` 集合；Repository 每次变更后首页 `onPageShow` 重新查询（3页小数据量，直查即可，无需事件总线）。
- 倒计时徽标：`setTimeout` 每60s刷新剩余文本；页面隐藏时清除定时器。

---

## 7. 权限与合规

| 权限 | 用途 | 申请时机 |
| --- | --- | --- |
| ohos.permission.CAMERA | 自定义相机取景与拍照 | 首次进入拍照页 |

不申请：存储权限（沙箱免权限）、媒体库读写（不触碰）、通知（静默策略）、网络（无上传）。

隐私声明口径：所有照片仅存于设备本地App沙箱，不上传任何服务器，卸载App即全部删除。

---

## 8. 测试策略

| 层 | 方式 | 重点用例 |
| --- | --- | --- |
| 单元 | ExpiryCalculator（5档位边界：23:59拍"今天"、闰秒/时区）、DbHelper CRUD/分桶统计SQL | 纯逻辑 |
| 集成 | CleanupService：构造过期/永久/临界记录，验证只删过期、孤儿回收 | 临时DB+临时目录 |
| 手工/设备 | 相机全流程（授权/拒绝/前后摄/闪光灯）、延迟任务（`hidumper -s 1904 -a '-t {bundle} {ability}'`手动触发回调验证清理）、转永久后过期不被删、冷启动补清理 | 真机/模拟器 |
| 回归 | 卸载重装 → 首次拍照重建延迟任务 | 设备 |

---

## 9. 里程碑计划（估6.5人天）

| 里程碑 | 内容 | 工期 | 验收标准 |
| --- | --- | --- | --- |
| M0 数据层 | 目录结构、DbHelper建表CRUD、ExpiryCalculator、单元自测 | 0.5d | CRUD与5档到期计算全通过 |
| M1 自定义相机 | 权限申请、XComponent预览、拍照编码落盘、入库 | 2d | 真机拍照→沙箱出现文件→DB有记录，系统相册无新增 |
| M2 首页 | 宫格列表、三桶统计、倒计时徽标、空态 | 1d | 拍后回首页即时可见，统计数字正确 |
| M3 详情页 | 大图、备注编辑、转永久、立即删除（P1:改寿命） | 1d | 转永久后过期不被清理 |
| M4 到期清理 | WorkSchedulerExtension、WorkSchedulerGuard、启动补清理、孤儿扫描 | 1d | hidumper手动触发回调清理过期照片；永久/未到期不动 |
| M5 联调打磨 | 权限拒绝引导、连拍体验、异常回滚、全链路回归 | 1d | 全部测试用例通过 |

依赖关系：M1依赖M0；M2依赖M1（有数据可显示）；M4可与M2/M3并行；M5收尾。

---

## 10. 后续演进（P2+，MVP不做）

- 手动导出到系统相册/分享（photoAccessHelper，需用户显式授权）
- 相册导入并设寿命
- 到期前通知提醒（受平台代理提醒管控，工具类应用可申请）
- 抬手亮屏快捷拍照（Widget/元服务）
- 视频短记

---

## 附录A：备选方案决策记录

| 决策点 | 选项 | 结论 | 理由 |
| --- | --- | --- | --- |
| 相机 | A系统CameraPicker / B自定义相机 | B | Picker拍完先进系统相册，违背"不污染相册"核心亮点；B直落沙箱（用户确认） |
| 清理 | A纯惰性 / B每照片一任务 / C单一重复任务+启动兜底 | C | 平台10任务上限击穿B；A不满足"不打开App"；C在约束内最大化静默清理概率（用户确认，接受非精确性） |
| 存储 | 沙箱文件+RDB元数据 | — | 免权限、卸载即清、结构化查询需求 |
| 通知 | 静默 / 到期提醒 | 静默 | 用户明确选择；规避代理提醒权限风险 |

## 附录B：实现差异记录（2026-09-19 审查后确认）

实现过程中相对本文档发生如下演进，以本节为准：

1. **改寿命基准时间**：详情页/首页菜单改寿命一律**以当前时间起算**（`Date.now()`），不再按 `created_at` 重算。旧照片改"1小时"即从现在起1小时后删除；`duration_type` 同步更新。`PhotoRepository.changeDuration` 是该策略唯一实现点。
2. **首页分桶口径**："今天到期"桶包含**已过期但尚未被清理**的照片（`expire_at <= 今日24点`，含过期），徽标显示"待清理"；"7天内到期"为 `expire_at > 今日24点`。三桶互斥完备。
3. **超出 MVP 的新增功能**：分享（systemShare 面板）、存系统相册（`showAssetsCreationDialog` 安全组件，免媒体库权限）、首页 Grid 双指多选批量分享/删除、首页分组视图（今天/7天/永久三段）、长按菜单改寿命、下拉刷新、点击对焦+追焦、详情页环形进度与双指缩放。
4. **延迟任务生命周期**：设备重启后 workScheduler 任务不保留（第三方无法持久化），除拍照时注册外，`EntryAbility.onCreate` 也会补注册（幂等，workId=1001），避免"重启后只打开App不拍照"导致后台清理长期失效。
5. **清理自愈**：sweep 的对账（reconcile）为双向——除回收"有文件无记录"的孤儿文件外，还会删除"**有记录无文件**"且记录已超过 1 天宽限期的残留记录，保证文件意外丢失后 UI 不会永久残留坏图。
6. **数据安全**：RDB `securityLevel` 取 S2（照片元数据属个人数据）。
7. **拍照旋转**：`rotation` 不再固定 0°，由 `PhotoOutput.getPhotoRotation()`（API 23+ 无参调用）按设备方向动态计算，避免竖拍照片横倒。
