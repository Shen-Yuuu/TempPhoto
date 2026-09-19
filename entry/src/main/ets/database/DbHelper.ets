import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PhotoRecord } from '../model/PhotoRecord';
import { DurationType } from '../model/DurationType';

const TABLE = 'photos';

export class DbHelper {
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static initPromise: Promise<void> | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (DbHelper.store !== undefined) {
      return;
    }
    if (DbHelper.initPromise === undefined) {
      DbHelper.initPromise = DbHelper.doInit(context);
    }
    await DbHelper.initPromise;
  }

  private static async doInit(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: 'tempphoto.db',
      securityLevel: relationalStore.SecurityLevel.S2
    };
    try {
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
    } catch (error) {
      // 初始化失败后清除缓存 Promise，允许下次调用重试
      DbHelper.initPromise = undefined;
      throw error as Error;
    }
  }

  private static get(): relationalStore.RdbStore {
    if (DbHelper.store === undefined) {
      throw new Error('DbHelper not initialized');
    }
    return DbHelper.store;
  }

  static async insert(r: PhotoRecord): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'file_path': r.filePath,
      'note': r.note,
      'created_at': r.createdAt,
      'expire_at': r.expireAt === undefined ? null : r.expireAt,
      'duration_type': r.durationType
    };
    try {
      return await DbHelper.get().insert(TABLE, values);
    } catch (error) {
      throw error as Error;
    }
  }

  private static rowToRecord(rs: relationalStore.ResultSet): PhotoRecord {
    const r = new PhotoRecord();
    try {
      r.id = rs.getLong(rs.getColumnIndex('id'));
      r.filePath = rs.getString(rs.getColumnIndex('file_path'));
      r.note = rs.getString(rs.getColumnIndex('note'));
      r.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
      const expireIdx = rs.getColumnIndex('expire_at');
      r.expireAt = rs.isColumnNull(expireIdx) ? undefined : rs.getLong(expireIdx);
      r.durationType = rs.getLong(rs.getColumnIndex('duration_type')) as DurationType;
    } catch (error) {
      throw error as Error;
    }
    return r;
  }

  static async listAll(): Promise<Array<PhotoRecord>> {
    const predicates = new relationalStore.RdbPredicates(TABLE).orderByDesc('created_at');
    try {
      const rs = await DbHelper.get().query(predicates);
      const result: Array<PhotoRecord> = [];
      while (rs.goToNextRow()) {
        result.push(DbHelper.rowToRecord(rs));
      }
      rs.close();
      return result;
    } catch (error) {
      throw error as Error;
    }
  }

  static async queryById(id: number): Promise<PhotoRecord | undefined> {
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    try {
      const rs = await DbHelper.get().query(predicates);
      let record: PhotoRecord | undefined = undefined;
      if (rs.goToNextRow()) {
        record = DbHelper.rowToRecord(rs);
      }
      rs.close();
      return record;
    } catch (error) {
      throw error as Error;
    }
  }

  static async listExpired(now: number): Promise<Array<PhotoRecord>> {
    const predicates = new relationalStore.RdbPredicates(TABLE)
      .isNotNull('expire_at')
      .lessThanOrEqualTo('expire_at', now);
    try {
      const rs = await DbHelper.get().query(predicates);
      const result: Array<PhotoRecord> = [];
      while (rs.goToNextRow()) {
        result.push(DbHelper.rowToRecord(rs));
      }
      rs.close();
      return result;
    } catch (error) {
      throw error as Error;
    }
  }

  static async setForever(id: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'expire_at': null,
      'duration_type': DurationType.FOREVER
    };
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    try {
      return await DbHelper.get().update(values, predicates);
    } catch (error) {
      throw error as Error;
    }
  }

  static async updateExpire(id: number, expireAt: number | undefined, type: DurationType): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'expire_at': expireAt === undefined ? null : expireAt,
      'duration_type': type
    };
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    try {
      return await DbHelper.get().update(values, predicates);
    } catch (error) {
      throw error as Error;
    }
  }

  static async updateNote(id: number, note: string): Promise<number> {
    const values: relationalStore.ValuesBucket = { 'note': note };
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    try {
      return await DbHelper.get().update(values, predicates);
    } catch (error) {
      throw error as Error;
    }
  }

  static async deleteById(id: number): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(TABLE).equalTo('id', id);
    try {
      return await DbHelper.get().delete(predicates);
    } catch (error) {
      throw error as Error;
    }
  }
}
