export class TimeUtil {
  static endOfToday(ts: number): number {
    const d = new Date(ts);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 0, 0, 0, 0).getTime();
  }

  static formatDay(ts: number): string {
    const d = new Date(ts);
    const m = `${d.getMonth() + 1}`.padStart(2, '0');
    const day = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}${m}${day}`;
  }

  static formatRemaining(expireAt: number | undefined, now: number): string {
    if (expireAt === undefined) {
      return '永久';
    }
    const diff = expireAt - now;
    if (diff <= 0) {
      return '待清理';
    }
    if (diff < 3_600_000) {
      return `剩${Math.max(1, Math.floor(diff / 60_000))}分钟`;
    }
    if (diff < 86_400_000) {
      return `剩${Math.floor(diff / 3_600_000)}小时${Math.floor((diff % 3_600_000) / 60_000)}分`;
    }
    return `剩${Math.floor(diff / 86_400_000)}天`;
  }

  static formatHeaderDate(ts: number): string {
    const d = new Date(ts);
    const week: Array<string> = ['日', '一', '二', '三', '四', '五', '六'];
    return `${d.getMonth() + 1}月${d.getDate()}日 周${week[d.getDay()]}`;
  }

  static formatDayTime(ts: number): string {
    const d = new Date(ts);
    const hh = `${d.getHours()}`.padStart(2, '0');
    const mm = `${d.getMinutes()}`.padStart(2, '0');
    return `${d.getMonth() + 1}月${d.getDate()}日 ${hh}:${mm}`;
  }

  static formatShotTime(ts: number): string {
    const d = new Date(ts);
    const hh = `${d.getHours()}`.padStart(2, '0');
    const mm = `${d.getMinutes()}`.padStart(2, '0');
    return `${d.getFullYear()}-${`${d.getMonth() + 1}`.padStart(2, '0')}-${`${d.getDate()}`.padStart(2, '0')} ${hh}:${mm}`;
  }
}
