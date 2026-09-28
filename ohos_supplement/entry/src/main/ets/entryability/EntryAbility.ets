/**
 * MERGE TARGET: ohos/entry/src/main/ets/entryability/EntryAbility.ets
 * ---------------------------------------------------------------
 * After `flutter create .` generates the ohos/ host project, replace its
 * EntryAbility with this file (or copy the two add() lines into the
 * generated configureFlutterEngine).
 *
 * It registers the three MyLangLean PAL plugins directly (they live inside
 * the app module, so no GeneratedPluginRegistrant entry is needed).
 */
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import MlAudioPlayerPlugin from '../plugins/ml_audio_player/MlAudioPlayerPlugin';
import MlAudioRecorderPlugin from '../plugins/ml_audio_recorder/MlAudioRecorderPlugin';
import MlMediaPickerPlugin from '../plugins/ml_media_picker/MlMediaPickerPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);

    // MyLangLean PAL plugins (AVPlayer / AVRecorder / system picker).
    flutterEngine.getPlugins()?.add(new MlAudioPlayerPlugin());
    flutterEngine.getPlugins()?.add(new MlAudioRecorderPlugin());
    flutterEngine.getPlugins()?.add(new MlMediaPickerPlugin());
  }
}
