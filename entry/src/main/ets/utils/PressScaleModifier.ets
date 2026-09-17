import { CommonModifier } from '@kit.ArkUI';

export class PressScaleModifier extends CommonModifier {
  applyNormalAttribute(instance: CommonAttribute): void {
    instance.scale({ x: 1, y: 1 });
  }

  applyPressedAttribute(instance: CommonAttribute): void {
    instance.scale({ x: 0.96, y: 0.96 });
  }
}
