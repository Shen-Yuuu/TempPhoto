import { DurationType, DurationLabel } from '../model/DurationType';
import { Theme } from '../utils/Theme';

@ComponentV2
export struct DurationSelector {
  @Param selected: DurationType = DurationType.END_OF_TODAY;
  @Param onSelected: (t: DurationType) => void = (t: DurationType) => {
  };

  private pillShadow(active: boolean): ShadowOptions {
    if (active) {
      return { radius: 4, color: 'rgba(230,74,25,0.35)', offsetY: 2 };
    }
    return { radius: 3, color: 'rgba(28,26,23,0.06)', offsetY: 1 };
  }

  build() {
    // 窄容器（如详情页弹窗）下 5 档可能超宽，套横向滚动兜底
    Scroll() {
      Row({ space: 8 }) {
        ForEach(DurationLabel.all(), (t: DurationType) => {
          Text(DurationLabel.labelOf(t))
            .fontSize(13)
            .fontWeight(this.selected === t ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.selected === t ? '#FFFFFF' : Theme.INK2)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(18)
            .backgroundColor(this.selected === t ? Theme.ACCENT : Theme.CARD)
            .shadow(this.pillShadow(this.selected === t))
            .animation({ duration: 180, curve: Curve.EaseOut })
            .onClick(() => this.onSelected(t))
        }, (t: DurationType) => `${t}`)
      }
      .justifyContent(FlexAlign.Center)
      .constraintSize({ minWidth: '100%' })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }
}
