import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kpixel.dart';
import 'package:pixelarticons/pixel.dart' as px;

// coverage:ignore-start

/// Single source of truth for app icon glyphs.
///
/// Maps semantic icon names to the backing icon set (currently
/// [pixelarticons](https://pub.dev/packages/pixelarticons)). Swapping icon
/// sets only requires editing this file. Where pixelarticons lacks a close
/// equivalent, the Material icon is kept as a documented fallback.
class KIcons {
  KIcons._();

  // ── Navigation ──────
  static const IconData arrowBack = px.Pixel.arrowleft;
  static const IconData arrowBackRounded = px.Pixel.arrowleft;
  static const IconData arrowDownwardRounded = px.Pixel.arrowdown;
  static const IconData arrowUpwardRounded = px.Pixel.arrowup;
  static const IconData chevronRight = px.Pixel.chevronright;
  static const IconData chevronRightRounded = px.Pixel.chevronright;
  static const IconData expandLess = px.Pixel.chevronup;
  static const IconData expandMore = px.Pixel.chevrondown;
  static const IconData menu = px.Pixel.menu;
  static const IconData homeRounded = px.Pixel.home;
  static const IconData fullscreenRounded = px.Pixel.expand;
  static const IconData exitToAppRounded = px.Pixel.logout;
  static const IconData loginRounded = px.Pixel.login;
  static const IconData logoutRounded = px.Pixel.logout;
  static const IconData openInNew = px.Pixel.externallink;
  static const IconData openInNewRounded = px.Pixel.externallink;
  static const IconData openInBrowser = px.Pixel.externallink;

  // ── Actions ──────
  static const IconData add = px.Pixel.plus;
  static const IconData addRounded = px.Pixel.plus;
  static const IconData addCircleOutline = px.Pixel.addbox;
  static const IconData addLinkRounded = px.Pixel.link;
  static const IconData addReactionOutlined = px.Pixel.moodhappy;
  static const IconData removeCircleOutline = px.Pixel.removebox;
  static const IconData check = px.Pixel.check;
  static const IconData checkRounded = px.Pixel.check;
  static const IconData doneRounded = px.Pixel.check;
  static const IconData doneAllRounded = px.Pixel.checkdouble;
  static const IconData checkCircle = px.Pixel.checkboxon;
  static const IconData checkCircleOutline = px.Pixel.checkbox;
  static const IconData checkCircleRounded = px.Pixel.checkboxon;
  static const IconData clear = px.Pixel.close;
  static const IconData close = px.Pixel.close;
  static const IconData closeRounded = px.Pixel.close;
  static const IconData cancelOutlined = px.Pixel.close;
  static const IconData block = Icons.block; // fallback: pixelarticons has no glyph
  static const IconData blockOutlined = Icons.block_outlined; // fallback: pixelarticons has no glyph
  static const IconData blockRounded = Icons.block_rounded; // fallback: pixelarticons has no glyph
  static const IconData editOutlined = px.Pixel.edit;
  static const IconData editRounded = px.Pixel.edit;
  static const IconData copy = px.Pixel.copy;
  static const IconData copyOutlined = px.Pixel.copy;
  static const IconData copyRounded = px.Pixel.copy;
  static const IconData deleteOutline = px.Pixel.trash;
  static const IconData deleteOutlined = px.Pixel.trash;
  static const IconData deleteOutlineRounded = px.Pixel.trash;
  static const IconData deleteSweepOutlined = px.Pixel.trash;
  static const IconData refresh = px.Pixel.reload;
  static const IconData refreshRounded = px.Pixel.reload;
  static const IconData replyRounded = px.Pixel.reply;
  static const IconData forwardRounded = px.Pixel.forward;
  static const IconData sendRounded = Kpixel.send;
  static const IconData dragHandleRounded = px.Pixel.draganddrop;
  static const IconData tuneRounded = px.Pixel.sliders;
  static const IconData upgradeRounded = px.Pixel.upload;
  static const IconData systemUpdateAlt = px.Pixel.reload;

  // ── Communication ──────
  static const IconData callRounded = px.Pixel.deskphone;
  static const IconData callEnd = Icons.call_end; // fallback: pixelarticons has no glyph
  static const IconData callEndRounded = Icons.call_end_rounded; // fallback: pixelarticons has no glyph
  static const IconData callMissedRounded = px.Pixel.missedcall;
  static const IconData cameraswitch = px.Pixel.cameraface;
  static const IconData screenShare = px.Pixel.cast;
  static const IconData stopScreenShare = px.Pixel.cast;
  static const IconData videocam = px.Pixel.video;
  static const IconData videocamOff = px.Pixel.videooff;
  static const IconData videocamRounded = px.Pixel.video;
  static const IconData headsetMicRounded = px.Pixel.headset;
  static const IconData headphonesRounded = px.Pixel.headphone;
  static const IconData mic = Kpixel.mic;
  static const IconData micOff = Kpixel.micoff;
  static const IconData micOffRounded = Kpixel.micoff;
  static const IconData micRounded = Kpixel.mic;
  static const IconData keyboardRounded = px.Pixel.keyboard;
  static const IconData keyboardVoiceRounded = Kpixel.mic;
  static const IconData spatialAudioOffRounded = px.Pixel.audiodevice;
  static const IconData graphicEqRounded = px.Pixel.audiodevice;
  static const IconData audiotrackRounded = px.Pixel.music;
  static const IconData volumeUp = px.Pixel.volume;
  static const IconData volumeUpRounded = px.Pixel.volume;
  static const IconData volumeOff = px.Pixel.volumex;
  static const IconData volumeOffRounded = px.Pixel.volumex;

  // ── Chat ──────
  static const IconData chatBubble = px.Pixel.chat;
  static const IconData chatBubbleOutline = px.Pixel.chat;
  static const IconData chatBubbleOutlineRounded = px.Pixel.chat;
  static const IconData chatOutlined = px.Pixel.chat;
  static const IconData forumOutlined = px.Pixel.chat;
  static const IconData alternateEmailRounded = px.Pixel.at;
  static const IconData emojiEmotionsOutlined = px.Pixel.moodhappy;
  static const IconData emojiPeopleOutlined = px.Pixel.humanhandsup;
  static const IconData emojiSymbolsOutlined = px.Pixel.notes;

  // ── Rooms Spaces ──────
  static const IconData pushPinOutlined = px.Pixel.pin;
  static const IconData pushPinRounded = px.Pixel.pin;
  static const IconData flagOutlined = px.Pixel.flag;
  static const IconData tag = px.Pixel.label;
  static const IconData numbers = Kpixel.hash;
  static const IconData meetingRoomOutlined = px.Pixel.building;
  static const IconData workspacesOutlined = px.Pixel.group;
  static const IconData shieldOutlined = px.Pixel.shield;
  static const IconData verified = px.Pixel.checkboxon;
  static const IconData verifiedOutlined = px.Pixel.checkboxon;
  static const IconData verifiedUserOutlined = px.Pixel.shield;
  static const IconData adminPanelSettingsOutlined = px.Pixel.shield;
  static const IconData lockOutline = px.Pixel.lock;
  static const IconData lockOutlineRounded = px.Pixel.lock;
  static const IconData lockRounded = px.Pixel.lock;
  static const IconData lockOpenOutlined = px.Pixel.lockopen;
  static const IconData lockOpenRounded = px.Pixel.lockopen;
  static const IconData keyOffOutlined = px.Pixel.lockopen;
  static const IconData vpnKeyOutlined = Icons.vpn_key_outlined; // fallback: pixelarticons has no glyph

  // ── People ──────
  static const IconData person = px.Pixel.user;
  static const IconData personOutline = px.Pixel.user;
  static const IconData personRounded = px.Pixel.user;
  static const IconData personAddOutlined = px.Pixel.userplus;
  static const IconData personAddAlt1Outlined = px.Pixel.userplus;
  static const IconData personRemoveOutlined = px.Pixel.userminus;
  static const IconData groupAddRounded = px.Pixel.userplus;
  static const IconData badgeOutlined = px.Pixel.cardid;

  // ── Media Files ──────
  static const IconData cameraAltOutlined = px.Pixel.camera;
  static const IconData imageOutlined = px.Pixel.image;
  static const IconData imageRounded = px.Pixel.image;
  static const IconData brokenImageOutlined = px.Pixel.imagebroken;
  static const IconData brokenImageRounded = px.Pixel.imagebroken;
  static const IconData photoLibraryOutlined = px.Pixel.imagegallery;
  static const IconData folderOutlined = px.Pixel.folder;
  static const IconData insertDriveFileOutlined = px.Pixel.file;
  static const IconData insertDriveFileRounded = px.Pixel.file;
  static const IconData uploadFileRounded = px.Pixel.fileplus;
  static const IconData downloadRounded = px.Pixel.download;
  static const IconData cloudOff = px.Pixel.cloud;
  static const IconData cloudOffRounded = px.Pixel.cloud;
  static const IconData cloudOutlined = px.Pixel.cloud;
  static const IconData gifBoxOutlined = px.Pixel.gif;
  static const IconData stickyNote2Outlined = px.Pixel.note;
  static const IconData codeRounded = px.Pixel.code;
  static const IconData qrCode2 = Icons.qr_code_2; // fallback: pixelarticons has no glyph
  static const IconData qrCodeScanner = Icons.qr_code_scanner; // fallback: pixelarticons has no glyph

  // ── Status Feedback ──────
  static const IconData infoOutline = px.Pixel.infobox;
  static const IconData infoOutlineRounded = px.Pixel.infobox;
  static const IconData errorOutline = px.Pixel.alert;
  static const IconData errorOutlineRounded = px.Pixel.alert;
  static const IconData warningAmberRounded = px.Pixel.warningbox;
  static const IconData noiseAwareRounded = px.Pixel.alert;
  static const IconData campaignOutlined = px.Pixel.notification;
  static const IconData notificationsOutlined = px.Pixel.notification;
  static const IconData notificationsNoneRounded = px.Pixel.notification;
  static const IconData notificationsOffOutlined = px.Pixel.notificationoff;
  static const IconData scheduleRounded = px.Pixel.clock;
  static const IconData lightbulbOutline = Kpixel.lightbulb;
  static const IconData autoAwesome = px.Pixel.zap;

  // ── Search ──────
  static const IconData search = px.Pixel.search;
  static const IconData searchRounded = px.Pixel.search;
  static const IconData searchOffRounded = px.Pixel.search;
  static const IconData travelExplore = px.Pixel.gps;
  static const IconData exploreOutlined = px.Pixel.gps;

  // ── Settings Theme ──────
  static const IconData settingsOutlined = Kpixel.settingscog;
  static const IconData paletteOutlined = px.Pixel.colorsswatch;
  static const IconData darkMode = px.Pixel.moon;
  static const IconData darkModeOutlined = px.Pixel.moon;
  static const IconData lightMode = px.Pixel.sun;
  static const IconData lightModeOutlined = px.Pixel.sun;
  static const IconData brightnessAutoOutlined = px.Pixel.sun;

  // ── Devices ──────
  static const IconData devices = px.Pixel.devices;
  static const IconData devicesRounded = px.Pixel.devices;
  static const IconData devicesOtherOutlined = px.Pixel.devices;
  static const IconData desktopMacOutlined = px.Pixel.monitor;
  static const IconData monitor = px.Pixel.monitor;
  static const IconData phoneAndroidOutlined = px.Pixel.devicephone;
  static const IconData phoneIphoneOutlined = px.Pixel.devicephone;
  static const IconData window = px.Pixel.monitor;

  // ── Mail Inbox ──────
  static const IconData inbox = px.Pixel.inbox;
  static const IconData inboxOutlined = px.Pixel.inbox;
  static const IconData inboxRounded = px.Pixel.inbox;
  static const IconData mailOutlineRounded = px.Pixel.mail;

  // ── Misc ──────
  static const IconData dnsOutlined = px.Pixel.server;
  static const IconData moreHorizRounded = px.Pixel.morehorizontal;
  static const IconData moreVert = px.Pixel.morevertical;
  static const IconData moreVertRounded = px.Pixel.morevertical;
  static const IconData visibilityOutlined = px.Pixel.eye;
  static const IconData visibilityOffOutlined = px.Pixel.eyeclosed;
  static const IconData linkRounded = px.Pixel.link;
  static const IconData linkOffRounded = px.Pixel.unlink;
  static const IconData pauseRounded = px.Pixel.pause;
  static const IconData playArrowRounded = px.Pixel.play;
  static const IconData stopRounded = Kpixel.square;
  static const IconData sportsBasketballOutlined = Icons.sports_basketball_outlined; // fallback: pixelarticons has no glyph
  static const IconData fastfoodOutlined = Icons.fastfood_outlined; // fallback: pixelarticons has no glyph
  static const IconData petsOutlined = Icons.pets_outlined; // fallback: pixelarticons has no glyph
  static const IconData directionsCarOutlined = px.Pixel.car;
  static const IconData frontHandOutlined = px.Pixel.humanhandsup;
  static const IconData starRounded = Kpixel.star;
  static const IconData starBorderRounded = Icons.star_border_rounded; // fallback: pixelarticons has no glyph
  static const IconData webOutlined = Kpixel.globe;
  static const IconData cancel = px.Pixel.close;
  static const IconData chat = px.Pixel.chat;
  static const IconData delete = px.Pixel.trash;
  static const IconData gifOutlined = px.Pixel.gif;
  static const IconData reply = px.Pixel.reply;
}
// coverage:ignore-end
