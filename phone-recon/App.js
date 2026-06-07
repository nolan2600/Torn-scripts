import React, {useState, useRef} from 'react';
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
} from 'react-native';
import {CONFIG} from './config';

// ─── HELPERS ────────────────────────────────────────────────────────────────

function normalizeE164(raw) {
  const digits = raw.replace(/\D/g, '');
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+${digits}`;
  return `+${digits}`;
}

// btoa is available in React Native (Hermes). Fallback for older setups.
function b64(str) {
  if (typeof btoa !== 'undefined') return btoa(str);
  return Buffer.from(str, 'binary').toString('base64');
}

// ─── API CALLS ──────────────────────────────────────────────────────────────

async function fetchTwilio(e164) {
  const creds = b64(`${CONFIG.TWILIO_ACCOUNT_SID}:${CONFIG.TWILIO_AUTH_TOKEN}`);
  const url =
    `https://lookups.twilio.com/v2/PhoneNumbers/${encodeURIComponent(e164)}` +
    `?Fields=line_type_intelligence,caller_name`;
  try {
    const res = await fetch(url, {
      headers: {Authorization: `Basic ${creds}`},
    });
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

async function fetchNumLookup(e164) {
  const url =
    `https://api.numlookupapi.com/v1/info/${encodeURIComponent(e164)}` +
    `?apikey=${CONFIG.NUMLOOKUP_API_KEY}`;
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
      intlFormat: data.international_format,
    };
  } catch (e) {
    return {error: e.message};
  }
}

async function fetchHIBP(e164) {
  const url = `https://haveibeenpwned.com/api/v3/breachedaccount/${encodeURIComponent(e164)}`;
  try {
    const res = await fetch(url, {
      headers: {
        'hibp-api-key': CONFIG.HIBP_API_KEY,
        'user-agent': 'PhoneRecon/1.0',
      },
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

// ─── COLORS ─────────────────────────────────────────────────────────────────

const C = {
  bg: '#0a0a0a',
  surface: '#111111',
  border: '#1e1e1e',
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

// ─── UI COMPONENTS ───────────────────────────────────────────────────────────

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

// ─── MAIN ────────────────────────────────────────────────────────────────────

export default function App() {
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const pulse = useRef(new Animated.Value(1)).current;
  const pulseAnim = useRef(null);

  async function runLookup() {
    const num = input.trim();
    if (!num) return;

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
      // All three APIs fire in parallel
      const [twilio, numLookup, hibp] = await Promise.all([
        fetchTwilio(e164),
        fetchNumLookup(e164),
        fetchHIBP(e164),
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

  return (
    <View style={s.root}>
      <StatusBar barStyle="light-content" backgroundColor={C.bg} />

      <View style={s.header}>
        <Text style={s.headerTitle}>PHONE RECON</Text>
        <Text style={s.headerSub}>CARRIER · GEO · BREACH</Text>
      </View>

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
            <Text style={s.emptyText}>{'> ENTER TARGET NUMBER'}</Text>
          </View>
        )
      )}
    </View>
  );
}

// ─── STYLES ──────────────────────────────────────────────────────────────────

const s = StyleSheet.create({
  root: {flex: 1, backgroundColor: C.bg},

  header: {
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
});
