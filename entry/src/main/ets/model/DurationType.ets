export enum DurationType {
  ONE_HOUR = 1,
  END_OF_TODAY = 2,
  THREE_DAYS = 3,
  SEVEN_DAYS = 4,
  FOREVER = 5
}

export class DurationLabel {
  static labelOf(type: DurationType): string {
    switch (type) {
      case DurationType.ONE_HOUR:
        return '1小时';
      case DurationType.END_OF_TODAY:
        return '今天';
      case DurationType.THREE_DAYS:
        return '3天';
      case DurationType.SEVEN_DAYS:
        return '7天';
      case DurationType.FOREVER:
        return '永久';
      default:
        return '';
    }
  }

  static all(): Array<DurationType> {
    return [
      DurationType.ONE_HOUR,
      DurationType.END_OF_TODAY,
      DurationType.THREE_DAYS,
      DurationType.SEVEN_DAYS,
      DurationType.FOREVER
    ];
  }
}
