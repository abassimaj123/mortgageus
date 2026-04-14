class AdConfig {
  static const bool adsEnabled = true;

  // Replace with real IDs from AdMob console before release
  // Publisher: pub-5379540026739666
  // App: com.mortgageus.calculator
  static const String bannerAndroid       = 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const String rewardedAndroid     = 'ca-app-pub-3940256099942544/5224354917';

  // iOS — same test IDs
  static const String banneriOS           = 'ca-app-pub-3940256099942544/2934735716';
  static const String interstitialiOS     = 'ca-app-pub-3940256099942544/4411468910';
  static const String rewardediOS         = 'ca-app-pub-3940256099942544/1712485313';

  static const int  calcThreshold  = 5;
  static const int  cooldownMinutes = 5;
}
