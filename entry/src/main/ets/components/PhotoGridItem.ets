import { PhotoRecord } from '../model/PhotoRecord';
import { TimeUtil } from '../utils/TimeUtil';
import { Theme } from '../utils/Theme';
import { PressScaleModifier } from '../utils/PressScaleModifier';
import { DurationType } from '../model/DurationType';
import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';

@ComponentV2
export struct PhotoGridItem {
  @Param record: PhotoRecord = new PhotoRecord();
  @Param nowTick: number = Date.now();
  @Param selectionMode: boolean = false;
  @Param onItemClicked: (r: PhotoRecord) => void = (r: PhotoRecord) => {
  };
  @Param onShare: (r: PhotoRecord) => void = (r: PhotoRecord) => {
  };
  @Param onSaveAlbum: (r: PhotoRecord) => void = (r: PhotoRecord) => {
  };
  @Param onDelete: (r: PhotoRecord) => void = (r: PhotoRecord) => {
  };
  @Param onDurationChange: (r: PhotoRecord, t: DurationType) => void = (r: PhotoRecord, t: DurationType) => {
  };
  @Local filesDir: string = '';
  private pressModifier: PressScaleModifier = new PressScaleModifier();
  private menuMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: 'rgba(247,246,243,0.72)'
  });

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
  }

  @Builder
  cellMenu() {
    Menu() {
      MenuItem({ startIcon: $r('app.media.ic_share'), content: '分享' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onShare(this.record);
          }
        })
      MenuItem({ startIcon: $r('app.media.ic_album'), content: '存相册' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onSaveAlbum(this.record);
          }
        })
      MenuItem({ startIcon: $r('app.media.ic_timer'), content: '改寿命' })
        .subMenuBuilder(this.durationMenu)
      MenuItem({ startIcon: $r('app.media.ic_delete'), content: '删除' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDelete(this.record);
          }
        })
    }
  }

  @Builder
  durationMenu() {
    Menu() {
      MenuItem({ content: '1小时' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDurationChange(this.record, DurationType.ONE_HOUR);
          }
        })
      MenuItem({ content: '今天' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDurationChange(this.record, DurationType.END_OF_TODAY);
          }
        })
      MenuItem({ content: '3天' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDurationChange(this.record, DurationType.THREE_DAYS);
          }
        })
      MenuItem({ content: '7天' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDurationChange(this.record, DurationType.SEVEN_DAYS);
          }
        })
      MenuItem({ content: '永久' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDurationChange(this.record, DurationType.FOREVER);
          }
        })
    }
  }

  private badgeText(): string {
    if (this.record.expireAt === undefined) {
      return '永久';
    }
    return TimeUtil.formatRemaining(this.record.expireAt, this.nowTick);
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        Image(`file://${this.filesDir}/${this.record.filePath}`, `${this.record.id}_${this.record.createdAt}`)
          .width('100%')
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .draggable(false)
          .shadow({ radius: 6, color: 'rgba(28,26,23,0.08)', offsetY: 2 })
          .onClick(() => {
            if (!this.selectionMode) {
              this.onItemClicked(this.record);
            }
          })
        Text(this.badgeText())
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(this.record.expireAt === undefined ? Theme.FOREVER : Theme.BADGE_BG)
          .borderRadius(8)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .margin(6)
      }
      .width('100%')
      .attributeModifier(this.pressModifier)
      Text(this.record.note === '' ? TimeUtil.formatShotTime(this.record.createdAt) : this.record.note)
        .fontSize(11)
        .height(16)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor(Theme.INK2)
        .width('100%')
        .margin({ top: 6, bottom: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .bindContextMenuByResponseType(this.cellMenu, ResponseType.LongPress, {
      preview: MenuPreviewMode.IMAGE,
      previewBorderRadius: 12,
      systemMaterial: this.menuMaterial,
      gridStyle: { count: 4, horizontalSize: 4, position: MenuGridPosition.BOTTOM }
    })
  }
}
