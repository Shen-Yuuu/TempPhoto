import { DurationType } from './DurationType';

@ObservedV2
export class PhotoRecord {
  @Trace id: number = -1;
  @Trace filePath: string = '';
  @Trace note: string = '';
  @Trace createdAt: number = 0;
  @Trace expireAt: number | undefined = undefined;
  @Trace durationType: DurationType = DurationType.FOREVER;
}
