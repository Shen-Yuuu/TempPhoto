import { workScheduler } from '@kit.BackgroundTasksKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0012;
const TAG = 'WorkSchedulerGuard';

export class WorkSchedulerGuard {
  static readonly WORK_ID = 1001;
  static readonly ABILITY_NAME = 'CleanupExtension';

  static ensureRegistered(context: common.UIAbilityContext): void {
    workScheduler.obtainAllWorks()
      .then((works: Array<workScheduler.WorkInfo>) => {
        for (const w of works) {
          if (w.workId === WorkSchedulerGuard.WORK_ID) {
            return;
          }
        }
        WorkSchedulerGuard.startWork(context);
      })
      .catch(() => {
        WorkSchedulerGuard.startWork(context);
      });
  }

  private static startWork(context: common.UIAbilityContext): void {
    try {
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
