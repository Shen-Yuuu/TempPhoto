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
