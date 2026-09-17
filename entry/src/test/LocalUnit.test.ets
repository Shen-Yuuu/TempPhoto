import { describe, it, expect } from '@ohos/hypium';
import { ExpiryCalculator } from '../main/ets/service/ExpiryCalculator';
import { DurationType } from '../main/ets/model/DurationType';
import { TimeUtil } from '../main/ets/utils/TimeUtil';

export default function localUnitTest() {
  describe('ExpiryCalculatorTest', () => {
    const T0 = new Date(2026, 8, 15, 10, 0, 0, 0).getTime();

    it('oneHour', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.ONE_HOUR, T0)).assertEqual(T0 + 3_600_000);
    });
    it('endOfToday', 0, () => {
      const midnight = new Date(2026, 8, 16, 0, 0, 0, 0).getTime();
      expect(ExpiryCalculator.calc(DurationType.END_OF_TODAY, T0)).assertEqual(midnight);
    });
    it('endOfTodayNearMidnight', 0, () => {
      const t = new Date(2026, 8, 15, 23, 59, 0, 0).getTime();
      const midnight = new Date(2026, 8, 16, 0, 0, 0, 0).getTime();
      expect(ExpiryCalculator.calc(DurationType.END_OF_TODAY, t)).assertEqual(midnight);
    });
    it('threeDays', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.THREE_DAYS, T0)).assertEqual(T0 + 3 * 86_400_000);
    });
    it('sevenDays', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.SEVEN_DAYS, T0)).assertEqual(T0 + 7 * 86_400_000);
    });
    it('forever', 0, () => {
      expect(ExpiryCalculator.calc(DurationType.FOREVER, T0)).assertUndefined();
    });
  });

  describe('TimeUtilTest', () => {
    it('formatDay', 0, () => {
      expect(TimeUtil.formatDay(new Date(2026, 8, 5, 8, 0, 0).getTime())).assertEqual('20260905');
    });
    it('remainingForever', 0, () => {
      expect(TimeUtil.formatRemaining(undefined, 1000)).assertEqual('永久');
    });
    it('remainingExpired', 0, () => {
      expect(TimeUtil.formatRemaining(500, 1000)).assertEqual('待清理');
    });
    it('remainingMinutes', 0, () => {
      expect(TimeUtil.formatRemaining(1000 + 30 * 60_000, 1000)).assertEqual('剩30分钟');
    });
    it('remainingHours', 0, () => {
      expect(TimeUtil.formatRemaining(1000 + 3 * 3_600_000, 1000)).assertEqual('剩3小时0分');
    });
    it('remainingDays', 0, () => {
      expect(TimeUtil.formatRemaining(1000 + 5 * 86_400_000, 1000)).assertEqual('剩5天');
    });
  });
}
