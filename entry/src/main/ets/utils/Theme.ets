export class Theme {
  static readonly BG: string = '#F7F6F3';
  static readonly CARD: string = '#FFFFFF';
  static readonly INK: string = '#1C1A17';
  static readonly INK2: string = '#55504A';
  static readonly DIM: string = '#8A857C';
  static readonly BORDER: string = '#E8E5DF';
  static readonly BORDER2: string = '#DDD9D0';
  static readonly TRACK: string = '#E8E5DF';
  static readonly WEEK: string = '#C9C4BA';
  static readonly ACCENT: string = '#E64A19';
  static readonly ACCENT_LIGHT: string = '#F4632F';
  static readonly TODAY: string = '#D97706';
  static readonly FOREVER: string = '#16A34A';
  static readonly DANGER: string = '#DC2626';
  static readonly BADGE_BG: string = 'rgba(28,26,23,0.72)';
  static readonly INK_DEEP: string = '#3A342D';
  static readonly R_S: number = 8;
  static readonly R_M: number = 12;
  static readonly R_L: number = 16;
  static readonly R_XL: number = 24;

  static shadowSm(): ShadowOptions {
    return { radius: 6, color: 'rgba(28,26,23,0.08)', offsetY: 2 };
  }

  static shadowMd(): ShadowOptions {
    return { radius: 10, color: 'rgba(28,26,23,0.18)', offsetY: 4 };
  }

  static shadowLg(): ShadowOptions {
    return { radius: 16, color: 'rgba(28,26,23,0.22)', offsetY: 6 };
  }
}
