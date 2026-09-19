import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DbHelper } from '../database/DbHelper';
import { PhotoRecord } from '../model/PhotoRecord';

const DOMAIN = 0x0011;
const TAG = 'CleanupService';
const ORPHAN_GRACE_MS = 86_400_000;

export const PHOTO_ROOT = 'temp_photos';

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
    await CleanupService.reconcile(context);
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

  // 双向对账：删除"有记录无文件"且超过宽限期的残留记录；回收"有文件无记录"的孤儿文件
  private static async reconcile(context: common.Context): Promise<void> {
    try {
      const root = `${context.filesDir}/${PHOTO_ROOT}`;
      const cutoff = Date.now() - ORPHAN_GRACE_MS;
      const known = new Set<string>();
      const all = await DbHelper.listAll();
      for (const r of all) {
        let exists = true;
        try {
          exists = fs.accessSync(`${context.filesDir}/${r.filePath}`);
        } catch (err) {
          exists = false;
        }
        if (!exists && r.createdAt < cutoff) {
          const rows = await DbHelper.deleteById(r.id);
          if (rows > 0) {
            hilog.info(DOMAIN, TAG, 'missing-file record removed: %{public}s', r.filePath);
            continue;
          }
        }
        known.add(r.filePath);
      }
      if (!fs.accessSync(root)) {
        return;
      }
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
              hilog.info(DOMAIN, TAG, 'orphan deleted: %{public}s', rel);
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'orphan delete failed: %{public}s', `${err}`);
            }
          }
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'reconcile failed: %{public}s', `${err}`);
    }
  }
}
