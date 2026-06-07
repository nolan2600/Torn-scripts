// v1.1
import React, {useState, useRef, useEffect, useCallback} from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
  StyleSheet,
  StatusBar,
  Animated,
  Platform,
  KeyboardAvoidingView,
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

// ─── CONSTANTS ───────────────────────────────────────────────────────────────

const STORAGE_KEY = '@phonerecon_keys';

const KEY_FIELDS = [
  {
    id: 'twilioSid',
    label: 'TWILIO ACCOUNT SID',
    hint: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    url: 'twilio.com → Console → Account Info',
  },
  {
    id: 'twilioToken',
    label: 'TWILIO AUTH TOKEN',
    hint: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    url: 'twilio.com → Console → Account Info',
  },
  {
    id: 'numLookupKey',
    label: 'NUMLOOKUP API KEY',
    hint: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    url: 'numlookupapi.com → Dashboard',
  },
  {
    id: 'hibpKey',
    label: 'HAVEIBEENPWNED KEY',
    hint: 'xxxxxxxxxxxxxxxx ($3.50/mo)',
    url: 'haveibeenpwned.com/API/Key',
  },
];

const C = {
  bg: '#0a0a0a',
  surface: '#111111',
  border: '#1e1e1e',
  borderActive: '#2a2a2a',
  cyan: '#00e5ff',
  green: '#00e676',
  orange: '#ff9800',
  red: '#ff1744',
  yellow: '#ffea00',
  muted: '#555',
  text: '#e0e0e0',
  dim: '#888',
};

const LINE_TYPE_COLOR = {
  mobile: C.green,
  landline: C.dim,
  voip: C.orange,
  'toll-free': C.yellow,
  premium: C.red,
};

const MONO = Platform.OS === 'android' ? 'monospace' : 'Menlo';

// ─── HELPERS ─────────────────────────────────────────────────────────────────

function normalizeE164(raw) {
  const digits = raw.replace(/\D/g, '');
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+${digits}`;
  return `+${digits}`;
}

function b64(str) {
  if (typeof btoa !== 'undefined') return btoa(str);
  return Buffer.from(str, 'binary').toString('base64');
}

function maskKey(val) {
  if (!val) return '—';
  if (val.length <= 6) return '•'.repeat(val.length);
  return val.slice(0, 4) + '•'.repeat(val.length - 6) + val.slice(-2);
}

// ─── API CALLS ───────────────────────────────────────────────────────────────

async function fetchTwilio(e164, sid, token) {
  const creds = b64(`${sid}:${token}`);
  const url =
    `https://lookups.twilio.com/v2/PhoneNumbers/${encodeURIComponent(e164)}` +
    `?Fields=line_type_intelligence,caller_name`;
  try {
    const res = await fetch(url, {headers: {Authorization: `Basic ${creds}`}});
    const data = await res.json();
    if (!res.ok) throw new Error(data.message ?? `HTTP ${res.status}`);
    return {
      valid: data.valid,
      countryCode: data.country_code,
      nationalFormat: data.national_format,
      lineType: data.line_type_intelligence?.type ?? null,
      carrier: data.line_type_intelligence?.carrier_name ?? null,
      callerName: data.caller_name?.caller_name ?? null,
      callerType: data.caller_name?.caller_type ?? null,
    };
  } catch (e) {
    return {error: e.message};
  }
}

async function fetchNumLookup(e164, apiKey) {
  const url =
    `https://api.numlookupapi.com/v1/info/${encodeURIComponent(e164)}` +
    `?apikey=${apiKey}`;
  try {
    const res = await fetch(url);
    const data = await res.json();
    if (!res.ok) throw new Error(data.message ?? `HTTP ${res.status}`);
    return {
      country: data.country_name,
      location: data.location,
      carrier: data.carrier,
      lineType: data.line_type,
      localFormat: data.local_format,
    };
  } catch (e) {
    return {error: e.message};
  }
}

async function fetchHIBP(e164, apiKey) {
  const url = `https://haveibeenpwned.com/api/v3/breachedaccount/${encodeURIComponent(e164)}`;
  try {
    const res = await fetch(url, {
      headers: {'hibp-api-key': apiKey, 'user-agent': 'PhoneRecon/1.0'},
    });
    if (res.status === 404) return {breached: false, breachCount: 0, breaches: []};
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    return {
      breached: true,
      breachCount: data.length,
      breaches: data.map(b => ({
        name: b.Name,
        domain: b.Domain,
        breachDate: b.BreachDate,
        dataClasses: b.DataClasses,
      })),
    };
  } catch (e) {
    return {error: e.message};
  }
}

// ─── SHARED UI ───────────────────────────────────────────────────────────────

function Badge({label, color}) {
  return (
    <View style={[s.badge, {borderColor: color}]}>
      <Text style={[s.badgeText, {color}]}>{label.toUpperCase()}</Text>
    </View>
  );
}

function Row({label, value, valueColor}) {
  if (value == null || value === '') return null;
  return (
    <View style={s.row}>
      <Text style={s.rowLabel}>{label}</Text>
      <Text style={[s.rowValue, valueColor ? {color: valueColor} : null]}>
        {String(value)}
      </Text>
    </View>
  );
}

function Section({title, accent, children}) {
  return (
    <View style={s.section}>
      <View style={[s.sectionHead, {borderLeftColor: accent ?? C.cyan}]}>
        <Text style={[s.sectionTitle, {color: accent ?? C.cyan}]}>{title}</Text>
      </View>
      {children}
    </View>
  );
}

// ─── RESULT BLOCKS ───────────────────────────────────────────────────────────

function TwilioBlock({data}) {
  if (!data) return null;
  if (data.error) {
    return (
      <Section title="CARRIER / LINE" accent={C.orange}>
        <Text style={s.errText}>Twilio: {data.error}</Text>
      </Section>
    );
  }
  const ltColor = LINE_TYPE_COLOR[data.lineType?.toLowerCase()] ?? C.muted;
  return (
    <Section title="CARRIER / LINE" accent={C.cyan}>
      <View style={s.badgeRow}>
        {data.lineType && <Badge label={data.lineType} color={ltColor} />}
        {data.valid === false && <Badge label="INVALID" color={C.red} />}
      </View>
      <Row label="Carrier" value={data.carrier} />
      <Row label="Caller Name" value={data.callerName} />
      <Row label="Caller Type" value={data.callerType} />
      <Row label="Country" value={data.countryCode} />
      <Row label="National Format" value={data.nationalFormat} />
    </Section>
  );
}

function NumLookupBlock({data}) {
  if (!data) return null;
  if (data.error) {
    return (
      <Section title="GEO / NETWORK" accent={C.orange}>
        <Text style={s.errText}>NumLookup: {data.error}</Text>
      </Section>
    );
  }
  return (
    <Section title="GEO / NETWORK" accent={C.cyan}>
      <Row label="Country" value={data.country} />
      <Row label="Location" value={data.location} />
      <Row label="Carrier" value={data.carrier} />
      <Row label="Line Type" value={data.lineType} />
      <Row label="Local Format" value={data.localFormat} />
    </Section>
  );
}

function HIBPBlock({data}) {
  if (!data) return null;
  if (data.error) {
    return (
      <Section title="BREACH CHECK" accent={C.orange}>
        <Text style={s.errText}>HIBP: {data.error}</Text>
      </Section>
    );
  }
  if (!data.breached) {
    return (
      <Section title="BREACH CHECK" accent={C.green}>
        <View style={s.badgeRow}>
          <Badge label="NO BREACHES FOUND" color={C.green} />
        </View>
      </Section>
    );
  }
  return (
    <Section title="BREACH CHECK" accent={C.red}>
      <View style={s.badgeRow}>
        <Badge
          label={`${data.breachCount} BREACH${data.breachCount > 1 ? 'ES' : ''}`}
          color={C.red}
        />
      </View>
      {data.breaches.map((b, i) => (
        <View key={i} style={s.breachCard}>
          <Text style={s.breachName}>{b.name}</Text>
          <Text style={s.breachMeta}>
            {b.domain} · {b.breachDate}
          </Text>
          <Text style={s.breachClasses}>{b.dataClasses?.join(', ')}</Text>
        </View>
      ))}
    </Section>
  );
}

// ─── SETTINGS SCREEN ─────────────────────────────────────────────────────────

function SettingsScreen({keys, onSave}) {
  const [draft, setDraft] = useState({...keys});
  const [revealed, setRevealed] = useState({});
  const [saved, setSaved] = useState(false);

  function toggle(id) {
    setRevealed(prev => ({...prev, [id]: !prev[id]}));
  }

  async function handleSave() {
    await onSave(draft);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }

  const allSet = KEY_FIELDS.every(f => draft[f.id]?.trim());

  return (
    <KeyboardAvoidingView
      style={{flex: 1}}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.settingsContent}
        keyboardShouldPersistTaps="handled">

        <Text style={s.settingsIntro}>
          Keys are stored on-device only via AsyncStorage.{'\n'}
          They are never sent anywhere except the respective API.
        </Text>

        {KEY_FIELDS.map(field => {
          const val = draft[field.id] ?? '';
          const isSet = val.trim().length > 0;
          return (
            <View key={field.id} style={s.keyCard}>
              <View style={s.keyCardHeader}>
                <Text style={s.keyLabel}>{field.label}</Text>
                <View style={[s.keyDot, {backgroundColor: isSet ? C.green : C.muted}]} />
              </View>
              <Text style={s.keyUrl}>{field.url}</Text>
              <View style={s.keyInputRow}>
                <TextInput
                  style={s.keyInput}
                  value={val}
                  onChangeText={text => setDraft(prev => ({...prev, [field.id]: text}))}
                  placeholder={field.hint}
                  placeholderTextColor={C.muted}
                  secureTextEntry={!revealed[field.id]}
                  autoCapitalize="none"
                  autoCorrect={false}
                  spellCheck={false}
                />
                <TouchableOpacity
                  style={s.revealBtn}
                  onPress={() => toggle(field.id)}
                  activeOpacity={0.7}>
                  <Text style={s.revealBtnText}>
                    {revealed[field.id] ? 'HIDE' : 'SHOW'}
                  </Text>
                </TouchableOpacity>
              </View>
              {isSet && !revealed[field.id] && (
                <Text style={s.maskedPreview}>{maskKey(val)}</Text>
              )}
            </View>
          );
        })}

        <TouchableOpacity
          style={[s.saveBtn, saved && s.saveBtnDone]}
          onPress={handleSave}
          activeOpacity={0.8}>
          <Text style={s.saveBtnText}>
            {saved ? '✓  SAVED' : allSet ? 'SAVE KEYS' : 'SAVE (INCOMPLETE)'}
          </Text>
        </TouchableOpacity>

        <View style={{height: 40}} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

// ─── MAIN APP ────────────────────────────────────────────────────────────────

export default function App() {
  const [screen, setScreen] = useState('lookup'); // 'lookup' | 'settings'
  const [keys, setKeys] = useState({
    twilioSid: '',
    twilioToken: '',
    numLookupKey: '',
    hibpKey: '',
  });
  const [keysLoaded, setKeysLoaded] = useState(false);

  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const pulse = useRef(new Animated.Value(1)).current;
  const pulseAnim = useRef(null);

  useEffect(() => {
    AsyncStorage.getItem(STORAGE_KEY)
      .then(raw => {
        if (raw) setKeys(JSON.parse(raw));
      })
      .finally(() => setKeysLoaded(true));
  }, []);

  const saveKeys = useCallback(async newKeys => {
    setKeys(newKeys);
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(newKeys));
  }, []);

  const keysConfigured =
    keys.twilioSid && keys.twilioToken && keys.numLookupKey && keys.hibpKey;

  async function runLookup() {
    const num = input.trim();
    if (!num) return;
    if (!keysConfigured) {
      setScreen('settings');
      return;
    }

    setLoading(true);
    setResult(null);
    setError(null);

    pulseAnim.current = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, {toValue: 0.3, duration: 500, useNativeDriver: true}),
        Animated.timing(pulse, {toValue: 1, duration: 500, useNativeDriver: true}),
      ]),
    );
    pulseAnim.current.start();

    try {
      const e164 = normalizeE164(num);
      const [twilio, numLookup, hibp] = await Promise.all([
        fetchTwilio(e164, keys.twilioSid, keys.twilioToken),
        fetchNumLookup(e164, keys.numLookupKey),
        fetchHIBP(e164, keys.hibpKey),
      ]);
      setResult({e164, timestamp: new Date().toISOString(), twilio, numLookup, hibp});
    } catch (e) {
      setError(e.message);
    } finally {
      pulseAnim.current?.stop();
      pulse.setValue(1);
      setLoading(false);
    }
  }

  if (!keysLoaded) {
    return (
      <View style={[s.root, {alignItems: 'center', justifyContent: 'center'}]}>
        <ActivityIndicator color={C.cyan} />
      </View>
    );
  }

  return (
    <View style={s.root}>
      <StatusBar barStyle="light-content" backgroundColor={C.bg} />

      {/* Header */}
      <View style={s.header}>
        <View>
          <Text style={s.headerTitle}>PHONE RECON</Text>
          <Text style={s.headerSub}>CARRIER · GEO · BREACH</Text>
        </View>
        <TouchableOpacity
          style={s.settingsToggle}
          onPress={() => setScreen(screen === 'settings' ? 'lookup' : 'settings')}
          activeOpacity={0.7}>
          <Text
            style={[
              s.settingsToggleText,
              screen === 'settings' && {color: C.cyan},
            ]}>
            {screen === 'settings' ? '← BACK' : '⚙ KEYS'}
          </Text>
          {!keysConfigured && screen !== 'settings' && (
            <View style={s.alertDot} />
          )}
        </TouchableOpacity>
      </View>

      {screen === 'settings' ? (
        <SettingsScreen keys={keys} onSave={saveKeys} />
      ) : (
        <>
          {/* Input row */}
          <View style={s.inputRow}>
            <TextInput
              style={s.input}
              value={input}
              onChangeText={setInput}
              placeholder="+1 555 000 0000"
              placeholderTextColor={C.muted}
              keyboardType="phone-pad"
              returnKeyType="search"
              onSubmitEditing={runLookup}
              autoCorrect={false}
            />
            <TouchableOpacity
              style={[s.btn, loading && s.btnDim]}
              onPress={runLookup}
              disabled={loading}
              activeOpacity={0.7}>
              {loading ? (
                <Animated.Text style={[s.btnText, {opacity: pulse, color: '#000'}]}>
                  ···
                </Animated.Text>
              ) : (
                <Text style={s.btnText}>RUN</Text>
              )}
            </TouchableOpacity>
          </View>

          {!keysConfigured && (
            <TouchableOpacity
              style={s.keysBanner}
              onPress={() => setScreen('settings')}
              activeOpacity={0.8}>
              <Text style={s.keysBannerText}>
                ⚠  API keys not configured — tap to set up
              </Text>
            </TouchableOpacity>
          )}

          {loading && (
            <View style={s.loadingRow}>
              <ActivityIndicator color={C.cyan} size="small" />
              <Text style={s.loadingText}>QUERYING 3 SOURCES…</Text>
            </View>
          )}

          {error && (
            <View style={s.errBanner}>
              <Text style={s.errBannerText}>ERROR: {error}</Text>
            </View>
          )}

          {result ? (
            <ScrollView
              style={s.scroll}
              contentContainerStyle={s.scrollContent}
              keyboardShouldPersistTaps="handled">
              <View style={s.targetBlock}>
                <Text style={s.targetLabel}>TARGET</Text>
                <Text style={s.targetNumber}>{result.e164}</Text>
                <Text style={s.targetTs}>{result.timestamp}</Text>
              </View>
              <TwilioBlock data={result.twilio} />
              <NumLookupBlock data={result.numLookup} />
              <HIBPBlock data={result.hibp} />
            </ScrollView>
          ) : (
            !loading && !error && (
              <View style={s.empty}>
                <Text style={s.emptyText}>
                  {keysConfigured
                    ? '> ENTER TARGET NUMBER'
                    : '> CONFIGURE API KEYS TO BEGIN'}
                </Text>
              </View>
            )
          )}
        </>
      )}
    </View>
  );
}

// ─── STYLES ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  root: {flex: 1, backgroundColor: C.bg},

  header: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    paddingTop: Platform.OS === 'android' ? 48 : 60,
    paddingHorizontal: 20,
    paddingBottom: 16,
    borderBottomWidth: 1,
    borderBottomColor: C.border,
  },
  headerTitle: {
    fontFamily: MONO,
    fontSize: 22,
    fontWeight: '700',
    color: C.cyan,
    letterSpacing: 6,
  },
  headerSub: {
    fontFamily: MONO,
    fontSize: 10,
    color: C.muted,
    letterSpacing: 4,
    marginTop: 2,
  },
  settingsToggle: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingBottom: 2,
    gap: 6,
  },
  settingsToggleText: {
    fontFamily: MONO,
    fontSize: 11,
    color: C.dim,
    letterSpacing: 2,
  },
  alertDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: C.orange,
  },

  keysBanner: {
    marginHorizontal: 16,
    marginBottom: 4,
    padding: 12,
    backgroundColor: '#1a0f00',
    borderWidth: 1,
    borderColor: C.orange,
    borderRadius: 4,
  },
  keysBannerText: {
    fontFamily: MONO,
    fontSize: 12,
    color: C.orange,
    letterSpacing: 1,
  },

  inputRow: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 10,
  },
  input: {
    flex: 1,
    height: 48,
    backgroundColor: C.surface,
    borderWidth: 1,
    borderColor: C.border,
    borderRadius: 4,
    paddingHorizontal: 14,
    fontFamily: MONO,
    fontSize: 16,
    color: C.text,
  },
  btn: {
    width: 72,
    height: 48,
    backgroundColor: C.cyan,
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnDim: {backgroundColor: '#004d5e'},
  btnText: {
    fontFamily: MONO,
    fontSize: 13,
    fontWeight: '700',
    color: '#000',
    letterSpacing: 2,
  },

  loadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    gap: 10,
    marginBottom: 4,
  },
  loadingText: {
    fontFamily: MONO,
    fontSize: 11,
    color: C.cyan,
    letterSpacing: 2,
  },

  errBanner: {
    margin: 16,
    padding: 12,
    backgroundColor: '#1a0007',
    borderWidth: 1,
    borderColor: C.red,
    borderRadius: 4,
  },
  errBannerText: {fontFamily: MONO, fontSize: 12, color: C.red},

  scroll: {flex: 1},
  scrollContent: {paddingBottom: 40},

  targetBlock: {
    margin: 16,
    padding: 16,
    backgroundColor: C.surface,
    borderWidth: 1,
    borderColor: C.cyan,
    borderRadius: 4,
  },
  targetLabel: {
    fontFamily: MONO,
    fontSize: 9,
    color: C.muted,
    letterSpacing: 4,
    marginBottom: 4,
  },
  targetNumber: {
    fontFamily: MONO,
    fontSize: 28,
    color: C.cyan,
    fontWeight: '700',
    letterSpacing: 2,
  },
  targetTs: {fontFamily: MONO, fontSize: 9, color: C.muted, marginTop: 6},

  section: {
    marginHorizontal: 16,
    marginBottom: 12,
    backgroundColor: C.surface,
    borderWidth: 1,
    borderColor: C.border,
    borderRadius: 4,
    overflow: 'hidden',
  },
  sectionHead: {
    borderLeftWidth: 3,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: C.border,
  },
  sectionTitle: {
    fontFamily: MONO,
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 3,
  },

  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderBottomWidth: 1,
    borderBottomColor: C.border,
  },
  rowLabel: {fontFamily: MONO, fontSize: 11, color: C.muted, flex: 1},
  rowValue: {fontFamily: MONO, fontSize: 12, color: C.text, flex: 2, textAlign: 'right'},

  badgeRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  badge: {borderWidth: 1, borderRadius: 3, paddingHorizontal: 8, paddingVertical: 3},
  badgeText: {fontFamily: MONO, fontSize: 9, fontWeight: '700', letterSpacing: 2},

  breachCard: {
    borderTopWidth: 1,
    borderTopColor: C.border,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  breachName: {fontFamily: MONO, fontSize: 13, color: C.red, fontWeight: '700'},
  breachMeta: {fontFamily: MONO, fontSize: 10, color: C.dim, marginTop: 2},
  breachClasses: {fontFamily: MONO, fontSize: 10, color: C.orange, marginTop: 4},

  errText: {fontFamily: MONO, fontSize: 11, color: C.orange, padding: 14},

  empty: {flex: 1, alignItems: 'center', justifyContent: 'center'},
  emptyText: {fontFamily: MONO, fontSize: 13, color: C.muted, letterSpacing: 1},

  // Settings
  settingsContent: {padding: 16, paddingTop: 12},
  settingsIntro: {
    fontFamily: MONO,
    fontSize: 10,
    color: C.muted,
    lineHeight: 16,
    marginBottom: 16,
    borderLeftWidth: 2,
    borderLeftColor: C.border,
    paddingLeft: 12,
  },
  keyCard: {
    backgroundColor: C.surface,
    borderWidth: 1,
    borderColor: C.border,
    borderRadius: 4,
    padding: 14,
    marginBottom: 12,
  },
  keyCardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 4,
  },
  keyLabel: {
    fontFamily: MONO,
    fontSize: 10,
    fontWeight: '700',
    color: C.cyan,
    letterSpacing: 2,
  },
  keyDot: {width: 8, height: 8, borderRadius: 4},
  keyUrl: {
    fontFamily: MONO,
    fontSize: 9,
    color: C.muted,
    marginBottom: 10,
    letterSpacing: 1,
  },
  keyInputRow: {flexDirection: 'row', gap: 8, alignItems: 'center'},
  keyInput: {
    flex: 1,
    height: 42,
    backgroundColor: C.bg,
    borderWidth: 1,
    borderColor: C.borderActive,
    borderRadius: 4,
    paddingHorizontal: 12,
    fontFamily: MONO,
    fontSize: 13,
    color: C.text,
  },
  revealBtn: {
    height: 42,
    paddingHorizontal: 12,
    backgroundColor: C.bg,
    borderWidth: 1,
    borderColor: C.borderActive,
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  revealBtnText: {
    fontFamily: MONO,
    fontSize: 9,
    color: C.dim,
    letterSpacing: 2,
  },
  maskedPreview: {
    fontFamily: MONO,
    fontSize: 10,
    color: C.muted,
    marginTop: 8,
    letterSpacing: 2,
  },

  saveBtn: {
    height: 52,
    backgroundColor: C.cyan,
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 4,
  },
  saveBtnDone: {backgroundColor: C.green},
  saveBtnText: {
    fontFamily: MONO,
    fontSize: 14,
    fontWeight: '700',
    color: '#000',
    letterSpacing: 3,
  },
});
