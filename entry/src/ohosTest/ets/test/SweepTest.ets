import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { DbHelper } from '../../../main/ets/database/DbHelper';
import { CleanupService } from '../../../main/ets/service/CleanupService';
import { PhotoRecord } from '../../../main/ets/model/PhotoRecord';
import { DurationType } from '../../../main/ets/model/DurationType';

function makeRecord(expireAt: number | undefined): PhotoRecord {
  const r = new PhotoRecord();
  r.filePath = `temp_photos/test/${Date.now()}_${Math.floor(Math.random() * 1000)}.jpg`;
  r.note = 'test';
  r.createdAt = Date.now();
  r.expireAt = expireAt;
  r.durationType = DurationType.ONE_HOUR;
  return r;
}

export default function sweepTest() {
  describe('SweepTest', () => {
    let appContext: common.Context | undefined = undefined;

    beforeAll(async () => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      await DbHelper.init(appContext);
    });

    it('sweepDeletesExpiredKeepsForeverAndFuture', 0, async () => {
      const now = Date.now();
      const expired = makeRecord(now - 10_000);
      const forever = makeRecord(undefined);
      const future = makeRecord(now + 86_400_000);
      const expiredId = await DbHelper.insert(expired);
      const foreverId = await DbHelper.insert(forever);
      const futureId = await DbHelper.insert(future);
      expect(expiredId > 0).assertTrue();

      const deleted = await CleanupService.sweepExpired(appContext as common.Context);
      expect(deleted >= 1).assertTrue();

      expect(await DbHelper.queryById(expiredId)).assertUndefined();
      expect((await DbHelper.queryById(foreverId)) !== undefined).assertTrue();
      expect((await DbHelper.queryById(futureId)) !== undefined).assertTrue();
    });

    it('setForeverExcludesFromSweep', 0, async () => {
      const soonExpired = makeRecord(Date.now() + 60_000);
      const id = await DbHelper.insert(soonExpired);
      await DbHelper.setForever(id);
      const deleted = await CleanupService.sweepExpired(appContext as common.Context);
      expect(deleted === 0).assertTrue();
      expect((await DbHelper.queryById(id)) !== undefined).assertTrue();
    });
  });
}
