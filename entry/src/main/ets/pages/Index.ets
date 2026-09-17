import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { PhotoRepository } from '../service/PhotoRepository';
import { PhotoRecord } from '../model/PhotoRecord';
import { DetailParams } from '../model/RouteParams';
import { DurationType } from '../model/DurationType';
import { ExpiryCalculator } from '../service/ExpiryCalculator';
import { DbHelper } from '../database/DbHelper';
import { TimeUtil } from '../utils/TimeUtil';
import { Theme } from '../utils/Theme';
import { StatsHeader } from '../components/StatsHeader';
import { PhotoGridItem } from '../components/PhotoGridItem';
import { ShareService } from '../service/ShareService';
import { CleanupService } from '../service/CleanupService';

@Entry
@ComponentV2
struct Index {
  @Local photos: Array<PhotoRecord> = [];
  @Local now: number = Date.now();
  @Local refreshing: boolean = false;
  @Local selectArmed: boolean = true;
  @Local editing: boolean = false;
  @Local selectedIds: Set<number> = new Set<number>();
  @Env(ReadonlyEnvKey.WINDOW_AVOID_AREA) avoidArea: window.UIEnvWindowAvoidAreaInfoVP;
  @Env(ReadonlyEnvKey.WINDOW_SIZE) windowSize: window.SizeInVP;
  private timerId: number = -1;
  private readonly gridGap: number = 8;

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

  @Computed
  get gridItemWidth(): number {
    const w = this.windowSize.width > 0 ? this.windowSize.width : 360;
    return (w - 32 - 2 * this.gridGap) / 3;
  }

  @Computed
  get todayList(): Array<PhotoRecord> {
    const endToday = TimeUtil.endOfToday(this.now);
    const out: Array<PhotoRecord> = [];
    for (const r of this.photos) {
      if (r.expireAt !== undefined && r.expireAt <= endToday) {
        out.push(r);
      }
    }
    return out;
  }

  @Computed
  get weekList(): Array<PhotoRecord> {
    const endToday = TimeUtil.endOfToday(this.now);
    const out: Array<PhotoRecord> = [];
    for (const r of this.photos) {
      if (r.expireAt !== undefined && r.expireAt > endToday) {
        out.push(r);
      }
    }
    return out;
  }

  @Computed
  get foreverList(): Array<PhotoRecord> {
    const out: Array<PhotoRecord> = [];
    for (const r of this.photos) {
      if (r.expireAt === undefined) {
        out.push(r);
      }
    }
    return out;
  }

  @Computed
  get selectedRecords(): Array<PhotoRecord> {
    const out: Array<PhotoRecord> = [];
    for (const r of this.photos) {
      if (this.selectedIds.has(r.id)) {
        out.push(r);
      }
    }
    return out;
  }

  aboutToAppear(): void {
    this.refresh();
  }

  onPageShow(): void {
    this.now = Date.now();
    this.refresh();
    if (this.timerId === -1) {
      this.timerId = setInterval(() => {
        this.now = Date.now();
      }, 60_000);
    }
  }

  onPageHide(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
    }
  }

  private refresh(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    PhotoRepository.loadAll(ctx)
      .then((list: Array<PhotoRecord>) => {
        this.photos = list;
      })
      .catch(() => {
      });
  }

  private openCamera(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/CameraPage' });
    } catch (error) {
    }
  }

  private openDetail(r: PhotoRecord): void {
    const params: DetailParams = { id: r.id };
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/DetailPage', params: params });
    } catch (error) {
    }
  }

  private changeDuration(r: PhotoRecord, t: DurationType): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const expireAt = ExpiryCalculator.calc(t, Date.now());
    DbHelper.init(ctx)
      .then(() => {
        return DbHelper.updateExpire(r.id, expireAt, t);
      })
      .then(() => {
        this.refresh();
        this.getUIContext().getPromptAction().showToast({
          message: t === DurationType.FOREVER ? '已转为永久保留' : '保存期限已更新'
        });
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
      });
  }

  private toggleSelect(id: number, isSelected: boolean): void {
    if (isSelected) {
      this.selectedIds.add(id);
    } else {
      this.selectedIds.delete(id);
    }
  }

  private exitSelect(): void {
    this.selectArmed = false;
    this.editing = false;
    this.selectedIds.clear();
  }

  private armSelect(): void {
    this.selectArmed = true;
  }

  private batchShare(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const records = this.selectedRecords;
    if (records.length === 0) {
      this.toast('请先选择照片');
      return;
    }
    ShareService.sharePhotos(ctx, records)
      .then((shared: boolean) => {
        if (shared) {
          this.getUIContext().getPromptAction().showToast({ message: '已分享' });
        }
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
      });
  }

  private batchDelete(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const records = this.selectedRecords;
    if (records.length === 0) {
      this.toast('请先选择照片');
      return;
    }
    this.getUIContext().showAlertDialog({
      title: `删除 ${records.length} 张照片？`,
      message: '删除后无法恢复',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Theme.DANGER,
        action: () => {
          let chain: Promise<void> = Promise.resolve();
          for (const r of records) {
            chain = chain.then(() => {
              return CleanupService.deletePhoto(ctx, r);
            });
          }
          chain
            .then(() => {
              this.refresh();
            })
            .catch(() => {
              this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
              this.refresh();
            });
        }
      }
    });
  }

  private shareFromGrid(r: PhotoRecord): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ShareService.sharePhoto(ctx, r)
      .then((shared: boolean) => {
        if (shared) {
          this.askDeleteAfterShare(r);
        }
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
      });
  }

  private askDeleteAfterShare(r: PhotoRecord): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
        fontColor: Theme.DANGER,
        action: () => {
          CleanupService.deletePhoto(ctx, r)
            .then(() => {
              this.refresh();
            })
            .catch(() => {
              this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
            });
        }
      }
    });
  }

  private saveFromGrid(r: PhotoRecord): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ShareService.saveToAlbum(ctx, r)
      .then((saved: boolean) => {
        if (saved) {
          this.getUIContext().getPromptAction().showToast({ message: '已保存到系统相册' });
        }
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败' });
      });
  }

  private deleteFromGrid(r: PhotoRecord): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
        fontColor: Theme.DANGER,
        action: () => {
          CleanupService.deletePhoto(ctx, r)
            .then(() => {
              this.refresh();
            })
            .catch(() => {
              this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
            });
        }
      }
    });
  }

  private gridHeight(count: number): number {
    if (count <= 0) {
      return 0;
    }
    const rows = Math.ceil(count / 3);
    return rows * (this.gridItemWidth + 24) + (rows - 1) * 12;
  }

  @Builder
  sectionHeader(title: string, accent: string, count: number) {
    Row({ space: 10 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
      Row()
        .layoutWeight(1)
        .height(1)
        .backgroundColor(Theme.BORDER)
      Text(`${count} 张`)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(accent)
        .fontFeature('"tnum" on')
    }
    .width('100%')
    .margin({ top: 18, bottom: 10 })
  }

  @Builder
  photoGrid(list: Array<PhotoRecord>) {
    Grid() {
      ForEach(list, (r: PhotoRecord) => {
        GridItem() {
          PhotoGridItem({
            record: r,
            nowTick: this.now,
            selectionMode: this.editing,
            onItemClicked: (clicked: PhotoRecord) => {
              this.openDetail(clicked);
            },
            onShare: (shared: PhotoRecord) => {
              this.shareFromGrid(shared);
            },
            onSaveAlbum: (saved: PhotoRecord) => {
              this.saveFromGrid(saved);
            },
            onDelete: (deleted: PhotoRecord) => {
              this.deleteFromGrid(deleted);
            },
            onDurationChange: (changed: PhotoRecord, t: DurationType) => {
              this.changeDuration(changed, t);
            }
          })
        }
        .selectable(this.selectArmed)
        .onSelect((isSelected: boolean) => {
          this.toggleSelect(r.id, isSelected);
        })
      }, (r: PhotoRecord) => `${r.id}`)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(this.gridGap)
    .rowsGap(12)
    .width('100%')
    .height(this.gridHeight(list.length))
    .enableEditMode(this.selectArmed)
    .editModeOptions({ enableTwoFingerMultiSelect: true, useDefaultMultiSelectStyle: true })
    .onEditModeChange((editing: boolean) => {
      this.editing = editing;
      if (!editing) {
        this.selectedIds.clear();
      }
    })
  }

  @Builder
  batchBar() {
    Row({ space: 14 }) {
      Text(`已选 ${this.selectedIds.size} 张`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
        .fontFeature('"tnum" on')
      Blank()
      Text('分享')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.INK2)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.batchShare();
        })
      Text('删除')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.DANGER)
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .onClick(() => {
          this.batchDelete();
        })
      Text('完成')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor(Theme.INK)
        .borderRadius(17)
        .padding({ left: 18, right: 18, top: 8, bottom: 8 })
        .onClick(() => {
          this.exitSelect();
        })
    }
    .width('100%')
    .padding({ left: 14, right: 8 })
    .height(50)
    .borderRadius(25)
    .backgroundColor(Theme.CARD)
    .border({ width: 1, color: Theme.BORDER })
    .shadow({ radius: 10, color: 'rgba(28,26,23,0.18)', offsetY: 4 })
    .margin({ top: 10, bottom: 18 + this.bottomInset })
  }

  @Builder
  emptyState() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(84)
          .height(58)
          .borderRadius(12)
          .backgroundColor('#E3DFD6')
        Row()
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor('#FFFFFF')
        Row()
          .width(26)
          .height(26)
          .borderRadius(13)
          .border({ width: 3, color: '#B8B2A6' })
        Row()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor('#B8B2A6')
          .position({ x: 62, y: 12 })
      }
      .width(84)
      .height(58)

      Row()
        .width(110)
        .height(5)
        .borderRadius(3)
        .backgroundColor('#E9E6DE')
        .margin({ top: 2 })

      Column({ space: 6 }) {
        Text('还没有临时照片')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
        Text('拍一张，用完自动消失')
          .fontSize(12)
          .fontColor(Theme.DIM)
          .orphanCharOptimization(true)
          .punctuationOverflow(true)
      }
      .margin({ top: 4 })

      Row({ space: 8 }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(Theme.ACCENT)
        Text('拍第一张')
          .fontSize(15)
          .fontColor('#FFFFFF')
      }
      .padding({ left: 26, right: 26, top: 13, bottom: 13 })
      .borderRadius(24)
      .backgroundColor(Theme.INK)
      .shadow({ radius: 10, color: 'rgba(28,26,23,0.18)', offsetY: 4 })
      .margin({ top: 8 })
      .onClick(() => {
        this.openCamera();
      })
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('临时相机')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.INK)
          Text(TimeUtil.formatHeaderDate(this.now))
            .fontSize(12)
            .fontColor(Theme.DIM)
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        if (this.photos.length > 0 && !this.editing) {
          Text('多选')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.INK2)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(15)
            .backgroundColor(Theme.CARD)
            .border({ width: 1, color: Theme.BORDER })
        .onClick(() => {
          this.armSelect();
          this.toast('双指滑动照片可批量选择');
        })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 14 + this.topInset, bottom: 12 })

      StatsHeader({
        todayCount: this.todayList.length,
        weekCount: this.weekList.length,
        foreverCount: this.foreverList.length
      })

      if (this.photos.length === 0) {
        this.emptyState()
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              if (this.todayList.length > 0) {
                this.sectionHeader('今天到期', Theme.TODAY, this.todayList.length)
                this.photoGrid(this.todayList)
              }
              if (this.weekList.length > 0) {
                this.sectionHeader('7天内到期', Theme.WEEK, this.weekList.length)
                this.photoGrid(this.weekList)
              }
              if (this.foreverList.length > 0) {
                this.sectionHeader('永久保留', Theme.FOREVER, this.foreverList.length)
                this.photoGrid(this.foreverList)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 2, bottom: 8 })
          }
          .height('100%')
          .width('100%')
          .scrollBar(BarState.Auto)
          .scrollBarWidth(3)
          .edgeEffect(EdgeEffect.Spring)
        }
        .layoutWeight(1)
        .width('100%')
        .refreshOffset(64)
        .maxPullDownDistance(120)
        .onRefreshing(() => {
          this.now = Date.now();
          this.refresh();
          this.refreshing = false;
        })

        if (this.editing) {
          this.batchBar()
        } else {
          Row({ space: 8 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(4)
              .backgroundColor(Theme.ACCENT)
            Text('拍照')
              .fontSize(15)
              .fontColor('#FFFFFF')
          }
          .padding({ left: 36, right: 36, top: 15, bottom: 15 })
          .borderRadius(26)
          .backgroundColor(Theme.INK)
          .shadow({ radius: 10, color: 'rgba(28,26,23,0.18)', offsetY: 4 })
          .margin({ top: 10, bottom: 18 + this.bottomInset })
          .onClick(() => {
            this.openCamera();
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG)
  }
}
