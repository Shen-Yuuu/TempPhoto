import { DurationType } from '../model/DurationType';
import { TimeUtil } from '../utils/TimeUtil';

export class ExpiryCalculator {
  static calc(type: DurationType, createdAt: number): number | undefined {
    switch (type) {
      case DurationType.ONE_HOUR:
        return createdAt + 3_600_000;
      case DurationType.END_OF_TODAY:
        return TimeUtil.endOfToday(createdAt);
      case DurationType.THREE_DAYS:
        return createdAt + 3 * 86_400_000;
      case DurationType.SEVEN_DAYS:
        return createdAt + 7 * 86_400_000;
      case DurationType.FOREVER:
        return undefined;
      default:
        return undefined;
    }
  }
}
