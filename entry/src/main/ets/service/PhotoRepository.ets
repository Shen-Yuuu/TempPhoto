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
    } catch (err) {
    }
    try {
      const file = fs.openSync(absolutePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.writeSync(file.fd, data);
      fs.closeSync(file);
    } catch (err) {
      throw new Error(`write photo file failed: ${err}`);
    }

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
