import 'package:vodozemac/vodozemac.dart' as vod;

Future<void> initVodozemac() =>
    vod.init(wasmPath: './assets/assets/vodozemac/');
