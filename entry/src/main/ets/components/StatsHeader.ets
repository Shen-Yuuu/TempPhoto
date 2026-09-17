import { Theme } from '../utils/Theme';

@ComponentV2
export struct StatsHeader {
  @Param todayCount: number = 0;
  @Param weekCount: number = 0;
  @Param foreverCount: number = 0;

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        StatsHeader.statCard(Theme.TODAY, `${this.todayCount}`, '今天清理')
        StatsHeader.statCard(Theme.WEEK, `${this.weekCount}`, '7天内清理')
        StatsHeader.statCard(Theme.FOREVER, `${this.foreverCount}`, '永久保留')
      }
      .width('100%')

      Row() {
        if (this.todayCount > 0) {
          Row()
            .layoutWeight(this.todayCount)
            .height(6)
            .backgroundColor(Theme.TODAY)
        }
        if (this.weekCount > 0) {
          Row()
            .layoutWeight(this.weekCount)
            .height(6)
            .backgroundColor(Theme.WEEK)
        }
        if (this.foreverCount > 0) {
          Row()
            .layoutWeight(this.foreverCount)
            .height(6)
            .backgroundColor(Theme.FOREVER)
        }
        if (this.todayCount === 0 && this.weekCount === 0 && this.foreverCount === 0) {
          Row()
            .layoutWeight(1)
            .height(6)
            .backgroundColor(Theme.TRACK)
        }
      }
      .width('100%')
      .borderRadius(3)
      .clip(true)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2 })
  }

  @Builder
  static statCard(dotColor: string, count: string, label: string) {
    Column({ space: 6 }) {
      Row({ space: 5 }) {
        Row()
          .width(7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(dotColor)
        Text(count)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .fontFeature('"tnum" on')
      }
      .alignItems(VerticalAlign.Center)

      Text(label)
        .fontSize(11)
        .fontColor(Theme.DIM)
        .orphanCharOptimization(true)
        .punctuationOverflow(true)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(Theme.CARD)
    .border({ width: 1, color: Theme.BORDER })
    .shadow(Theme.shadowSm())
    .alignItems(HorizontalAlign.Center)
  }
}
