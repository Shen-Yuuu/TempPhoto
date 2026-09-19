import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { CleanupService } from '../service/CleanupService';
import { WorkSchedulerGuard } from '../service/WorkSchedulerGuard';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    // 延迟任务不随设备重启保留，冷启动时补注册，避免重启后后台静默清理失效
    WorkSchedulerGuard.ensureRegistered(this.context);
    this.runStartupSweep();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowSystemBarProperties({
        statusBarContentColor: '#1C1A17',
        navigationBarContentColor: '#1C1A17'
      });
      mainWindow.setWindowLayoutFullScreen(true).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'layoutFullScreen failed: %{public}d', err.code);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'immersive setup failed. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
    this.runStartupSweep();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }

  private runStartupSweep(): void {
    CleanupService.sweepExpired(this.context)
      .then((n: number) => {
        if (n > 0) {
          hilog.info(DOMAIN, TAG, 'startup sweep deleted %{public}d photos', n);
        }
      })
      .catch((err: Object) => {
        hilog.error(DOMAIN, TAG, 'startup sweep failed. Cause: %{public}s', `${err}`);
      });
  }
}
