import 'package:timeago/timeago.dart' as timeago;

/// Registers relative-time ("9 hours ago") messages for every locale the app
/// supports, so [timeago.format] renders in the user's language instead of
/// silently falling back to English.
///
/// `timeago` keeps its locale table in top-level mutable state, so this is
/// called once from `bootstrap()` before the app runs. Each locale is keyed by
/// its bare `languageCode` (the value of `Localizations.localeOf(context)
/// .languageCode`) so call sites can pass that code straight through.
///
/// `timeago` ships messages for most of our locales. The four it lacks —
/// Marathi, Punjabi, Swahili, Telugu — get the hand-written `LookupMessages`
/// below, keeping us compliant with the project policy that new user-facing
/// strings land in all 24 locales rather than English-only.
void registerTimeagoLocales() {
  // Locales covered by timeago's bundled messages. `pt` and `zh` have no bare
  // variant in the package, so they map to the closest shipped one.
  timeago.setLocaleMessages('ar', timeago.ArMessages());
  timeago.setLocaleMessages('bn', timeago.BnMessages());
  timeago.setLocaleMessages('de', timeago.DeMessages());
  timeago.setLocaleMessages('en', timeago.EnMessages());
  timeago.setLocaleMessages('es', timeago.EsMessages());
  timeago.setLocaleMessages('fa', timeago.FaMessages());
  timeago.setLocaleMessages('fr', timeago.FrMessages());
  timeago.setLocaleMessages('hi', timeago.HiMessages());
  timeago.setLocaleMessages('id', timeago.IdMessages());
  timeago.setLocaleMessages('ja', timeago.JaMessages());
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  timeago.setLocaleMessages('pt', timeago.PtBrMessages());
  timeago.setLocaleMessages('ru', timeago.RuMessages());
  timeago.setLocaleMessages('ta', timeago.TaMessages());
  timeago.setLocaleMessages('th', timeago.ThMessages());
  timeago.setLocaleMessages('tr', timeago.TrMessages());
  timeago.setLocaleMessages('uk', timeago.UkMessages());
  timeago.setLocaleMessages('ur', timeago.UrMessages());
  timeago.setLocaleMessages('vi', timeago.ViMessages());
  timeago.setLocaleMessages('zh', timeago.ZhMessages());

  // Locales timeago doesn't bundle — provided in-repo.
  timeago.setLocaleMessages('mr', MrMessages());
  timeago.setLocaleMessages('pa', PaMessages());
  timeago.setLocaleMessages('sw', SwMessages());
  timeago.setLocaleMessages('te', TeMessages());
}

/// Marathi (मराठी) relative-time messages.
class MrMessages implements timeago.LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => '';
  @override
  String suffixAgo() => 'पूर्वी';
  @override
  String suffixFromNow() => 'नंतर';
  @override
  String lessThanOneMinute(int seconds) => 'काही क्षण';
  @override
  String aboutAMinute(int minutes) => 'एक मिनिट';
  @override
  String minutes(int minutes) => '$minutes मिनिटे';
  @override
  String aboutAnHour(int minutes) => 'सुमारे एक तास';
  @override
  String hours(int hours) => '$hours तास';
  @override
  String aDay(int hours) => 'एक दिवस';
  @override
  String days(int days) => '$days दिवस';
  @override
  String aboutAMonth(int days) => 'सुमारे एक महिना';
  @override
  String months(int months) => '$months महिने';
  @override
  String aboutAYear(int year) => 'सुमारे एक वर्ष';
  @override
  String years(int years) => '$years वर्षे';
  @override
  String wordSeparator() => ' ';
}

/// Punjabi (ਪੰਜਾਬੀ) relative-time messages.
class PaMessages implements timeago.LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => '';
  @override
  String suffixAgo() => 'ਪਹਿਲਾਂ';
  @override
  String suffixFromNow() => 'ਬਾਅਦ';
  @override
  String lessThanOneMinute(int seconds) => 'ਕੁਝ ਪਲ';
  @override
  String aboutAMinute(int minutes) => 'ਇੱਕ ਮਿੰਟ';
  @override
  String minutes(int minutes) => '$minutes ਮਿੰਟ';
  @override
  String aboutAnHour(int minutes) => 'ਲਗਭਗ ਇੱਕ ਘੰਟਾ';
  @override
  String hours(int hours) => '$hours ਘੰਟੇ';
  @override
  String aDay(int hours) => 'ਇੱਕ ਦਿਨ';
  @override
  String days(int days) => '$days ਦਿਨ';
  @override
  String aboutAMonth(int days) => 'ਲਗਭਗ ਇੱਕ ਮਹੀਨਾ';
  @override
  String months(int months) => '$months ਮਹੀਨੇ';
  @override
  String aboutAYear(int year) => 'ਲਗਭਗ ਇੱਕ ਸਾਲ';
  @override
  String years(int years) => '$years ਸਾਲ';
  @override
  String wordSeparator() => ' ';
}

/// Swahili (Kiswahili) relative-time messages.
class SwMessages implements timeago.LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => 'baada ya';
  @override
  String suffixAgo() => 'zilizopita';
  @override
  String suffixFromNow() => '';
  @override
  String lessThanOneMinute(int seconds) => 'sekunde chache';
  @override
  String aboutAMinute(int minutes) => 'dakika moja';
  @override
  String minutes(int minutes) => 'dakika $minutes';
  @override
  String aboutAnHour(int minutes) => 'takriban saa moja';
  @override
  String hours(int hours) => 'saa $hours';
  @override
  String aDay(int hours) => 'siku moja';
  @override
  String days(int days) => 'siku $days';
  @override
  String aboutAMonth(int days) => 'takriban mwezi mmoja';
  @override
  String months(int months) => 'miezi $months';
  @override
  String aboutAYear(int year) => 'takriban mwaka mmoja';
  @override
  String years(int years) => 'miaka $years';
  @override
  String wordSeparator() => ' ';
}

/// Telugu (తెలుగు) relative-time messages.
class TeMessages implements timeago.LookupMessages {
  @override
  String prefixAgo() => '';
  @override
  String prefixFromNow() => '';
  @override
  String suffixAgo() => 'క్రితం';
  @override
  String suffixFromNow() => 'లో';
  @override
  String lessThanOneMinute(int seconds) => 'కొన్ని క్షణాల';
  @override
  String aboutAMinute(int minutes) => 'ఒక నిమిషం';
  @override
  String minutes(int minutes) => '$minutes నిమిషాల';
  @override
  String aboutAnHour(int minutes) => 'సుమారు ఒక గంట';
  @override
  String hours(int hours) => '$hours గంటల';
  @override
  String aDay(int hours) => 'ఒక రోజు';
  @override
  String days(int days) => '$days రోజుల';
  @override
  String aboutAMonth(int days) => 'సుమారు ఒక నెల';
  @override
  String months(int months) => '$months నెలల';
  @override
  String aboutAYear(int year) => 'సుమారు ఒక సంవత్సరం';
  @override
  String years(int years) => '$years సంవత్సరాల';
  @override
  String wordSeparator() => ' ';
}
