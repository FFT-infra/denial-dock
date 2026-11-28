import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_shell_kit/kit_store.dart';
import 'package:denial_shell_kit/kit_style.dart';
import 'package:denial_shell_kit/kit_widgets.dart';
import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, Material, MaterialType, TextField;
import 'package:flutter/widgets.dart';

import '../bar_icons.dart';
import '../bar_type.dart';
import '../l10n.dart';
import 'mac_kit.dart';

/// Persisted city name for the Weather widget.
final ValueNotifier<String> widgetWeatherCity = ValueNotifier<String>(
  _readStoredCity(),
);

String _readStoredCity() {
  final raw = kitStore.read()['widgetWeatherCity'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  return 'Beijing';
}

void setWidgetWeatherCity(String city) {
  final clean = city.trim();
  if (clean.isEmpty) return;
  widgetWeatherCity.value = clean;
  kitStore.put('widgetWeatherCity', clean);
  _WeatherCache.invalidate();
}

class _WeatherData {
  const _WeatherData({
    required this.city,
    required this.tempC,
    required this.highC,
    required this.lowC,
    required this.code,
    required this.humidity,
    required this.windKmh,
    required this.fetchedAt,
  });

  final String city;
  final double tempC;
  final double highC;
  final double lowC;
  final int code;
  final int humidity;
  final double windKmh;
  final DateTime fetchedAt;
}

abstract final class _WeatherCache {
  static _WeatherData? last;
  static String? lastError;
  static Future<_WeatherData?>? _inFlight;

  static void invalidate() {
    last = null;
    lastError = null;
  }

  static Future<_WeatherData?> fetch(String city, {bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        last != null &&
        last!.city.toLowerCase() == city.toLowerCase() &&
        now.difference(last!.fetchedAt) < const Duration(minutes: 30)) {
      return last;
    }
    if (_inFlight != null) return _inFlight;
    _inFlight = _doFetch(city);
    try {
      return await _inFlight;
    } finally {
      _inFlight = null;
    }
  }

  static Future<_WeatherData?> _doFetch(String city) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': city,
        'count': '1',
        'language': 'en',
        'format': 'json',
      });
      final geoReq = await client.getUrl(geoUri).timeout(const Duration(seconds: 4));
      final geoRes = await geoReq.close().timeout(const Duration(seconds: 4));
      if (geoRes.statusCode != 200) {
        lastError = 'Offline';
        return last;
      }
      final geoBody = await geoRes.transform(utf8.decoder).join();
      final geoJson = jsonDecode(geoBody);
      final results = geoJson is Map ? geoJson['results'] : null;
      if (results is! List || results.isEmpty || results.first is! Map) {
        lastError = 'City not found';
        return null;
      }
      final first = results.first as Map;
      final lat = (first['latitude'] as num).toDouble();
      final lon = (first['longitude'] as num).toDouble();
      final resolvedName = (first['name'] as String?) ?? city;

      final wxUri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'current':
            'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m',
        'daily': 'temperature_2m_max,temperature_2m_min',
        'timezone': 'auto',
        'forecast_days': '1',
      });
      final wxReq = await client.getUrl(wxUri).timeout(const Duration(seconds: 4));
      final wxRes = await wxReq.close().timeout(const Duration(seconds: 4));
      if (wxRes.statusCode != 200) {
        lastError = 'Offline';
        return last;
      }
      final wxBody = await wxRes.transform(utf8.decoder).join();
      final wxJson = jsonDecode(wxBody);
      if (wxJson is! Map) return last;
      final cur = wxJson['current'] as Map?;
      final daily = wxJson['daily'] as Map?;
      if (cur == null) return last;
      final highs = daily?['temperature_2m_max'] as List?;
      final lows = daily?['temperature_2m_min'] as List?;
      final temp = (cur['temperature_2m'] as num?)?.toDouble() ?? 0;
      final data = _WeatherData(
        city: resolvedName,
        tempC: temp,
        highC: (highs != null && highs.isNotEmpty && highs.first is num)
            ? (highs.first as num).toDouble()
            : temp,
        lowC: (lows != null && lows.isNotEmpty && lows.first is num)
            ? (lows.first as num).toDouble()
            : temp,
        code: (cur['weather_code'] as num?)?.toInt() ?? 0,
        humidity: (cur['relative_humidity_2m'] as num?)?.toInt() ?? 0,
        windKmh: (cur['wind_speed_10m'] as num?)?.toDouble() ?? 0,
        fetchedAt: DateTime.now(),
      );
      last = data;
      lastError = null;
      return data;
    } catch (_) {
      lastError = 'Offline';
      return last;
    } finally {
      client.close(force: true);
    }
  }
}

(IconData, String) _describeWmo(int code) {
  if (code == 0) return (BarIcons.sunMaxFill, 'Clear');
  if (code <= 3) return (BarIcons.sunMax, 'Partly Cloudy');
  if (code == 45 || code == 48) return (BarIcons.circleHalf, 'Fog');
  if (code >= 51 && code <= 67) return (BarIcons.boltFill, 'Rain');
  if (code >= 71 && code <= 77) return (BarIcons.moonFill, 'Snow');
  if (code >= 80 && code <= 82) return (BarIcons.boltFill, 'Showers');
  if (code >= 95) return (BarIcons.boltFill, 'Thunderstorm');
  return (BarIcons.sunMax, 'Cloudy');
}

/// Weather widget (Small 1×1, Medium 2×1, Large 2×2) backed by Open-Meteo
/// with a 30-minute cache, inline city editor, and graceful offline fallback.
class WeatherWidget extends StatefulWidget {
  const WeatherWidget({
    this.size = KitWidgetSize.medium,
    this.glass = true,
    super.key,
  });

  final KitWidgetSize size;
  final bool glass;

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  _WeatherData? _data = _WeatherCache.last;
  bool _loading = false;
  bool _editingCity = false;
  final TextEditingController _cityCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widgetWeatherCity.addListener(_onCityChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widgetWeatherCity.removeListener(_onCityChanged);
    _cityCtrl.dispose();
    super.dispose();
  }

  void _onCityChanged() {
    if (!mounted) return;
    unawaited(_load(force: true));
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() => _loading = true);
    final res = await _WeatherCache.fetch(
      widgetWeatherCity.value,
      force: force,
    );
    if (!mounted) return;
    setState(() {
      _data = res;
      _loading = false;
    });
  }

  void _commitCity() {
    final next = _cityCtrl.text.trim();
    setState(() => _editingCity = false);
    if (next.isNotEmpty) setWidgetWeatherCity(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final style = KitStyle.of(context);
    final ink = widget.glass ? theme.colors.textPrimary : const Color(0xffffffff);
    final sub = widget.glass
        ? theme.colors.textSecondary
        : const Color(0xccffffff);
    final accent = style.accent(theme);
    final data = _data;
    final (icon, condKey) = _describeWmo(data?.code ?? 0);
    final cityLabel = data?.city ?? widgetWeatherCity.value;

    if (_editingCity) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              context.tr('City'),
              style: BarType.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: sub,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(style.corner(8)),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: TextField(
                  controller: _cityCtrl,
                  autofocus: true,
                  style: BarType.caption.copyWith(fontSize: 12, color: ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: context.tr('Enter city name'),
                    hintStyle: BarType.caption.copyWith(fontSize: 12, color: sub),
                  ),
                  onSubmitted: (_) => _commitCity(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Pressable(
                  onTap: () => setState(() => _editingCity = false),
                  wash: true,
                  shape: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      context.tr('Cancel'),
                      style: BarType.caption.copyWith(color: sub),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Pressable(
                  onTap: _commitCity,
                  shape: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      context.tr('Save'),
                      style: BarType.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: style.onAccent(theme),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final tempText = data == null ? '--°' : '${data.tempC.round()}°';
    final condText = data == null
        ? context.tr(_loading ? 'Updating…' : (_WeatherCache.lastError ?? 'Offline'))
        : context.tr(condKey);

    if (widget.size == KitWidgetSize.small) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_load(force: true)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      cityLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BarType.title.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  BarGlyph(icon, size: 16, color: accent),
                ],
              ),
              const Spacer(),
              Text(
                tempText,
                style: BarType.title.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w300,
                  height: 1.0,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                condText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BarType.caption.copyWith(fontSize: 11.5, color: sub),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Pressable(
                  onTap: () {
                    _cityCtrl.text = widgetWeatherCity.value;
                    setState(() => _editingCity = true);
                  },
                  shape: BorderRadius.circular(6),
                  wash: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          cityLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BarType.title.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      BarGlyph(BarIcons.chevronRight, size: 10, color: sub),
                    ],
                  ),
                ),
              ),
              Pressable(
                onTap: () => unawaited(_load(force: true)),
                shape: BorderRadius.circular(12),
                wash: true,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: BarGlyph(BarIcons.arrowClockwise, size: 12, color: sub),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                tempText,
                style: BarType.title.copyWith(
                  fontSize: widget.size == KitWidgetSize.large ? 48 : 38,
                  fontWeight: FontWeight.w300,
                  height: 1.0,
                  color: ink,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  BarGlyph(icon, size: 22, color: accent),
                  const SizedBox(height: 4),
                  Text(
                    condText,
                    style: BarType.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  if (data != null)
                    Text(
                      'H:${data.highC.round()}°  L:${data.lowC.round()}°',
                      style: BarType.caption.copyWith(fontSize: 11, color: sub),
                    ),
                ],
              ),
            ],
          ),
          if (widget.size == KitWidgetSize.large && data != null) ...<Widget>[
            const SizedBox(height: 14),
            Container(height: 1, color: ink.withValues(alpha: 0.1)),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.tr('Humidity'),
                        style: BarType.caption.copyWith(
                          fontSize: 11,
                          color: sub,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${data.humidity}%',
                        style: BarType.title.copyWith(
                          fontSize: 15,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.tr('Wind'),
                        style: BarType.caption.copyWith(
                          fontSize: 11,
                          color: sub,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${data.windKmh.round()} km/h',
                        style: BarType.title.copyWith(
                          fontSize: 15,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
