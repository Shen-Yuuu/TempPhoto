import { common } from '@kit.AbilityKit';
import { window, uiMaterial } from '@kit.ArkUI';
import { DbHelper } from '../database/DbHelper';
import { CleanupService } from '../service/CleanupService';
import { PhotoRecord } from '../model/PhotoRecord';
import { DurationType, DurationLabel } from '../model/DurationType';
import { ExpiryCalculator } from '../service/ExpiryCalculator';
import { TimeUtil } from '../utils/TimeUtil';
import { Theme } from '../utils/Theme';
import { DetailParams } from '../model/RouteParams';
import { DurationSelector } from '../components/DurationSelector';
import { ShareService } from '../service/ShareService';

@Entry
@ComponentV2
struct DetailPage {
  @Local record: PhotoRecord | undefined = undefined;
  @Local noteDraft: string = '';
  @Local remainingText: string = '';
  @Local lifePercent: number = 100;
  @Local showDurationDialog: boolean = false;
  @Local imgScale: number = 1;
  @Local imgOffsetX: number = 0;
  @Local imgOffsetY: number = 0;
  @Env(ReadonlyEnvKey.WINDOW_AVOID_AREA) avoidArea: window.UIEnvWindowAvoidAreaInfoVP;
  @Env(ReadonlyEnvKey.WINDOW_SIZE) windowSize: window.SizeInVP;
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private context: common.UIAbilityContext | undefined = undefined;
  private timerId: number = -1;
  private barMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THICK,
    materialColor: 'rgba(247,246,243,0.72)'
  });
  private dialogMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: 'rgba(255,255,255,0.66)'
  });

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
    const params = this.getUIContext().getRouter().getParams() as DetailParams;
    const id = params !== undefined && params.id !== undefined ? params.id : -1;
    DbHelper.init(this.context)
      .then(() => {
        return DbHelper.queryById(id);
      })
      .then((r: PhotoRecord | undefined) => {
        if (r === undefined) {
          this.getUIContext().getPromptAction().showToast({ message: '照片不存在' });
          this.getUIContext().getRouter().back();
          return;
        }
        this.record = r;
        this.noteDraft = r.note;
        this.refreshRemaining();
        this.timerId = setInterval(() => {
          this.refreshRemaining();
        }, 60_000);
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '加载失败' });
      });
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refreshRemaining(): void {
    const r = this.record;
    if (r === undefined) {
      return;
    }
    if (r.expireAt === undefined) {
      this.remainingText = '永久保留';
      this.lifePercent = 100;
      return;
    }
    const now = Date.now();
    this.remainingText = `剩余 ${TimeUtil.formatRemaining(r.expireAt, now)}`;
    const total = r.expireAt - r.createdAt;
    const left = r.expireAt - now;
    const frac = total <= 0 ? 0 : Math.max(0, Math.min(1, left / total));
    this.lifePercent = Math.max(2, Math.round(frac * 100));
  }

  private expireSubLabel(): string {
    const r = this.record;
    if (r === undefined) {
      return '';
    }
    if (r.expireAt === undefined) {
      return '不会自动删除';
    }
    if (r.durationType === DurationType.END_OF_TODAY) {
      return '今晚 24:00 自动删除';
    }
    return `${TimeUtil.formatDayTime(r.expireAt)} 自动删除`;
  }

  private imageSide(): number {
    const w = this.windowSize.width > 0 ? this.windowSize.width : 360;
    return w - 32;
  }

  private panLimitX(): number {
    return this.imageSide() * (this.imgScale - 1) / 2;
  }

  private panLimitY(): number {
    return this.imageSide() * (this.imgScale - 1) / 2;
  }

  private makeForever(): void {
    const target = this.record;
    if (target === undefined) {
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
          DbHelper.setForever(target.id)
            .then(() => {
              target.expireAt = undefined;
              target.durationType = DurationType.FOREVER;
              this.refreshRemaining();
              this.getUIContext().getPromptAction().showToast({ message: '已转为永久保留' });
            })
            .catch(() => {
              this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
            });
        }
      }
    });
  }

  private deleteNow(): void {
    const target = this.record;
    const ctx = this.context;
    if (target === undefined || ctx === undefined) {
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
          CleanupService.deletePhoto(ctx, target)
            .then(() => {
              this.getUIContext().getRouter().back();
            })
            .catch(() => {
              this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
            });
        }
      }
    });
  }

  private sharePhoto(): void {
    const target = this.record;
    const ctx = this.context;
    if (target === undefined || ctx === undefined) {
      return;
    }
    ShareService.sharePhoto(ctx, target)
      .then((shared: boolean) => {
        if (shared) {
          this.askDeleteAfterShare();
        }
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
      });
  }

  private askDeleteAfterShare(): void {
    const target = this.record;
    const ctx = this.context;
    if (target === undefined || ctx === undefined) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '照片已分享',
      message: '对方已收到照片，是否立即删除本地的这张照片？',
      primaryButton: {
        value: '保留',
        action: () => {
        }
      },
      secondaryButton: {
        value: '立即删除',
        fontColor: '#E64A19',
        action: () => {
          CleanupService.deletePhoto(ctx, target)
            .then(() => {
              this.getUIContext().getRouter().back();
            })
            .catch(() => {
              this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
            });
        }
      }
    });
  }

  private saveToAlbum(): void {
    const target = this.record;
    const ctx = this.context;
    if (target === undefined || ctx === undefined) {
      return;
    }
    ShareService.saveToAlbum(ctx, target)
      .then((saved: boolean) => {
        if (saved) {
          this.getUIContext().getPromptAction().showToast({ message: '已保存到系统相册' });
        }
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败' });
      });
  }

  private applyDuration(type: DurationType): void {
    const target = this.record;
    if (target === undefined) {
      return;
    }
    const expireAt = ExpiryCalculator.calc(type, Date.now());
    DbHelper.updateExpire(target.id, expireAt, type)
      .then(() => {
        target.expireAt = expireAt;
        target.durationType = type;
        this.showDurationDialog = false;
        this.refreshRemaining();
        const promptAction = this.getUIContext().getPromptAction();
        if (type === DurationType.FOREVER) {
          promptAction.showToast({ message: '已转为永久保留' });
        } else {
          promptAction.showToast({ message: '保存期限已更新' });
        }
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
      });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.record !== undefined) {
        Scroll() {
          Column({ space: 14 }) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width('100%')
                .aspectRatio(1)
                .borderRadius(16)
                .backgroundColor('#141414')
              Image(`file://${this.context?.filesDir}/${this.record.filePath}`,
                `${this.record.id}_${this.record.createdAt}`)
                .width('100%')
                .aspectRatio(1)
                .objectFit(ImageFit.Contain)
                .borderRadius(16)
                .scale({ x: this.imgScale, y: this.imgScale })
                .translate({ x: this.imgOffsetX, y: this.imgOffsetY })
                .gesture(
                  PinchGesture({ fingers: 2 })
                    .onActionStart(() => {
                      this.pinchStartScale = this.imgScale;
                    })
                    .onActionUpdate((event: GestureEvent) => {
                      this.imgScale = Math.max(1, Math.min(5, this.pinchStartScale * event.scale));
                      if (this.imgScale <= 1) {
                        this.imgOffsetX = 0;
                        this.imgOffsetY = 0;
                      }
                    })
                )
                .gesture(
                  PanGesture({ fingers: 1 })
                    .onActionStart(() => {
                      this.panStartX = this.imgOffsetX;
                      this.panStartY = this.imgOffsetY;
                    })
                    .onActionUpdate((event: GestureEvent) => {
                      if (this.imgScale <= 1) {
                        return;
                      }
                      const limitX = this.panLimitX();
                      const limitY = this.panLimitY();
                      this.imgOffsetX = Math.max(-limitX, Math.min(limitX, this.panStartX + event.offsetX));
                      this.imgOffsetY = Math.max(-limitY, Math.min(limitY, this.panStartY + event.offsetY));
                    })
                    .onActionEnd(() => {
                      if (this.imgScale <= 1) {
                        this.imgOffsetX = 0;
                        this.imgOffsetY = 0;
                      }
                    })
                )
                .shouldRecognizerParallelWith(
                  (current: GestureRecognizer, others: Array<GestureRecognizer>): GestureRecognizer => {
                    if (this.imgScale <= 1) {
                      for (const g of others) {
                        if (g.getType() === GestureControl.GestureType.PAN_GESTURE) {
                          return g;
                        }
                      }
                    }
                    return current;
                  })
            }
            .width('100%')
            .shadow({ radius: 12, color: 'rgba(28,26,23,0.12)', offsetY: 4 })

            Column({ space: 8 }) {
              Row() {
                Text('剩余寿命')
                  .fontSize(12)
                  .fontColor(Theme.DIM)
                Blank()
                Text(this.expireSubLabel())
                  .fontSize(11)
                  .fontColor(Theme.DIM)
              }
              .width('100%')

              if (this.record.expireAt === undefined) {
                Text('永久保留')
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.FOREVER)
                  .fontFeature('"tnum" on')
              } else {
                Stack({ alignContent: Alignment.Start }) {
                  Row()
                    .width('100%')
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(Theme.TRACK)
                  Row()
                    .width(`${this.lifePercent}%`)
                    .height(6)
                    .borderRadius(3)
                    .linearGradient({ angle: 90, colors: [[Theme.TODAY, 0.0], [Theme.ACCENT, 1.0]] })
                }
                .width('100%')
                Text(this.remainingText)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.ACCENT)
                  .fontFeature('"tnum" on')
              }
            }
            .width('100%')

            Text(`拍摄于 ${TimeUtil.formatShotTime(this.record.createdAt)} · 寿命「${DurationLabel.labelOf(this.record.durationType)}」`)
              .fontSize(12)
              .fontColor(Theme.DIM)
              .width('100%')
              .orphanCharOptimization(true)
              .punctuationOverflow(true)

            Column({ space: 8 }) {
              Text('备注')
                .fontSize(11)
                .fontColor(Theme.DIM)
              TextInput({ text: this.noteDraft, placeholder: '添加备注，如：3号储物柜' })
                .width('100%')
                .fontSize(14)
                .fontColor(Theme.INK)
                .backgroundColor(Theme.BG)
                .borderRadius(10)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.noteDraft = value;
                })
                .onBlur(() => {
                  const target = this.record;
                  if (target !== undefined && this.noteDraft !== target.note) {
                    DbHelper.updateNote(target.id, this.noteDraft)
                      .then(() => {
                        target.note = this.noteDraft;
                      })
                      .catch(() => {
                      });
                  }
                })
            }
            .width('100%')
            .padding(14)
            .borderRadius(16)
            .backgroundColor(Theme.CARD)
            .border({ width: 1, color: Theme.BORDER })
            .alignItems(HorizontalAlign.Start)

            Row({ space: 10 }) {
              Button('分享')
                .layoutWeight(1)
                .height(48)
                .borderRadius(24)
                .backgroundColor(Theme.ACCENT)
                .fontColor('#FFFFFF')
                .fontSize(15)
                .onClick(() => this.sharePhoto())
              Button('存相册')
                .layoutWeight(1)
                .height(48)
                .borderRadius(24)
                .backgroundColor(Theme.CARD)
                .fontColor(Theme.INK)
                .fontSize(15)
                .border({ width: 1.5, color: Theme.BORDER2 })
                .onClick(() => this.saveToAlbum())
            }
            .width('100%')

            Row() {
              Text('转永久')
                .layoutWeight(1)
                .height(52)
                .textAlign(TextAlign.Center)
                .fontSize(14)
                .fontColor(Theme.INK2)
                .opacity(this.record.expireAt === undefined ? 0.35 : 1)
                .onClick(() => {
                  if (this.record !== undefined && this.record.expireAt !== undefined) {
                    this.makeForever();
                  }
                })
              Divider()
                .vertical(true)
                .height(22)
                .color(Theme.BORDER)
              Text('改寿命')
                .layoutWeight(1)
                .height(52)
                .textAlign(TextAlign.Center)
                .fontSize(14)
                .fontColor(Theme.INK2)
                .opacity(this.record.expireAt === undefined ? 0.35 : 1)
                .onClick(() => {
                  if (this.record !== undefined && this.record.expireAt !== undefined) {
                    this.showDurationDialog = true;
                  }
                })
              Divider()
                .vertical(true)
                .height(22)
                .color(Theme.BORDER)
              Text('删除')
                .layoutWeight(1)
                .height(52)
                .textAlign(TextAlign.Center)
                .fontSize(14)
                .fontColor(Theme.DANGER)
                .onClick(() => this.deleteNow())
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(Theme.CARD)
            .border({ width: 1, color: Theme.BORDER })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 64 + this.topInset, bottom: 24 + this.bottomInset })
        }
        .height('100%')
        .width('100%')
        .scrollBar(BarState.Auto)
        .scrollBarWidth(3)
        .edgeEffect(EdgeEffect.Spring)
      }

      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor(Theme.INK)
          .width(44)
          .height(52)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Blank()
        Text('详情')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
        Blank()
        Row()
          .width(44)
          .height(52)
      }
      .width('100%')
      .padding({ top: this.topInset })
      .backgroundColor('rgba(247,246,243,0.82)')
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .systemMaterial(this.barMaterial)

      if (this.showDurationDialog && this.record !== undefined) {
        Column() {
          Column({ space: 16 }) {
            Text('修改保存期限')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.INK)
            DurationSelector({
              selected: this.record.durationType,
              onSelected: (t: DurationType) => {
                this.applyDuration(t);
              }
            })
          }
          .width('86%')
          .padding({ top: 20, bottom: 24, left: 12, right: 12 })
          .borderRadius(20)
          .backgroundColor(Theme.CARD)
          .alignItems(HorizontalAlign.Center)
          .systemMaterial(this.dialogMaterial)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(28,26,23,0.35)')
        .onClick(() => {
          this.showDurationDialog = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
