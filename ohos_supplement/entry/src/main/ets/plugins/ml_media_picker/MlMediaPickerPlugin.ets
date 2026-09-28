/**
 * MyLangLean - HarmonyOS system media picker plugin.
 *
 * Channel: ml/media_picker
 * Dart side: app/lib/pal/ohos/ohos_media_picker.dart
 *
 * Uses AudioViewPicker (no storage permission required). The picker returns
 * temporary read-only uris, so the file is copied into the app sandbox before
 * the permanent path is handed back to Dart.
 */
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import UIAbility from '@ohos.app.ability.UIAbility';

const TAG = 'MlMediaPicker';
const CHANNEL = 'ml/media_picker';

export default class MlMediaPickerPlugin
  implements MethodCallHandler, FlutterPlugin, AbilityAware {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;

  getUniqueClassName(): string {
    return 'MlMediaPickerPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  onDetachedFromAbility(): void {
    this.ability = null;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method !== 'pickAudio') {
      result.notImplemented();
      return;
    }
    try {
      const picked = await this.pickAudio();
      result.success(picked); // null when user cancels
    } catch (e) {
      Log.e(TAG, 'pickAudio failed: ' + JSON.stringify(e));
      result.error('PICKER_ERROR', 'pickAudio failed', JSON.stringify(e));
    }
  }

  private async pickAudio(): Promise<Record<string, Object> | null> {
    if (!this.ability) return null;
    const audioPicker = new picker.AudioViewPicker();
    const selectResult = await audioPicker.select({
      maxSelectNumber: 1,
    } as picker.AudioSelectOptions);
    if (!selectResult || selectResult.length === 0) {
      return null;
    }
    const srcUri = selectResult[0];
    const context = this.ability.context;
    const dir = context.filesDir + '/imports';
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }
    const segments = srcUri.split('/');
    const fileName = segments[segments.length - 1].split('?')[0] ||
      `audio_${Date.now()}.m4a`;
    const destPath = `${dir}/${fileName}`;
    await fs.copy(srcUri, destPath);

    return {
      'path': destPath,
      'title': fileName,
      'durationMs': 0,
    };
  }
}
