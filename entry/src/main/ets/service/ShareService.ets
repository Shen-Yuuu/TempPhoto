import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PhotoRecord } from '../model/PhotoRecord';

const DOMAIN = 0x0014;
const TAG = 'ShareService';

export class ShareService {
  static sharePhoto(context: common.UIAbilityContext, record: PhotoRecord): Promise<boolean> {
    return ShareService.sharePhotos(context, [record]);
  }

  static sharePhotos(context: common.UIAbilityContext, records: Array<PhotoRecord>): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      if (records.length === 0) {
        resolve(false);
        return;
      }
      const paths: Array<string> = [];
      for (const r of records) {
        const absolutePath = `${context.filesDir}/${r.filePath}`;
        let exists = false;
        try {
          exists = fs.accessSync(absolutePath);
        } catch (err) {
          exists = false;
        }
        if (!exists) {
          // 文件缺失属于真实失败，需让调用方提示用户，而非静默当作取消
          throw new Error(`photo file missing: ${r.filePath}`);
        }
        paths.push(absolutePath);
      }
      const utdTypeId = utd.getUniformDataTypeByFilenameExtension('.jpg', utd.UniformDataType.IMAGE);
      const first: systemShare.SharedRecord = {
        utd: utdTypeId,
        uri: fileUri.getUriFromPath(paths[0]),
        title: records[0].note === '' ? '临时照片' : records[0].note
      };
      const shareData: systemShare.SharedData = new systemShare.SharedData(first);
      for (let i = 1; i < paths.length; i++) {
        const extra: systemShare.SharedRecord = {
          utd: utdTypeId,
          uri: fileUri.getUriFromPath(paths[i]),
          title: records[i].note === '' ? `临时照片 ${i + 1}` : records[i].note
        };
        shareData.addRecord(extra);
      }
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      let shared = false;
      controller.on('shareCompleted', () => {
        shared = true;
      });
      controller.on('dismiss', () => {
        resolve(shared);
      });
      controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'share panel show failed: %{public}d', error.code);
        resolve(false);
      });
    });
  }

  static async saveToAlbum(context: common.UIAbilityContext, record: PhotoRecord): Promise<boolean> {
    const absolutePath = `${context.filesDir}/${record.filePath}`;
    let exists = false;
    try {
      exists = fs.accessSync(absolutePath);
    } catch (err) {
      exists = false;
    }
    if (!exists) {
      throw new Error('photo file missing');
    }
    try {
      const srcFileUris: Array<string> = [fileUri.getUriFromPath(absolutePath)];
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        fileNameExtension: 'jpg',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        title: record.note === '' ? `temp_${record.createdAt}` : record.note
      }];
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const desFileUris: Array<string> =
        await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      if (desFileUris.length === 0) {
        return false;
      }
      const srcFile = fs.openSync(srcFileUris[0], fs.OpenMode.READ_ONLY);
      const desFile = fs.openSync(desFileUris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(srcFile.fd, desFile.fd);
      fs.closeSync(srcFile);
      fs.closeSync(desFile);
      return true;
    } catch (err) {
      throw new Error(`save to album failed: ${err}`);
    }
  }
}
