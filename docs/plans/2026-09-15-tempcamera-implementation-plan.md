# 「临时相机」实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建鸿蒙应用「临时相机」MVP——自定义相机拍照入沙箱、五档寿命、延迟任务静默到期清理、转永久、备注标签、首页三桶统计。

**Architecture:** 单HAP三层结构（UI/Service/Data）。照片文件存应用沙箱 `filesDir/temp_photos/`，元数据存 RelationalStore；清理采用方案C：单一可重复延迟任务（WorkSchedulerExtensionAbility 批量扫描）+ App 启动/回前台补清理兜底。

**Tech Stack:** ArkTS (API 21)、ArkUI 状态管理V2、Camera Kit、Image Kit（ImageReceiver）、RelationalStore、workScheduler、Hypium 测试。

**Spec:** `docs/plans/2026-09-15-tempcamera-design.md`（本计划从该设计文档推导，执行前先阅读）

## Global Constraints

- bundleName：`com.huawei.tempphoto`（AppScope/app.json5，WorkInfo 需一致）
- targetSdkVersion：`6.0.1(21)`，仅 phone 设备
- ArkTS 严格模式：禁止 `any`/`unknown`（catch 块中 `error as BusinessError` 为官方文档模式，允许）；对象字面量必须有显式类型
- 状态管理一律 V2（`@ComponentV2`/`@Local`/`@ObservedV2`/`@Trace`）
- 权限仅 `ohos.permission.CAMERA`，不申请存储/媒体库/通知/网络权限
- 寿命档位枚举值：1=1小时 2=今天结束 3=3天 4=7天 5=永久；`expire_at` 为 NULL 表示永久
- 延迟任务约束：全App唯一 workId=1001，`isRepeat: true`，onWorkStart 内禁止耗时网络操作
- UI 文案（保持一致）：`今天将自动清理 {X} 张` / `7天内将清理 {Y} 张` / `永久保留 {Z} 张`
- 项目当前非 git 仓库：Task 0 含 `git init`（用户已同意按计划管理则执行；若用户选择不用 git，跳过所有 Commit 步骤）
- 每个任务完成后必须通过：`arkts_check`（改动文件）+ 里程碑处 `build_project`

---

### Task 0: 工程准备

**Files:**
- Modify: `entry/src/main/module.json5`
- Modify: `entry/src/main/resources/base/element/string.json`
- Create: 目录骨架 `entry/src/main/ets/{pages,components,model,database,service,utils,workscheduler}`

**Interfaces:**
- Produces: CAMERA 权限声明、目录骨架，供后续任务放置文件

- [ ] **Step 1: 初始化 git（可选）**

Run: `git init`（项目根目录）
说明：项目尚未纳入版本管理；若用户不要 git 则跳过本步与所有后续 Commit 步骤。

- [ ] **Step 2: 创建目录骨架**

创建空目录：`entry/src/main/ets/components/`、`model/`、`database/`、`service/`、`utils/`、`workscheduler/`（`pages/` 已存在）。

- [ ] **Step 3: module.json5 声明 CAMERA 权限**

在 `"module"` 下新增（与 `abilities` 平级）：

```json5
"requestPermissions": [
  {
    "name": "ohos.permission.CAMERA",
    "reason": "$string:camera_permission_reason",
    "usedScene": {
      "abilities": ["EntryAbility"],
      "when": "inuse"
    }
  }
]
```

- [ ] **Step 4: string.json 增加字符串**

`entry/src/main/resources/base/element/string.json` 的 `string` 数组追加：

```json
{ "name": "camera_permission_reason", "value": "用于拍摄临时照片" },
{ "name": "app_name_camera", "value": "临时相机" }
```

（若 `app_name` 当前为模板默认值，将其 `value` 改为 `临时相机`。）

- [ ] **Step 5: 校验**

Run: `build_project`
Expected: SUCCESS（无代码改动，仅配置）

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/module.json5 entry/src/main/resources/base/element/string.json
git commit -m "chore: 声明相机权限与基础资源"
```

---

### Task 1: Model 层（DurationType / PhotoRecord）

**Files:**
- Create: `entry/src/main/ets/model/DurationType.ets`
- Create: `entry/src/main/ets/model/PhotoRecord.ets`

**Interfaces:**
- Produces（后续所有任务依赖）:
  - `enum DurationType { ONE_HOUR=1, END_OF_TODAY=2, THREE_DAYS=3, SEVEN_DAYS=4, FOREVER=5 }`
  - `DurationLabel.labelOf(type: DurationType): string`
  - `@ObservedV2 class PhotoRecord { id: number; filePath: string; note: string; createdAt: number; expireAt: number | null; durationType: DurationType }`

- [ ] **Step 1: 写 DurationType.ets**

```typescript
export enum DurationType {
  ONE_HOUR = 1,
  END_OF_TODAY = 2,
  THREE_DAYS = 3,
  SEVEN_DAYS = 4,
  FOREVER = 5
}

export class DurationLabel {
  static labelOf(type: DurationType): string {
    switch (type) {
      case DurationType.ONE_HOUR:
        return '1小时';
      case DurationType.END_OF_TODAY:
        return '今天';
      case DurationType.THREE_DAYS:
        return '3天';
      case DurationType.SEVEN_DAYS:
        return '7天';
      case DurationType.FOREVER:
        return '永久';
      default:
        return '';
    }
  }

  static all(): Array<DurationType> {
    return [
      DurationType.ONE_HOUR,
      DurationType.END_OF_TODAY,
      DurationType.THREE_DAYS,
      DurationType.SEVEN_DAYS,
      DurationType.FOREVER
    ];
  }
}
```

- [ ] **Step 2: 写 PhotoRecord.ets**

```typescript
import { ObservedV2, Trace } from '@kit.ArkUI';
import { DurationType } from './DurationType';

@ObservedV2
export class PhotoRecord {
  @Trace id: number = -1;
  @Trace filePath: string = '';
  @Trace note: string = '';
  @Trace createdAt: number = 0;
  @Trace expireAt: number | null = null;
  @Trace durationType: DurationType = DurationType.FOREVER;
}
```

- [ ] **Step 3: 校验**

Run: `arkts_check ["entry/src/main/ets/model/DurationType.ets", "entry/src/main/ets/model/PhotoRecord.ets"]`
Expected: 无 ERROR

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/model/
git commit -m "feat: 照片实体与寿命枚举模型"
```

---

### Task 2: ExpiryCalculator / TimeUtil + 本地单元测试

**Files:**
- Create: `entry/src/main/ets/utils/TimeUtil.ets`
- Create: `entry/src/main/ets/service/ExpiryCalculator.ets`
- Create: `entry/src/test/LocalUnit.test.ets`（DevEco 本地测试，无设备运行）

**Interfaces:**
- Consumes: `DurationType`
- Produces:
  - `TimeUtil.endOfToday(ts: number): number`（本地时区次日零点毫秒）
  - `TimeUtil.formatDay(ts: number): string`（`yyyyMMdd`）
  - `TimeUtil.formatRemaining(expireAt: number | null, now: number): string`
  - `ExpiryCalculator.calc(type: DurationType, createdAt: number): number | null`

- [ ] **Step 1: 写 TimeUtil.ets**

```typescript
export class TimeUtil {
  static endOfToday(ts: number): number {
    const d = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 0, 0, 0, 0).getTime();
  }

  static formatDay(ts: number): string {
    const d = new Date(ts);
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}${m}${day}`;
  }

  static formatRemaining(expireAt: number | null, now: number): string {
    if (expireAt === null) {
      return '永久';
    }
    const diff = expireAt - now;
    if (diff <= 0) {
      return '待清理';
    }
    if (diff < 3_600_000) {
      return `剩${Math.max(1, Math.floor(diff / 60_000))}分钟`;
    }
    if (diff < 86_400_000) {
      return `剩${Math.floor(diff / 3_600_000)}小时${Math.floor((diff % 3_600_000) / 60_000)}分`;
    }
    return `剩${Math.floor(diff / 86_400_000)}天`;
  }
}
```

- [ ] **Step 2: 写 ExpiryCalculator.ets**

```typescript
import { DurationType } from '../model/DurationType';
import { TimeUtil } from '../utils/TimeUtil';

export class ExpiryCalculator {
  static calc(type: DurationType, createdAt: number): number | null {
    switch (type) {
      case DurationType.ONE_HOUR:
        return createdAt + 3_600_000;
      case DurationType.END_OF_TODAY:
        return TimeUtil.endOfToday(createdAt);
      case DurationType.THREE_DAYS:
        return createdAt + 3 * 86_400_000;
      case DurationType.SEVEN_DAYS:
        return createdAt + 7 * 86_400_000;
      case DurationType.FOREVER:
        return null;
      default:
        return null;
    }
  }
}
```

- [ ] **Step 3: 写本地单元测试**

`entry/src/test/LocalUnit.test.ets`（纯逻辑，不依赖 @ohos API，可在开发机本地跑）：

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { ExpiryCalculator } from '../main/ets/service/ExpiryCalculator';
import { DurationType } from '../main/ets/model/DurationType';
import { TimeUtil } from '../main/ets/utils/TimeUtil';

export default function localUnitTest() {
  describe('ExpiryCalculatorTest', () => {
    const T0 = new Date(2026, 8, 15, 10, 0, 0, 0).getTime();

    it('oneHour', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.ONE_HOUR, T0)).assertEqual(T0 + 3_600_000);
    });
    it('endOfToday', 0, () => {
      const midnight = new Date(2026, 8, 16, 0, 0, 0, 0).getTime();
      expect(ExpiryCalculator.calc(DurationType.END_OF_TODAY, T0)).assertEqual(midnight);
    });
    it('endOfTodayNearMidnight', 0, () => {
      const t = new Date(2026, 8, 15, 23, 59, 0, 0).getTime();
      const midnight = new Date(2026, 8, 16, 0, 0, 0, 0).getTime();
      expect(ExpiryCalculator.calc(DurationType.END_OF_TODAY, t)).assertEqual(midnight);
    });
    it('threeDays', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.THREE_DAYS, T0)).assertEqual(T0 + 3 * 86_400_000);
    });
    it('sevenDays', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.SEVEN_DAYS, T0)).assertEqual(T0 + 7 * 86_400_000);
    });
    it('forever', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.FOREVER, T0)).assertNull();
    });
  });
  describe('TimeUtilTest', () => {
    it('formatDay', 0, () => {
      expect(TimeUtil.formatDay(new Date(2026, 8, 5, 8, 0, 0).getTime())).assertEqual('20260905');
    });
    it('remainingForever', 0, () => {
      expect(TimeUtil.formatRemaining(null, 1000)).assertEqual('永久');
    });
    it('remainingExpired', 0, () => {
      expect(TimeUtil.formatRemaining(500, 1000)).assertEqual('待清理');
    });
    it('remainingMinutes', 0, () => {
      expect(TimeUtil.formatRemaining(1000 + 30 * 60_000, 1000)).assertEqual('剩30分钟');
    });
  });
}
```

同时在 `entry/src/test/List.test.ets`（模板已有）中确保调用 `localUnitTest()`。

- [ ] **Step 4: 运行测试**

在 DevEco Studio 中右键 `entry/src/test` → Run 'Local Test'（本地测试无需设备）。
Expected: 10 个用例全部 PASS。（CLI 环境下可先以 arkts_check 代替，测试留待联调阶段执行。）

- [ ] **Step 5: 校验**

Run: `arkts_check ["entry/src/main/ets/utils/TimeUtil.ets", "entry/src/main/ets/service/ExpiryCalculator.ets", "entry/src/test/LocalUnit.test.ets"]`
Expected: 无 ERROR

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/ entry/src/main/ets/service/ExpiryCalculator.ets entry/src/test/
git commit -m "feat: 到期时间计算与剩余时长格式化(含单测)"
```

---

### Task 3: DbHelper（RelationalStore 元数据层）

**Files:**
- Create: `entry/src/main/ets/database/DbHelper.ets`

**Interfaces:**
- Consumes: `PhotoRecord`, `DurationType`
- Produces:
  - `DbHelper.init(context: common.Context): Promise<void>`（幂等单例）
  - `DbHelper.insert(r: PhotoRecord): Promise<number>`（返回 rowId，失败 -1）
  - `DbHelper.listAll(): Promise<Array<PhotoRecord>>`（created_at DESC）
  - `DbHelper.queryById(id: number): Promise<PhotoRecord | null>`
  - `DbHelper.listExpired(now: number): Promise<Array<PhotoRecord>>`
  - `DbHelper.setForever(id: number): Promise<number>`（影响行数）
  - `DbHelper.updateExpire(id: number, expireAt: number | null, type: DurationType): Promise<number>`
  - `DbHelper.updateNote(id: number, note: string): Promise<number>`
  - `DbHelper.deleteById(id: number): Promise<number>`

- [ ] **Step 1: 写 DbHelper.ets**

```typescript
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PhotoRecord } from '../model/PhotoRecord';
import { DurationType } from '../model/DurationType';

const TABLE = 'photos';

export class DbHelper {
  private static store: relationalStore.RdbStore | null = null;

  static async init(context: common.Context): Promise<void> {
    if (DbHelper.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'tempphoto.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.executeSql(`CREATE TABLE IF NOT EXISTS ${TABLE} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_path TEXT NOT NULL,
      note TEXT DEFAULT '',
      created_at INTEGER NOT NULL,
      expire_at INTEGER,
      duration_type INTEGER NOT NULL)`);
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_photos_expire ON ${TABLE}(expire_at)`);
    await store.executeSql(`CREATE INDEX IF NOT EXISTS idx_photos_created ON ${TABLE}(created_at DESC)`);
    DbHelper.store = store;
  }

  private static get(): relationalStore.RdbStore {
    if (DbHelper.store === null) {
      throw new Error('DbHelper not initialized');
    }
    return DbHelper.store;
  }

  static async insert(r: PhotoRecord): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'file_path': r.filePath,
      'note': r.note,
      'created_at': r.createdAt,
      'expire_at': r.expireAt,
      'duration_type': r.durationType
    };
    return DbHelper.get().insert(TABLE, values);
  }

  private static rowToRecord(rs: relationalStore.ResultSet): PhotoRecord {
    const r = new PhotoRecord();
    r.id = rs.getLong(rs.getColumnIndex('id'));
    r.filePath = rs.getString(rs.getColumnIndex('file_path'));
    r.note = rs.getString(rs.getColumnIndex('note'));
    r.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    const expireIdx = rs.getColumnIndex('expire_at');
    r.expireAt = rs.isColumnNull(expireIdx) ? null : rs.getLong(expireIdx);
    r.durationType = rs.getLong(rs.getColumnIndex('duration_type')) as DurationType;
    return r;
  }

  static async listAll(): Promise<Array<PhotoRecord>> {
    const predicates = new relationalStore.RdbPredicates(TABLE).orderByDesc('created_at');
    const rs = await DbHelper.get().query(predicates);
    const result: Array<PhotoRecord> = [];
    while (rs.goToNextRow()) {
      result.push(DbHelper.rowToRecord(rs));
    }
    rs.close();
    return result;
  }

  static async queryById(id: number): Promise<PhotoRecord | null> {
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    const rs = await DbHelper.get().query(predicates);
    let record: PhotoRecord | null = null;
    if (rs.goToNextRow()) {
      record = DbHelper.rowToRecord(rs);
    }
    rs.close();
    return record;
  }

  static async listExpired(now: number): Promise<Array<PhotoRecord>> {
    const predicates = new relationalStore.RdbPredicates(TABLE)
      .isNotNull('expire_at')
      .lessThanOrEqualTo('expire_at', now);
    const rs = await DbHelper.get().query(predicates);
    const result: Array<PhotoRecord> = [];
    while (rs.goToNextRow()) {
      result.push(DbHelper.rowToRecord(rs));
    }
    rs.close();
    return result;
  }

  static async setForever(id: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'expire_at': null,
      'duration_type': DurationType.FOREVER
    };
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    return DbHelper.get().update(values, predicates);
  }

  static async updateExpire(id: number, expireAt: number | null, type: DurationType): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'expire_at': expireAt,
      'duration_type': type
    };
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    return DbHelper.get().update(values, predicates);
  }

  static async updateNote(id: number, note: string): Promise<number> {
    const values: relationalStore.ValuesBucket = { 'note': note };
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    return DbHelper.get().update(values, predicates);
  }

  static async deleteById(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    return DbHelper.get().delete(predicates);
  }
}
```

注意：`rs.getLong(...) as DurationType` 为数值到枚举的必要转换；若 arkts_check 报 `arkts-no-unsafe-cast` 类问题，改为先存 `const t: number = rs.getLong(...)` 再用 `DurationType[t]` 之外的映射函数（枚举数值判断）。

- [ ] **Step 2: 校验**

Run: `arkts_check ["entry/src/main/ets/database/DbHelper.ets"]`
Expected: 无 ERROR

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/database/
git commit -m "feat: 照片元数据RDB存储层"
```

---

### Task 4: CleanupService（到期清理 + 孤儿扫描）

**Files:**
- Create: `entry/src/main/ets/service/CleanupService.ets`

**Interfaces:**
- Consumes: `DbHelper`, `PhotoRecord`
- Produces:
  - `CleanupService.sweepExpired(context: common.Context): Promise<number>`（返回删除条数；前台/后台共用入口）
  - `CleanupService.deletePhoto(context: common.Context, record: PhotoRecord): Promise<void>`（详情页手动删除）
  - 常量 `PHOTO_ROOT = 'temp_photos'`（与 PhotoRepository 共用）

- [ ] **Step 1: 写 CleanupService.ets**

```typescript
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DbHelper } from '../database/DbHelper';
import { PhotoRecord } from '../model/PhotoRecord';

const DOMAIN = 0x0011;
const TAG = 'CleanupService';

export const PHOTO_ROOT = 'temp_photos';
const ORPHAN_GRACE_MS = 86_400_000;

export class CleanupService {
  static async sweepExpired(context: common.Context): Promise<number> {
    await DbHelper.init(context);
    const expired = await DbHelper.listExpired(Date.now());
    let deleted = 0;
    for (const r of expired) {
      const rows = await DbHelper.deleteById(r.id);
      if (rows > 0) {
        CleanupService.deleteFileQuietly(context, r.filePath);
        deleted += rows;
      }
    }
    await CleanupService.sweepOrphans(context);
    if (deleted > 0) {
      hilog.info(DOMAIN, TAG, 'sweepExpired deleted %{public}d photos', deleted);
    }
    return deleted;
  }

  static async deletePhoto(context: common.Context, record: PhotoRecord): Promise<void> {
    await DbHelper.init(context);
    await DbHelper.deleteById(record.id);
    CleanupService.deleteFileQuietly(context, record.filePath);
  }

  static deleteFileQuietly(context: common.Context, relativePath: string): void {
    try {
      fs.unlinkSync(`${context.filesDir}/${relativePath}`);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'delete file failed: %{public}s', `${err}`);
    }
  }

  private static async sweepOrphans(context: common.Context): Promise<void> {
    const root = `${context.filesDir}/${PHOTO_ROOT}`;
    if (!fs.accessSync(root)) {
      return;
    }
    const known = new Set<string>();
    const all = await DbHelper.listAll();
    for (const r of all) {
      known.add(r.filePath);
    }
    const cutoff = Date.now() - ORPHAN_GRACE_MS;
    const dayDirs = fs.listFileSync(root);
    for (const day of dayDirs) {
      const dayDir = `${root}/${day}`;
      const dayStat = fs.statSync(dayDir);
      if (!dayStat.isDirectory()) {
        continue;
      }
      const files = fs.listFileSync(dayDir);
      for (const f of files) {
        const rel = `${PHOTO_ROOT}/${day}/${f}`;
        if (known.has(rel)) {
          continue;
        }
        const fStat = fs.statSync(`${dayDir}/${f}`);
        if (fStat.mtime * 1000 < cutoff) {
          try {
            fs.unlinkSync(`${dayDir}/${f}`);
          } catch (err) {
            hilog.warn(DOMAIN, TAG, 'orphan delete failed: %{public}s', `${err}`);
          }
        }
      }
    }
  }
}
```

注意：`fs.Stat.mtime` 单位为秒，与毫秒 `cutoff` 比较需乘 1000（实现时以真机验证为准，若 mtime 已是毫秒则去掉系数）。

- [ ] **Step 2: 校验**

Run: `arkts_check ["entry/src/main/ets/service/CleanupService.ets"]`
Expected: 无 ERROR

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/service/CleanupService.ets
git commit -m "feat: 到期清理服务与孤儿文件回收"
```

---

### Task 5: PhotoRepository（保存编排 + 转永久 + 列表）

**Files:**
- Create: `entry/src/main/ets/service/PhotoRepository.ets`
- Create: `entry/src/main/ets/service/WorkSchedulerGuard.ets`

**Interfaces:**
- Consumes: `DbHelper`, `ExpiryCalculator`, `TimeUtil`, `CleanupService`, `PhotoRecord`, `DurationType`
- Produces:
  - `PhotoRepository.savePhoto(context: common.UIAbilityContext, data: ArrayBuffer, type: DurationType): Promise<PhotoRecord>`（写文件→入库→注册延迟任务；入库失败回滚删文件并抛错）
  - `PhotoRepository.loadAll(context: common.Context): Promise<Array<PhotoRecord>>`（内部先 `DbHelper.init`）
  - `PhotoRepository.makeForever(id: number): Promise<number>`
  - `WorkSchedulerGuard.ensureRegistered(context: common.UIAbilityContext): void`（幂等，workId=1001）

- [ ] **Step 1: 写 WorkSchedulerGuard.ets**

```typescript
import { workScheduler } from '@kit.BackgroundTasksKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0012;
const TAG = 'WorkSchedulerGuard';

export class WorkSchedulerGuard {
  static readonly WORK_ID = 1001;
  static readonly ABILITY_NAME = 'CleanupExtension';

  static ensureRegistered(context: common.UIAbilityContext): void {
    try {
      const works: Array<workScheduler.WorkInfo> = workScheduler.obtainAllWorksSync();
      for (const w of works) {
        if (w.workId === WorkSchedulerGuard.WORK_ID) {
          return;
        }
      }
      const work: workScheduler.WorkInfo = {
        workId: WorkSchedulerGuard.WORK_ID,
        bundleName: context.abilityInfo.bundleName,
        abilityName: WorkSchedulerGuard.ABILITY_NAME,
        isRepeat: true
      };
      workScheduler.startWork(work);
      hilog.info(DOMAIN, TAG, 'cleanup work registered');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'register work failed: %{public}s', `${err}`);
    }
  }
}
```

- [ ] **Step 2: 写 PhotoRepository.ets**

```typescript
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { DbHelper } from '../database/DbHelper';
import { ExpiryCalculator } from './ExpiryCalculator';
import { CleanupService, PHOTO_ROOT } from './CleanupService';
import { WorkSchedulerGuard } from './WorkSchedulerGuard';
import { PhotoRecord } from '../model/PhotoRecord';
import { DurationType } from '../model/DurationType';
import { TimeUtil } from '../utils/TimeUtil';

export class PhotoRepository {
  static async savePhoto(context: common.UIAbilityContext, data: ArrayBuffer,
    type: DurationType): Promise<PhotoRecord> {
    await DbHelper.init(context);
    const now = Date.now();
    const day = TimeUtil.formatDay(now);
    const relativePath = `${PHOTO_ROOT}/${day}/${now}_${Math.floor(Math.random() * 100000)}.jpg`;
    const absolutePath = `${context.filesDir}/${relativePath}`;
    const dayDir = `${context.filesDir}/${PHOTO_ROOT}/${day}`;
    try {
      fs.mkdirSync(dayDir, true);
    } catch (e) {
    }
    const file = fs.openSync(absolutePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    fs.writeSync(file.fd, data);
    fs.closeSync(file);

    const record = new PhotoRecord();
    record.filePath = relativePath;
    record.note = '';
    record.createdAt = now;
    record.expireAt = ExpiryCalculator.calc(type, now);
    record.durationType = type;

    const rowId = await DbHelper.insert(record);
    if (rowId === -1) {
      CleanupService.deleteFileQuietly(context, relativePath);
      throw new Error('insert photo record failed');
    }
    record.id = rowId;
    WorkSchedulerGuard.ensureRegistered(context);
    return record;
  }

  static async loadAll(context: common.Context): Promise<Array<PhotoRecord>> {
    await DbHelper.init(context);
    return DbHelper.listAll();
  }

  static async makeForever(id: number): Promise<number> {
    return DbHelper.setForever(id);
  }
}
```

- [ ] **Step 3: 校验**

Run: `arkts_check ["entry/src/main/ets/service/PhotoRepository.ets", "entry/src/main/ets/service/WorkSchedulerGuard.ets"]`
Expected: 无 ERROR

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/service/
git commit -m "feat: 照片保存编排与延迟任务保活"
```

---

### Task 6: CleanupExtension（延迟任务回调）+ 注册

**Files:**
- Create: `entry/src/main/ets/workscheduler/CleanupExtension.ets`
- Modify: `entry/src/main/module.json5`（extensionAbilities 增加项）

**Interfaces:**
- Consumes: `CleanupService`
- Produces: module.json5 中注册的 `CleanupExtension`（type=workScheduler），与 `WorkSchedulerGuard.ABILITY_NAME` 一致

- [ ] **Step 1: 写 CleanupExtension.ets**

```typescript
import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CleanupService } from '../service/CleanupService';

const DOMAIN = 0x0013;
const TAG = 'CleanupExtension';

export default class CleanupExtension extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'onWorkStart workId=%{public}d', work.workId);
    CleanupService.sweepExpired(this.context)
      .then((n: number) => {
        hilog.info(DOMAIN, TAG, 'background sweep deleted %{public}d', n);
      })
      .catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'background sweep failed: %{public}s', `${err}`);
      });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, TAG, 'onWorkStop workId=%{public}d', work.workId);
  }
}
```

设计要点：`isRepeat: true` 的任务**不调用 stopWork**（stopWork 会取消任务，重复任务依赖系统按频率反复调度 onWorkStart）。M4 设备验证时确认重复调度行为；若系统只回调一次，则改为 onWorkStart 末尾 `workScheduler.stopWork(work)` 并在 sweep 后由 `WorkSchedulerGuard.ensureRegistered` 于下次保存/启动时重注册（见 Task 11 验证项）。

- [ ] **Step 2: module.json5 注册**

`extensionAbilities` 数组追加：

```json5
{
  "name": "CleanupExtension",
  "srcEntry": "./ets/workscheduler/CleanupExtension.ets",
  "type": "workScheduler",
  "exported": false
}
```

- [ ] **Step 3: 校验**

Run: `arkts_check ["entry/src/main/ets/workscheduler/CleanupExtension.ets"]` 然后 `build_project`
Expected: 均无 ERROR / SUCCESS

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/workscheduler/ entry/src/main/module.json5
git commit -m "feat: 后台延迟任务清理扩展"
```

---

### Task 7: EntryAbility 挂载启动/回前台补清理

**Files:**
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`

**Interfaces:**
- Consumes: `CleanupService`
- Produces: 启动兜底清理（无新接口）

- [ ] **Step 1: 修改 EntryAbility.ets**

在文件顶部追加导入：

```typescript
import { CleanupService } from '../service/CleanupService';
```

`onCreate` 末尾与 `onForeground` 中各追加（异步执行不阻塞启动）：

```typescript
CleanupService.sweepExpired(this.context)
  .then((n: number) => {
    if (n > 0) {
      hilog.info(DOMAIN, 'EntryAbility', 'startup sweep deleted %{public}d', n);
    }
  })
  .catch((err: Object) => {
    hilog.error(DOMAIN, 'EntryAbility', 'startup sweep failed: %{public}s', `${err}`);
  });
```

- [ ] **Step 2: 校验**

Run: `arkts_check ["entry/src/main/ets/entryability/EntryAbility.ets"]`
Expected: 无 ERROR

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat: 启动与回前台补清理兜底"
```

---

### Task 8: 首页（统计头 + 照片宫格 + 拍照入口）

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`（整页重写模板）
- Create: `entry/src/main/ets/components/StatsHeader.ets`
- Create: `entry/src/main/ets/components/PhotoGridItem.ets`

**Interfaces:**
- Consumes: `PhotoRepository`, `PhotoRecord`, `TimeUtil`, `DbHelper`
- Produces:
  - `StatsHeader` 组件：`todayCount: number`、`weekCount: number`、`foreverCount: number`（普通成员属性）
  - `PhotoGridItem` 组件：`record: PhotoRecord`、`onItemClick: (r: PhotoRecord) => void`
  - 首页路由跳转：`pages/CameraPage`（Task 9 实现）

- [ ] **Step 1: 写 StatsHeader.ets**

```typescript
import { DurationType } from '../model/DurationType';

@ComponentV2
export struct StatsHeader {
  todayCount: number = 0;
  weekCount: number = 0;
  foreverCount: number = 0;

  build() {
    Row({ space: 8 }) {
      this.bucket('今天', `${this.todayCount}`, '将自动清理')
      this.bucket('7天内', `${this.weekCount}`, '将清理')
      this.bucket('永久', `${this.foreverCount}`, '保留')
    }
    .width('100%')
    .padding(12)
  }

  @Builder
  bucket(title: string, count: string, suffix: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(12)
        .fontColor('#9E9E9E')
      Row({ space: 4 }) {
        Text(count)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        Text(suffix)
          .fontSize(12)
          .fontColor('#9E9E9E')
      }
    }
    .layoutWeight(1)
    .padding(12)
    .borderRadius(12)
    .backgroundColor('#F5F5F5')
    .alignItems(HorizontalAlign.Center)
  }
}
```

（删除未使用的 `DurationType` 导入若 arkts_check 报警；builder 内不依赖枚举。）

- [ ] **Step 2: 写 PhotoGridItem.ets**

```typescript
import { PhotoRecord } from '../model/PhotoRecord';
import { TimeUtil } from '../utils/TimeUtil';

@ComponentV2
export struct PhotoGridItem {
  @Param record: PhotoRecord = new PhotoRecord();
  onItemClicked: (r: PhotoRecord) => void = (r: PhotoRecord) => {
  };
  private context = this.getUIContext().getHostContext();

  build() {
    Column() {
      Image(`file://${this.context?.filesDir}/${this.record.filePath}`)
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .onClick(() => this.onItemClicked(this.record))
      Text(this.record.note === '' ? TimeUtil.formatRemaining(this.record.expireAt, Date.now())
        : this.record.note)
        .fontSize(11)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor('#666666')
        .margin({ top: 4 })
      if (this.record.expireAt !== null) {
        Text(TimeUtil.formatRemaining(this.record.expireAt, Date.now()))
          .fontSize(10)
          .fontColor('#E64A19')
      }
    }
    .margin(4)
  }
}
```

- [ ] **Step 3: 重写 Index.ets**

```typescript
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { PhotoRepository } from '../service/PhotoRepository';
import { PhotoRecord } from '../model/PhotoRecord';
import { TimeUtil } from '../utils/TimeUtil';
import { StatsHeader } from '../components/StatsHeader';
import { PhotoGridItem } from '../components/PhotoGridItem';

@Entry
@ComponentV2
struct Index {
  @Local photos: Array<PhotoRecord> = [];
  @Local todayCount: number = 0;
  @Local weekCount: number = 0;
  @Local foreverCount: number = 0;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear(): void {
    this.refresh();
  }

  onPageShow(): void {
    this.refresh();
  }

  private refresh(): void {
    PhotoRepository.loadAll(this.context)
      .then((list: Array<PhotoRecord>) => {
        this.photos = list;
        this.computeStats(list);
      })
      .catch(() => {
      });
  }

  private computeStats(list: Array<PhotoRecord>): void {
    const now = Date.now();
    const endToday = TimeUtil.endOfToday(now);
    let today = 0;
    let week = 0;
    let forever = 0;
    for (const r of list) {
      if (r.expireAt === null) {
        forever += 1;
      } else if (r.expireAt > now && r.expireAt <= endToday) {
        today += 1;
      } else if (r.expireAt > endToday) {
        week += 1;
      }
    }
    this.todayCount = today;
    this.weekCount = week;
    this.foreverCount = forever;
  }

  build() {
    Column() {
      Text('临时相机')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 8 })
      StatsHeader({
        todayCount: this.todayCount,
        weekCount: this.weekCount,
        foreverCount: this.foreverCount
      })
      if (this.photos.length === 0) {
        Column({ space: 12 }) {
          Text('📷')
            .fontSize(48)
          Text('还没有临时照片')
            .fontSize(14)
            .fontColor('#9E9E9E')
          Text('拍一张，用完自动消失')
            .fontSize(12)
            .fontColor('#BDBDBD')
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Grid() {
            ForEach(this.photos, (r: PhotoRecord) => {
              GridItem() {
                PhotoGridItem({
                  record: r,
                  onItemClicked: (clicked: PhotoRecord) => {
                    router.pushUrl({
                      url: 'pages/DetailPage',
                      params: { id: clicked.id } as Record<string, number>
                    });
                  }
                })
              }
            }, (r: PhotoRecord) => `${r.id}`)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(4)
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      Button('拍照')
        .width('80%')
        .height(52)
        .fontSize(18)
        .backgroundColor('#E64A19')
        .margin(16)
        .onClick(() => {
          router.pushUrl({ url: 'pages/CameraPage' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
```

- [ ] **Step 4: 校验**

Run: `arkts_check ["entry/src/main/ets/pages/Index.ets", "entry/src/main/ets/components/StatsHeader.ets", "entry/src/main/ets/components/PhotoGridItem.ets"]`
Expected: 无 ERROR（CameraPage/DetailPage 尚不存在不影响静态检查；build 会因路由缺失失败，本任务只跑 arkts_check）

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/pages/Index.ets entry/src/main/ets/components/
git commit -m "feat: 首页三桶统计与照片宫格"
```

---

### Task 9: 寿命选择条 + 自定义相机页

**Files:**
- Create: `entry/src/main/ets/components/DurationSelector.ets`
- Create: `entry/src/main/ets/pages/CameraPage.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`（加 `pages/CameraPage`）
- Modify: `entry/src/main/ets/pages/Index.ets` 不变（已引用）

**Interfaces:**
- Consumes: `PhotoRepository`, `DurationType`, `DurationLabel`, `camera`, `image`, `TimeUtil`
- Produces:
  - `DurationSelector` 组件：`selected: DurationType`（@Param）、`onSelected: (t: DurationType) => void`
  - CameraPage 完整拍照流程；保存成功后 `router.back()` 返回首页

- [ ] **Step 1: 写 DurationSelector.ets**

```typescript
import { DurationType, DurationLabel } from '../model/DurationType';

@ComponentV2
export struct DurationSelector {
  @Param selected: DurationType = DurationType.END_OF_TODAY;
  onSelected: (t: DurationType) => void = (t: DurationType) => {
  };

  build() {
    Row({ space: 8 }) {
      ForEach(DurationLabel.all(), (t: DurationType) => {
        Text(DurationLabel.labelOf(t))
          .fontSize(14)
          .fontColor(this.selected === t ? '#FFFFFF' : '#333333')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.selected === t ? '#E64A19' : '#F5F5F5')
          .onClick(() => this.onSelected(t))
      }, (t: DurationType) => `${t}`)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
}
```

- [ ] **Step 2: 写 CameraPage.ets**

```typescript
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, Permissions, common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { PhotoRepository } from '../service/PhotoRepository';
import { DurationType } from '../model/DurationType';
import { TimeUtil } from '../utils/TimeUtil';
import { DurationSelector } from '../components/DurationSelector';

@Entry
@ComponentV2
struct CameraPage {
  @Local surfaceId: string = '';
  @Local selected: DurationType = DurationType.END_OF_TODAY;
  @Local hasPermission: boolean = false;
  @Local flashOn: boolean = false;
  @Local isFront: boolean = false;
  @Local saving: boolean = false;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private xComponentController: XComponentController = new XComponentController();
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private receiver: image.ImageReceiver | null = null;
  private session: camera.PhotoSession | null = null;

  aboutToAppear(): void {
    const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
    abilityAccessCtrl.requestPermissionsFromUser(this.context, permissions)
      .then((result) => {
        if (result.authResults.length > 0 && result.authResults[0] === 0) {
          this.hasPermission = true;
        } else {
          this.hasPermission = false;
        }
      })
      .catch(() => {
        this.hasPermission = false;
      });
  }

  aboutToDisappear(): void {
    this.releaseCamera();
  }

  private async initCamera(): Promise<void> {
    try {
      this.cameraManager = camera.getCameraManager(this.context);
      const devices = this.cameraManager.getSupportedCameras();
      const wanted = this.isFront ? camera.CameraPosition.FRONT : camera.CameraPosition.BACK;
      let device: camera.CameraDevice | undefined = undefined;
      for (const d of devices) {
        if (d.cameraPosition === wanted) {
          device = d;
          break;
        }
      }
      if (device === undefined) {
        device = devices[0];
      }
      const capability = this.cameraManager.getCameraOutputCapability(device);
      const previewProfile = capability.previewProfiles[0];
      const photoProfile = capability.photoProfiles[0];
      this.cameraInput = this.cameraManager.createCameraInput(device);
      await this.cameraInput.open();
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, this.surfaceId);
      this.receiver = image.createImageReceiver(photoProfile.size.width, photoProfile.size.height,
        image.ImageFormat.JPEG, 8);
      const photoSurfaceId: string = await this.receiver.getReceivingSurfaceId();
      this.photoOutput = this.cameraManager.createPhotoOutput(photoProfile, photoSurfaceId);
      this.receiver.on('imageArrival', () => {
        this.onImageArrival();
      });
      this.session = this.cameraManager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      this.session.beginConfig();
      this.session.addInput(this.cameraInput);
      this.session.addOutput(this.previewOutput);
      this.session.addOutput(this.photoOutput);
      await this.session.commitConfig();
      await this.session.start();
      this.applyFlash();
    } catch (error) {
      const err = error as BusinessError;
      promptAction.showToast({ message: `相机启动失败: ${err.code}` });
    }
  }

  private applyFlash(): void {
    if (this.session === null) {
      return;
    }
    try {
      this.session.setFlashMode(this.flashOn ? camera.FlashMode.ON : camera.FlashMode.OFF);
    } catch (error) {
    }
  }

  private async onImageArrival(): Promise<void> {
    if (this.saving || this.receiver === null) {
      return;
    }
    this.saving = true;
    const receiver = this.receiver;
    receiver.readNextImage((err: BusinessError, img: image.Image) => {
      if (err.code !== 0 || img === null) {
        this.saving = false;
        return;
      }
      img.getComponent(image.ComponentType.JPEG, (errComp: BusinessError,
        component: image.ImageComponent) => {
        if (errComp.code !== 0 || component === null) {
          img.release();
          this.saving = false;
          return;
        }
        const typeAtShot = this.selected;
        PhotoRepository.savePhoto(this.context, component.byteBuffer, typeAtShot)
          .then((record: {
          }) => {
            img.release();
            this.saving = false;
            this.notifySaved(typeAtShot);
          })
          .catch(() => {
            img.release();
            this.saving = false;
            promptAction.showToast({ message: '保存失败，请重试' });
          });
      });
    });
  }

  private notifySaved(type: DurationType): void {
    let suffix = '已保存';
    if (type === DurationType.FOREVER) {
      suffix = '已保存 · 永久保留';
    } else {
      const expire = record ExpirePlaceholder;
    }
    promptAction.showToast({ message: suffix, duration: 1500 });
    router.back();
  }

  private async releaseCamera(): Promise<void> {
    try {
      if (this.session !== null) {
        await this.session.stop();
        this.session.release();
        this.session = null;
      }
      if (this.previewOutput !== null) {
        this.previewOutput.release();
        this.previewOutput = null;
      }
      if (this.photoOutput !== null) {
        this.photoOutput.release();
        this.photoOutput = null;
      }
      if (this.receiver !== null) {
        this.receiver.release();
        this.receiver = null;
      }
      if (this.cameraInput !== null) {
        await this.cameraInput.close();
        this.cameraInput = null;
      }
    } catch (error) {
    }
  }

  private async capture(): Promise<void> {
    if (this.photoOutput === null) {
      return;
    }
    try {
      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: camera.ImageRotation.ROTATION_0
      };
      this.photoOutput.capture(setting);
    } catch (error) {
      const err = error as BusinessError;
      promptAction.showToast({ message: `拍照失败: ${err.code}` });
    }
  }

  private async switchCamera(): Promise<void> {
    this.isFront = !this.isFront;
    await this.releaseCamera();
    await this.initCamera();
  }

  build() {
    Column() {
      if (this.hasPermission) {
        XComponent({
          type: XComponentType.SURFACE,
          controller: this.xComponentController
        })
          .onLoad(() => {
            this.surfaceId = this.xComponentController.getXComponentSurfaceId();
            this.initCamera();
          })
          .width('100%')
          .layoutWeight(1)

        if (this.selected === DurationType.END_OF_TODAY) {
          Text(`今晚 ${new Date(TimeUtil.endOfToday(Date.now())).getHours()}:00 自动删除`)
            .fontSize(12)
            .fontColor('#E64A19')
            .margin({ top: 8 })
        }
        DurationSelector({
          selected: this.selected,
          onSelected: (t: DurationType) => {
            this.selected = t;
          }
        })
        .margin({ top: 8 })

        Row({ space: 24 }) {
          Text(this.flashOn ? '闪光:开' : '闪光:关')
            .fontSize(14)
            .fontColor('#333333')
            .onClick(() => {
              this.flashOn = !this.flashOn;
              this.applyFlash();
            })
          Text(this.isFront ? '转后摄' : '转前摄')
            .fontSize(14)
            .fontColor('#333333')
            .onClick(() => {
              this.switchCamera();
            })
        }
        .margin({ top: 8 })
        .justifyContent(FlexAlign.Center)

        Button('拍摄')
          .width(72)
          .height(72)
          .borderRadius(36)
          .backgroundColor('#FFFFFF')
          .fontColor('#E64A19')
          .fontSize(16)
          .margin(16)
          .enabled(!this.saving)
          .onClick(() => {
            this.capture();
          })
      } else {
        Column({ space: 12 }) {
          Text('需要相机权限')
            .fontSize(16)
          Text('临时相机仅在App内保存照片，不会写入系统相册')
            .fontSize(12)
            .fontColor('#9E9E9E')
            .textAlign(TextAlign.Center)
            .padding({ left: 32, right: 32 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
```

**实现者注意（这是遗留伪代码，必须修复）：** `notifySaved` 中 `const expire = record ExpirePlaceholder;` 为占位错误，正确实现为：

```typescript
private notifySaved(type: DurationType): void {
  let message = '已保存';
  if (type === DurationType.FOREVER) {
    message = '已保存 · 永久保留';
  } else if (type === DurationType.END_OF_TODAY) {
    message = '已保存 · 今晚24:00自动删除';
  } else {
    message = `已保存 · ${DurationLabel.labelOf(type)}后自动删除`;
  }
  promptAction.showToast({ message: message, duration: 1500 });
  router.back();
}
```

同时 `onImageArrival` 的 `savePhoto` 回调参数类型应为 `(record: PhotoRecord)`，需补充 `import { PhotoRecord } from '../model/PhotoRecord';` 与 `import { DurationLabel } from '../model/DurationType';`。

- [ ] **Step 3: main_pages.json 注册**

```json5
{
  "src": [
    "pages/Index",
    "pages/CameraPage"
  ]
}
```

- [ ] **Step 4: 校验**

Run: `arkts_check ["entry/src/main/ets/components/DurationSelector.ets", "entry/src/main/ets/pages/CameraPage.ets"]`
Expected: 无 ERROR（先修复上述遗留伪代码再检查）

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/components/DurationSelector.ets entry/src/main/ets/pages/CameraPage.ets entry/src/main/resources/base/profile/main_pages.json
git commit -m "feat: 自定义相机页与寿命选择条"
```

---

### Task 10: 详情页（备注 / 转永久 / 改寿命 / 删除）

**Files:**
- Create: `entry/src/main/ets/pages/DetailPage.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`（加 `pages/DetailPage`）

**Interfaces:**
- Consumes: `DbHelper`, `CleanupService`, `PhotoRecord`, `DurationType`, `DurationLabel`, `ExpiryCalculator`, `TimeUtil`, `DurationSelector`
- Produces: DetailPage；路由参数 `{ id: number }`

- [ ] **Step 1: 写 DetailPage.ets**

```typescript
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DbHelper } from '../database/DbHelper';
import { CleanupService } from '../service/CleanupService';
import { PhotoRecord } from '../model/PhotoRecord';
import { DurationType, DurationLabel } from '../model/DurationType';
import { ExpiryCalculator } from '../service/ExpiryCalculator';
import { TimeUtil } from '../utils/TimeUtil';

@Entry
@ComponentV2
struct DetailPage {
  @Local record: PhotoRecord | null = null;
  @Local noteDraft: string = '';
  @Local remainingText: string = '';
  @Local showDurationDialog: boolean = false;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private timerId: number = -1;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, number>;
    const id = params !== undefined && params.id !== undefined ? params.id : -1;
    DbHelper.init(this.context)
      .then(() => DbHelper.queryById(id))
      .then((r: PhotoRecord | null) => {
        if (r === null) {
          promptAction.showToast({ message: '照片不存在' });
          router.back();
          return;
        }
        this.record = r;
        this.noteDraft = r.note;
        this.refreshRemaining();
        this.timerId = setInterval(() => {
          this.refreshRemaining();
        }, 60_000);
      });
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
    }
  }

  private refreshRemaining(): void {
    if (this.record === null) {
      return;
    }
    this.remainingText = this.record.expireAt === null
      ? '永久保留'
      : `剩余 ${TimeUtil.formatRemaining(this.record.expireAt, Date.now())}`;
  }

  private makeForever(): void {
    if (this.record === null) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '转为永久保留？',
      message: '这张照片将不再自动删除',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '转永久',
        fontColor: '#E64A19',
        action: () => {
          const target = this.record;
          if (target === null) {
            return;
          }
          DbHelper.setForever(target.id)
            .then(() => {
              target.expireAt = null;
              target.durationType = DurationType.FOREVER;
              this.refreshRemaining();
              promptAction.showToast({ message: '已转为永久保留' });
            });
        }
      }
    });
  }

  private deleteNow(): void {
    const target = this.record;
    if (target === null) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '立即删除？',
      message: '删除后无法恢复',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#E64A19',
        action: () => {
          CleanupService.deletePhoto(this.context, target)
            .then(() => {
              router.back();
            });
        }
      }
    });
  }

  private applyDuration(type: DurationType): void {
    const target = this.record;
    if (target === null) {
      return;
    }
    const expireAt = ExpiryCalculator.calc(type, target.createdAt);
    DbHelper.updateExpire(target.id, expireAt, type)
      .then(() => {
        target.expireAt = expireAt;
        target.durationType = type;
        this.showDurationDialog = false;
        this.refreshRemaining();
        promptAction.showToast({ message: `已改为${DurationLabel.labelOf(type)}` });
      });
  }

  build() {
    Column() {
      if (this.record !== null) {
        Image(`file://${this.context.filesDir}/${this.record.filePath}`)
          .width('100%')
          .layoutWeight(1)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#111111')

        Column({ space: 12 }) {
          Text(this.remainingText)
            .fontSize(14)
            .fontColor(this.record.expireAt === null ? '#4CAF50' : '#E64A19')
          Text(`拍摄于 ${new Date(this.record.createdAt).toLocaleString()}`)
            .fontSize(12)
            .fontColor('#9E9E9E')
          TextInput({ text: this.noteDraft, placeholder: '添加备注，如：3号储物柜' })
            .width('100%')
            .fontSize(14)
            .backgroundColor('#F5F5F5')
            .onChange((value: string) => {
              this.noteDraft = value;
            })
            .onBlur(() => {
              if (this.record !== null && this.noteDraft !== this.record.note) {
                DbHelper.updateNote(this.record.id, this.noteDraft)
                  .then(() => {
                    this.record.note = this.noteDraft;
                  });
              }
            })

          Row({ space: 8 }) {
            Button('转永久')
              .layoutWeight(1)
              .backgroundColor('#4CAF50')
              .enabled(this.record.expireAt !== null)
              .onClick(() => this.makeForever())
            Button('改寿命')
              .layoutWeight(1)
              .backgroundColor('#2196F3')
              .enabled(this.record.expireAt !== null)
              .onClick(() => {
                this.showDurationDialog = true;
              })
            Button('删除')
              .layoutWeight(1)
              .backgroundColor('#E64A19')
              .onClick(() => this.deleteNow())
          }
          .width('100%')
        }
        .padding(16)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')

    if (this.showDurationDialog) {
      Column() {
        Text('修改保存期限')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 16 })
        DurationSelector({
          selected: this.record === null ? DurationType.ONE_HOUR : this.record.durationType,
          onSelected: (t: DurationType) => {
            this.applyDuration(t);
          }
        })
          .margin({ top: 16, bottom: 24 })
      }
      .width('86%')
      .borderRadius(16)
      .backgroundColor('#FFFFFF')
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.showDurationDialog = false;
      })
    }
  }
}
```

实现者注意：改寿命弹窗中 `DurationSelector` 不支持横向滚动，5 档在窄弹窗内可能拥挤——若真机显示拥挤，将弹窗内选择条外层套 `Scroll()` 并设 `.scrollable(ScrollDirection.Horizontal)`，其余逻辑不变。"改寿命"选择"永久"档位即等价转永久（`applyDuration(FOREVER)` 的 `updateExpire` 会写入 expire_at=NULL）。

- [ ] **Step 2: main_pages.json 注册 DetailPage**

```json5
{
  "src": [
    "pages/Index",
    "pages/CameraPage",
    "pages/DetailPage"
  ]
}
```

- [ ] **Step 3: 校验**

Run: `arkts_check ["entry/src/main/ets/pages/DetailPage.ets"]`，然后 `build_project`
Expected: 无 ERROR / SUCCESS（全页面齐备，首次全量构建）

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/pages/DetailPage.ets entry/src/main/resources/base/profile/main_pages.json
git commit -m "feat: 详情页备注/转永久/改寿命/删除"
```

---

### Task 11: 集成验证（ohosTest + 设备全链路）

**Files:**
- Create: `entry/src/ohosTest/ets/test/SweepTest.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册 SweepTest）

**Interfaces:**
- Consumes: 全部已交付模块

- [ ] **Step 1: 写设备端清理测试**

`entry/src/ohosTest/ets/test/SweepTest.ets`：

```typescript
import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { AbilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DbHelper } from '../../../../main/ets/database/DbHelper';
import { CleanupService } from '../../../../main/ets/service/CleanupService';
import { PhotoRecord } from '../../../../main/ets/model/PhotoRecord';
import { DurationType } from '../../../../main/ets/model/DurationType';

export default function sweepTest() {
  describe('SweepTest', () => {
    let filesDir = '';

    beforeAll(async () => {
      const appContext = AbilityDelegatorRegistry.getAbilityDelegator().appContext;
      filesDir = appContext.filesDir;
      await DbHelper.init(appContext);
    });

    it('sweepDeletesExpiredKeepsForeverAndFuture', 0, async () => {
      const now = Date.now();
      const expired = makeRecord(now - 10_000);
      const forever = makeRecord(null);
      const future = makeRecord(now + 86_400_000);
      const expiredId = await DbHelper.insert(expired);
      const foreverId = await DbHelper.insert(forever);
      const futureId = await DbHelper.insert(future);
      expect(expiredId > 0).assertTrue();

      const appContext = AbilityDelegatorRegistry.getAbilityDelegator().appContext;
      const deleted = await CleanupService.sweepExpired(appContext);
      expect(deleted >= 1).assertTrue();

      expect(await DbHelper.queryById(expiredId)).assertNull();
      expect((await DbHelper.queryById(foreverId)) !== null).assertTrue();
      expect((await DbHelper.queryById(futureId)) !== null).assertTrue();
    });

    function makeRecord(expireAt: number | null): PhotoRecord {
      const r = new PhotoRecord();
      r.filePath = `temp_photos/test/${Date.now()}_${Math.floor(Math.random() * 1000)}.jpg`;
      r.note = 'test';
      r.createdAt = Date.now();
      r.expireAt = expireAt;
      r.durationType = DurationType.ONE_HOUR;
      return r;
    }
  });
}
```

在 `List.test.ets` 中 `export default function testsuite()` 内追加 `sweepTest();` 并导入。（测试记录不含真实文件，`deleteFileQuietly` 对不存在路径静默失败，不影响断言。）

- [ ] **Step 2: 全量构建并上设备**

Run: `build_project`，成功后 `start_app` 安装到真机/模拟器。

- [ ] **Step 3: 手动功能回归（真机）**

按清单逐项验证：
1. 首次进拍照页弹权限，允许后预览正常；拒绝后出现引导文案
2. 选"今天"档拍照 → Toast"今晚24:00自动删除" → 返回首页宫格立即出现，统计"今天将自动清理 1 张"
3. 详情页加备注"测试" → 返回首页备注显示
4. 详情页"转永久" → 剩余变"永久保留"，统计永久桶 +1
5. 详情页"删除" → 首页消失
6. 拍一张设"1小时" → 用 `hidumper -s 1904 -a '-t com.huawei.tempphoto CleanupExtension'` 手动触发延迟任务 → hilog 出现 `background sweep deleted`（需构造已过期记录，可用"改寿命"无法改到过去时，改用步骤7验证）
7. 退出App杀进程 → 修改系统时间跨过到期点 → 重新打开App → 首页该照片已被补清理
8. 系统相册全程无新增照片

- [ ] **Step 4: 修复回归问题并复测**

任何失败项回到对应任务修复后重跑本清单。

- [ ] **Step 5: Commit**

```bash
git add entry/src/ohosTest/
git commit -m "test: 到期清理设备端用例"
```

---

## Self-Review 记录

- **Spec 覆盖**：MVP五项（拍照§Task9/寿命§Task2·9/清理§Task4·6·7/转永久§Task10/本地存储§Task3·5）+ 备注（Task10）+ 首页三桶（Task8）+ 改寿命P1（Task10）均有对应任务；P2 导出分享按设计文档不做。
- **类型一致性**：`PhotoRecord` 字段、`DurationType` 枚举值、`DbHelper` 方法签名、`CleanupService.sweepExpired`、`WorkSchedulerGuard.WORK_ID=1001/ABILITY_NAME='CleanupExtension'` 与 module.json5 注册名一致。
- **已知风险点**（实现时验证）：① `fs.Stat.mtime` 单位（Task4）；② workScheduler 重复任务的持续调度行为（Task6 注记 + Task11 验证7）；③ `readNextImage` 回调签名在 API 21 的精确形式以 SDK d.ets 声明为准。
