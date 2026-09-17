import { Theme } from '../utils/Theme';

@ComponentV2
export struct StatsHeader {
  @Param todayCount: number = 0;
  @Param weekCount: number = 0;
  @Param foreverCount: number = 0;

  build() {
    Column({ space: 10 }) {
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

      Row({ space: 14 }) {
        StatsHeader.legend(Theme.TODAY, '今天清理', `${this.todayCount}`)
        StatsHeader.legend(Theme.WEEK, '7天内清理', `${this.weekCount}`)
        StatsHeader.legend(Theme.FOREVER, '永久保留', `${this.foreverCount}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2 })
  }

  @Builder
  static legend(dotColor: string, label: string, count: string) {
    Row({ space: 5 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(dotColor)
      Text(label)
        .fontSize(11)
        .fontColor(Theme.DIM)
      Text(count)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
        .fontFeature('"tnum" on')
    }
    .alignItems(VerticalAlign.Center)
  }
}
