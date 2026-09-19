import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, Permissions, common, Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { display, window } from '@kit.ArkUI';
import { PhotoRepository } from '../service/PhotoRepository';
import { PhotoRecord } from '../model/PhotoRecord';
import { DurationType, DurationLabel } from '../model/DurationType';
import { DurationSelector } from '../components/DurationSelector';
import { Theme } from '../utils/Theme';
import { PressScaleModifier } from '../utils/PressScaleModifier';

const PREF_NAME = 'camera_settings';
const KEY_LAST_DURATION = 'last_duration';

// 预览分辨率取与屏幕长宽比最接近的档位，避免取景画面拉伸；比例相同选分辨率更高的一档
function pickPreviewProfile(profiles: Array<camera.Profile>): camera.Profile {
  if (profiles.length === 0) {
    throw new Error('no preview profile supported');
  }
  let targetRatio = 0.46;
  try {
    const dsp = display.getDefaultDisplaySync();
    targetRatio = normalizedRatio(dsp.width, dsp.height);
  } catch (error) {
  }
  let best = profiles[0];
  let bestScore = Number.MAX_VALUE;
  for (const p of profiles) {
    const ratio = normalizedRatio(p.size.width, p.size.height);
    const diff = Math.abs(ratio - targetRatio);
    const pixels = p.size.width * p.size.height;
    const score = diff - pixels / 1e10;
    if (score < bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best;
}

function normalizedRatio(w: number, h: number): number {
  if (w <= 0 || h <= 0) {
    return 1;
  }
  return w > h ? w / h : h / w;
}

@Entry
@ComponentV2
struct CameraPage {
  @Local surfaceId: string = '';
  @Local selected: DurationType = DurationType.END_OF_TODAY;
  @Local hasPermission: boolean = false;
  @Local flashOn: boolean = false;
  @Local isFront: boolean = false;
  @Local saving: boolean = false;
  @Local focusVisible: boolean = false;
  @Local focusX: number = 0;
  @Local focusY: number = 0;
  @Local exposureScanning: boolean = false;
  @Env(ReadonlyEnvKey.WINDOW_AVOID_AREA) avoidArea: window.UIEnvWindowAvoidAreaInfoVP;
  private context: common.UIAbilityContext | undefined = undefined;
  private xComponentController: XComponentController = new XComponentController();
  private cameraManager: camera.CameraManager | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private session: camera.PhotoSession | undefined = undefined;
  private focusTimerId: number = -1;
  private pressModifier: PressScaleModifier = new PressScaleModifier();

  @Computed
  get topInset(): number {
    const status = this.avoidArea.statusBar.topRect.height;
    const cut = this.avoidArea.cutout.visible ? this.avoidArea.cutout.topRect.height : 0;
    return Math.max(status, cut);
  }

  @Computed
  get bottomInset(): number {
    return this.avoidArea.navigationIndicator.bottomRect.height;
  }

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadLastDuration();
    const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, permissions)
      .then((result) => {
        this.hasPermission = result.authResults.length > 0 && result.authResults[0] === 0;
      })
      .catch(() => {
        this.hasPermission = false;
      });
  }

  onPageShow(): void {
    this.recheckPermission();
  }

  private loadLastDuration(): void {
    const ctx = this.context;
    if (ctx === undefined) {
      return;
    }
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(ctx, { name: PREF_NAME });
      const saved = store.getSync(KEY_LAST_DURATION, DurationType.END_OF_TODAY) as number;
      if (saved >= DurationType.ONE_HOUR && saved <= DurationType.FOREVER) {
        this.selected = saved as DurationType;
      }
    } catch (error) {
    }
  }

  private persistLastDuration(t: DurationType): void {
    const ctx = this.context;
    if (ctx === undefined) {
      return;
    }
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(ctx, { name: PREF_NAME });
      store.putSync(KEY_LAST_DURATION, t);
      store.flush().catch(() => {
      });
    } catch (error) {
    }
  }

  private recheckPermission(): void {
    const ctx = this.context;
    if (ctx === undefined || this.hasPermission) {
      return;
    }
    const atManager = abilityAccessCtrl.createAtManager();
    atManager.checkAccessToken(ctx.applicationInfo.accessTokenId, 'ohos.permission.CAMERA')
      .then((state: abilityAccessCtrl.GrantStatus) => {
        if (state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          this.hasPermission = true;
        }
      })
      .catch(() => {
      });
  }

  private openPermissionSettings(): void {
    const ctx = this.context;
    if (ctx === undefined) {
      return;
    }
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: { 'pushParams': ctx.abilityInfo.bundleName }
    };
    ctx.startAbility(want).catch(() => {
      this.toast('无法打开系统设置');
    });
  }

  private scheduleHideFocus(delayMs: number): void {
    if (this.focusTimerId !== -1) {
      clearTimeout(this.focusTimerId);
    }
    this.focusTimerId = setTimeout(() => {
      this.focusTimerId = -1;
      this.focusVisible = false;
    }, delayMs);
  }

  private focusAtTouch(event: TouchEvent): void {
    const session = this.session;
    if (session === undefined || event.type !== TouchType.Down) {
      return;
    }
    const touchVpX = event.touches[0].x;
    const touchVpY = event.touches[0].y;
    this.focusX = touchVpX;
    this.focusY = touchVpY;
    this.focusVisible = true;
    this.exposureScanning = true;
    this.scheduleHideFocus(1200);
    try {
      const density = display.getDefaultDisplaySync().densityPixels;
      const point: camera.Point = {
        x: touchVpX * density,
        y: touchVpY * density
      };
      if (session.isLockFocusTrackingSupported()) {
        try {
          session.unlockFocusTracking();
        } catch (ignored) {
        }
        session.lockFocusTracking(point);
      } else if (session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_AUTO)) {
        session.setFocusMode(camera.FocusMode.FOCUS_MODE_AUTO);
        session.setFocusPoint(point);
      }
    } catch (error) {
    }
  }

  aboutToDisappear(): void {
    if (this.focusTimerId !== -1) {
      clearTimeout(this.focusTimerId);
      this.focusTimerId = -1;
    }
    this.releaseCamera();
  }

  private async initCamera(): Promise<void> {
    if (this.context === undefined || this.surfaceId === '') {
      return;
    }
    try {
      this.cameraManager = camera.getCameraManager(this.context);
      const devices = this.cameraManager.getSupportedCameras();
      const wanted = this.isFront ? camera.CameraPosition.CAMERA_POSITION_FRONT :
        camera.CameraPosition.CAMERA_POSITION_BACK;
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
      const capability = this.cameraManager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const previewProfile = pickPreviewProfile(capability.previewProfiles);
      const photoProfile = capability.photoProfiles[0];
      this.cameraInput = this.cameraManager.createCameraInput(device);
      await this.cameraInput.open();
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, this.surfaceId);
      this.photoOutput = this.cameraManager.createPhotoOutput(photoProfile);
      this.photoOutput.on('photoAvailable', (err: BusinessError, photo: camera.Photo) => {
        this.onPhotoAvailable(err, photo);
      });
      const session: camera.PhotoSession = this.cameraManager.createSession(camera.SceneMode.NORMAL_PHOTO);
      this.session = session;
      session.beginConfig();
      session.addInput(this.cameraInput);
      session.addOutput(this.previewOutput);
      session.addOutput(this.photoOutput);
      await session.commitConfig();
      await session.start();
      session.onExposureStateChange((state: camera.ExposureState) => {
        if (state === camera.ExposureState.EXPOSURE_STATE_SCAN) {
          this.exposureScanning = true;
        } else if (state === camera.ExposureState.EXPOSURE_STATE_CONVERGED) {
          this.exposureScanning = false;
          if (this.focusVisible) {
            this.scheduleHideFocus(600);
          }
        }
      });
      this.applyFlash();
    } catch (error) {
      const err = error as BusinessError;
      this.toast(`相机启动失败: ${err.code}`);
    }
  }

  private applyFlash(): void {
    if (this.session === undefined) {
      return;
    }
    try {
      this.session.setFlashMode(this.flashOn ? camera.FlashMode.FLASH_MODE_OPEN :
        camera.FlashMode.FLASH_MODE_CLOSE);
    } catch (error) {
    }
  }

  private onPhotoAvailable(err: BusinessError, photo: camera.Photo): void {
    if (this.context === undefined) {
      photo.release().catch(() => {
      });
      return;
    }
    if (this.saving) {
      photo.release().catch(() => {
      });
      return;
    }
    if (err.code !== 0) {
      photo.release().catch(() => {
      });
      return;
    }
    this.saving = true;
    const typeAtShot = this.selected;
    const img = photo.main;
    img.getComponent(image.ComponentType.JPEG, (errComp: BusinessError,
      component: image.Component) => {
      if (errComp.code !== 0 || component === undefined) {
        photo.release().catch(() => {
        });
        this.saving = false;
        return;
      }
      const ctx = this.context as common.UIAbilityContext;
      PhotoRepository.savePhoto(ctx, component.byteBuffer, typeAtShot)
        .then((record: PhotoRecord) => {
          photo.release().catch(() => {
          });
          this.saving = false;
          this.notifySaved(record);
        })
        .catch(() => {
          photo.release().catch(() => {
          });
          this.saving = false;
          this.toast('保存失败，请重试');
        });
    });
  }

  private notifySaved(record: PhotoRecord): void {
    let message = '已保存';
    if (record.durationType === DurationType.FOREVER) {
      message = '已保存 · 永久保留';
    } else if (record.durationType === DurationType.END_OF_TODAY) {
      message = '已保存 · 今晚24:00自动删除';
    } else {
      message = `已保存 · ${DurationLabel.labelOf(record.durationType)}后自动删除`;
    }
    this.toast(message);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
    }
  }

  private async releaseCamera(): Promise<void> {
    try {
      if (this.session !== undefined) {
        await this.session.stop();
        await this.session.release();
        this.session = undefined;
      }
      if (this.previewOutput !== undefined) {
        await this.previewOutput.release();
        this.previewOutput = undefined;
      }
      if (this.photoOutput !== undefined) {
        await this.photoOutput.release();
        this.photoOutput = undefined;
      }
      if (this.cameraInput !== undefined) {
        await this.cameraInput.close();
        this.cameraInput = undefined;
      }
    } catch (error) {
    }
  }

  private capture(): void {
    if (this.photoOutput === undefined || this.saving) {
      return;
    }
    try {
      const setting: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: this.detectRotation()
      };
      this.photoOutput.capture(setting);
    } catch (error) {
      const err = error as BusinessError;
      this.toast(`拍照失败: ${err.code}`);
    }
  }

  // 由系统按当前设备方向计算照片旋转角（API 23+ 可无参调用），避免竖拍照片横倒
  private detectRotation(): camera.ImageRotation {
    try {
      const detected = this.photoOutput?.getPhotoRotation();
      if (detected !== undefined) {
        return detected;
      }
    } catch (error) {
    }
    return camera.ImageRotation.ROTATION_0;
  }

  private async switchCamera(): Promise<void> {
    this.isFront = !this.isFront;
    await this.releaseCamera();
    await this.initCamera();
  }

  private expireHint(): string {
    switch (this.selected) {
      case DurationType.ONE_HOUR:
        return '1小时后自动删除';
      case DurationType.END_OF_TODAY:
        return '今晚 24:00 自动删除';
      case DurationType.THREE_DAYS:
        return '3天后自动删除';
      case DurationType.SEVEN_DAYS:
        return '7天后自动删除';
      default:
        return '不会自动删除';
    }
  }

  build() {
    Column() {
      if (this.hasPermission) {
        Stack({ alignContent: Alignment.TopStart }) {
          XComponent({
            type: XComponentType.SURFACE,
            controller: this.xComponentController
          })
            .onLoad(() => {
              this.surfaceId = this.xComponentController.getXComponentSurfaceId();
              this.initCamera();
            })
            .onTouch((event: TouchEvent) => {
              this.focusAtTouch(event);
            })
            .width('100%')
            .height('100%')
            .borderRadius(18)

          if (this.focusVisible) {
            Column()
              .width(66)
              .height(66)
              .borderRadius(33)
              .border({ width: 2, color: this.exposureScanning ? '#FFFFFF' : Theme.FOREVER })
              .position({ x: this.focusX - 33, y: this.focusY - 33 })
              .opacity(0.9)
          }

          Column({ space: 10 }) {
            Stack({ alignContent: Alignment.Center }) {
              Image(this.flashOn ? $r('app.media.ic_flash_on') : $r('app.media.ic_flash_off'))
                .width(20)
                .height(20)
                .draggable(false)
                .fillColor(this.flashOn ? '#FFFFFF' : '#55504A')
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.flashOn ? Theme.ACCENT : 'rgba(255,255,255,0.92)')
            .shadow(Theme.shadowSm())
            .attributeModifier(this.pressModifier)
            .onClick(() => {
              this.flashOn = !this.flashOn;
              this.applyFlash();
            })

            Stack({ alignContent: Alignment.Center }) {
              Image($r('app.media.ic_flip'))
                .width(20)
                .height(20)
                .draggable(false)
                .fillColor('#55504A')
            }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor('rgba(255,255,255,0.92)')
            .shadow(Theme.shadowSm())
            .attributeModifier(this.pressModifier)
            .onClick(() => {
              this.switchCamera();
            })
          }
          .position({ x: '100%', y: 0 })
          .translate({ x: -52, y: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ left: 14, right: 14, top: 10 + this.topInset })
        .borderRadius(20)
        .clip(true)
        .backgroundColor('#1C1A17')

        Text(`已选「${DurationLabel.labelOf(this.selected)}」· ${this.expireHint()}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.selected === DurationType.FOREVER ? Theme.FOREVER : Theme.TODAY)
          .margin({ top: 14 })

        DurationSelector({
          selected: this.selected,
          onSelected: (t: DurationType) => {
            this.selected = t;
            this.persistLastDuration(t);
          }
        })
        .margin({ top: 10 })

        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width(74)
            .height(74)
            .borderRadius(37)
            .backgroundColor('#FFFFFF')
            .border({ width: 3, color: Theme.ACCENT })
            .shadow(Theme.shadowMd())
          Row()
            .width(58)
            .height(58)
            .borderRadius(29)
            .linearGradient({ angle: 135, colors: [[Theme.ACCENT_LIGHT, 0.0], [Theme.ACCENT, 1.0]] })
            .opacity(this.saving ? 0.35 : 1)
        }
        .margin({ top: 12, bottom: 16 + this.bottomInset })
        .attributeModifier(this.pressModifier)
        .onClick(() => {
          this.capture();
        })
      } else {
        Column({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            Row()
              .width(88)
              .height(88)
              .borderRadius(44)
              .backgroundColor('#EDEAE3')
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(44)
                .height(30)
                .borderRadius(6)
                .backgroundColor('#C9C4BA')
              Row()
                .width(14)
                .height(14)
                .borderRadius(7)
                .backgroundColor('#FFFFFF')
              Row()
                .width(14)
                .height(14)
                .borderRadius(7)
                .border({ width: 2, color: '#8A857C' })
            }
          }
          .width(88)
          .height(88)

          Text('需要相机权限')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.INK)
            .margin({ top: 4 })
          Text('临时相机仅在应用内保存照片，不会写入系统相册。请前往设置授予相机权限。')
            .fontSize(12)
            .fontColor(Theme.INK2)
            .textAlign(TextAlign.Center)
            .lineHeight(19)
            .padding({ left: 40, right: 40 })
            .orphanCharOptimization(true)
            .punctuationOverflow(true)

          Row({ space: 8 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(Theme.ACCENT)
            Text('前往设置授权')
              .fontSize(15)
              .fontColor('#FFFFFF')
          }
          .padding({ left: 28, right: 28, top: 13, bottom: 13 })
          .borderRadius(24)
          .backgroundColor(Theme.INK)
          .shadow({ radius: 10, color: 'rgba(28,26,23,0.18)', offsetY: 4 })
          .margin({ top: 8 })
          .onClick(() => {
            this.openPermissionSettings();
          })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
