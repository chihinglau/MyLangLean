/**
 * MyLangLean - HarmonyOS microphone recorder plugin.
 *
 * Channel: ml/audio_recorder
 * Dart side: app/lib/pal/ohos/ohos_audio_recorder.dart
 *
 * requestPermission -> ohos.permission.MICROPHONE (user_grant)
 * start             -> AVRecorder AAC into app filesDir
 * stop              -> returns sandbox file path
 */
import media from '@ohos.multimedia.media';
import fs from '@ohos.file.fs';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
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

const TAG = 'MlAudioRecorder';
const CHANNEL = 'ml/audio_recorder';
const MIC_PERMISSION = 'ohos.permission.MICROPHONE';

export default class MlAudioRecorderPlugin
  implements MethodCallHandler, FlutterPlugin, AbilityAware {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | null = null;
  private recorder: media.AVRecorder | null = null;
  private outputPath: string = '';
  private fd: number = -1;

  getUniqueClassName(): string {
    return 'MlAudioRecorderPlugin';
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
    try {
      switch (call.method) {
        case 'requestPermission':
          result.success(await this.requestPermission());
          break;
        case 'start':
          await this.start();
          result.success(null);
          break;
        case 'stop':
          result.success(await this.stop());
          break;
        default:
          result.notImplemented();
      }
    } catch (e) {
      Log.e(TAG, call.method + ' failed: ' + JSON.stringify(e));
      result.error('RECORDER_ERROR', call.method + ' failed', JSON.stringify(e));
    }
  }

  private async requestPermission(): Promise<boolean> {
    if (!this.ability) return false;
    const atManager = abilityAccessCtrl.createAtManager();
    const ctx = this.ability.context;
    const grantResult = await atManager.requestPermissionsFromUser(ctx, [
      MIC_PERMISSION,
    ]);
    return grantResult.authResults.length > 0 && grantResult.authResults[0] === 0;
  }

  private async start(): Promise<void> {
    if (!this.ability) {
      throw new Error('ability not attached');
    }
    const dir = this.ability.context.filesDir + '/recordings';
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }
    this.outputPath = `${dir}/rec_${Date.now()}.m4a`;
    const file = fs.openSync(this.outputPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    this.fd = file.fd;

    this.recorder = await media.createAVRecorder();
    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      profile: {
        audioBitrate: 96000,
        audioChannels: 1,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: 44100,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4A,
      },
      url: `fd://${this.fd}`,
      rotation: 0,
      location: { latitude: 0, longitude: 0 },
    };
    await this.recorder.prepare(config);
    await this.recorder.start();
    Log.i(TAG, 'recording -> ' + this.outputPath);
  }

  private async stop(): Promise<string> {
    if (this.recorder) {
      try {
        await this.recorder.stop();
        await this.recorder.release();
      } finally {
        this.recorder = null;
      }
    }
    if (this.fd >= 0) {
      fs.closeSync(this.fd);
      this.fd = -1;
    }
    return this.outputPath;
  }
}
