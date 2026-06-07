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

// ─── CONFIG ────────────────────────────────────────────────────────────────
const SERVER_URL = 'http://YOUR_LOCAL_IP:3000'; // e.g. http://192.168.1.42:3000
const API_SECRET = 'change_me_to_a_random_string_32chars';
// ───────────────────────────────────────────────────────────────────────────

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
  unknown: C.muted,
};

function Badge({label, color}) {
  return (
    <View style={[styles.badge, {borderColor: color}]}>
      <Text style={[styles.badgeText, {color}]}>{label.toUpperCase()}</Text>
    </View>
  );
}

function Row({label, value, valueColor}) {
  if (value == null || value === '') return null;
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={[styles.rowValue, valueColor ? {color: valueColor} : null]}>
        {String(value)}
      </Text>
    </View>
  );
}

function Section({title, children, accent}) {
  return (
    <View style={styles.section}>
      <View style={[styles.sectionHeader, {borderLeftColor: accent ?? C.cyan}]}>
        <Text style={[styles.sectionTitle, {color: accent ?? C.cyan}]}>
          {title}
        </Text>
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
        <Text style={styles.errorText}>Twilio error: {data.error}</Text>
      </Section>
    );
  }
  const ltColor = LINE_TYPE_COLOR[data.lineType?.toLowerCase()] ?? C.muted;
  return (
    <Section title="CARRIER / LINE" accent={C.cyan}>
      <View style={styles.badgeRow}>
        {data.lineType && (
          <Badge label={data.lineType} color={ltColor} />
        )}
        {data.valid === false && <Badge label="INVALID" color={C.red} />}
        {data.lineTypeConfidence === 'high' && (
          <Badge label="HIGH CONFIDENCE" color={C.green} />
        )}
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
        <Text style={styles.errorText}>NumLookup error: {data.error}</Text>
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
        <Text style={styles.errorText}>HIBP error: {data.error}</Text>
      </Section>
    );
  }
  if (!data.breached) {
    return (
      <Section title="BREACH CHECK" accent={C.green}>
        <View style={styles.badgeRow}>
          <Badge label="NO BREACHES FOUND" color={C.green} />
        </View>
      </Section>
    );
  }
  return (
    <Section title="BREACH CHECK" accent={C.red}>
      <View style={styles.badgeRow}>
        <Badge label={`${data.breachCount} BREACH${data.breachCount > 1 ? 'ES' : ''}`} color={C.red} />
      </View>
      {data.breaches.map((b, i) => (
        <View key={i} style={styles.breachCard}>
          <Text style={styles.breachName}>{b.name}</Text>
          <Text style={styles.breachMeta}>
            {b.domain} · {b.breachDate}
          </Text>
          <Text style={styles.breachClasses}>
            {b.dataClasses?.join(', ')}
          </Text>
        </View>
      ))}
    </Section>
  );
}

export default function App() {
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const pulse = useRef(new Animated.Value(1)).current;

  async function runLookup() {
    const num = input.trim();
    if (!num) return;
    setLoading(true);
    setResult(null);
    setError(null);

    Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, {toValue: 0.4, duration: 600, useNativeDriver: true}),
        Animated.timing(pulse, {toValue: 1, duration: 600, useNativeDriver: true}),
      ]),
    ).start();

    try {
      const resp = await fetch(`${SERVER_URL}/lookup`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-secret': API_SECRET,
        },
        body: JSON.stringify({number: num}),
      });
      const json = await resp.json();
      if (!resp.ok) throw new Error(json.error ?? `HTTP ${resp.status}`);
      setResult(json);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      pulse.stopAnimation();
      pulse.setValue(1);
    }
  }

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={C.bg} />

      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>PHONE RECON</Text>
        <Text style={styles.headerSub}>OSINT · CARRIER · BREACH</Text>
      </View>

      {/* Input */}
      <View style={styles.inputRow}>
        <TextInput
          style={styles.input}
          value={input}
          onChangeText={setInput}
          placeholder="+1 (555) 000-0000"
          placeholderTextColor={C.muted}
          keyboardType="phone-pad"
          returnKeyType="search"
          onSubmitEditing={runLookup}
          autoCorrect={false}
        />
        <TouchableOpacity
          style={[styles.btn, loading && styles.btnDisabled]}
          onPress={runLookup}
          disabled={loading}
          activeOpacity={0.7}>
          {loading ? (
            <Animated.Text style={[styles.btnText, {opacity: pulse}]}>
              ···
            </Animated.Text>
          ) : (
            <Text style={styles.btnText}>RUN</Text>
          )}
        </TouchableOpacity>
      </View>

      {loading && (
        <View style={styles.loadingRow}>
          <ActivityIndicator color={C.cyan} size="small" />
          <Text style={styles.loadingText}>QUERYING SOURCES…</Text>
        </View>
      )}

      {error && (
        <View style={styles.errorBanner}>
          <Text style={styles.errorBannerText}>ERROR: {error}</Text>
        </View>
      )}

      {result && (
        <ScrollView
          style={styles.scroll}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled">

          {/* Target line */}
          <View style={styles.targetBlock}>
            <Text style={styles.targetLabel}>TARGET</Text>
            <Text style={styles.targetNumber}>{result.e164}</Text>
            <Text style={styles.targetTs}>{result.timestamp}</Text>
          </View>

          <TwilioBlock data={result.twilio} />
          <NumLookupBlock data={result.numLookup} />
          <HIBPBlock data={result.hibp} />
        </ScrollView>
      )}

      {!result && !loading && !error && (
        <View style={styles.emptyState}>
          <Text style={styles.emptyText}>
            {'> ENTER TARGET NUMBER TO BEGIN'}
          </Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: {flex: 1, backgroundColor: C.bg},

  header: {
    paddingTop: Platform.OS === 'android' ? 48 : 60,
    paddingHorizontal: 20,
    paddingBottom: 16,
    borderBottomWidth: 1,
    borderBottomColor: C.border,
  },
  headerTitle: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 22,
    fontWeight: '700',
    color: C.cyan,
    letterSpacing: 6,
  },
  headerSub: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
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
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
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
  btnDisabled: {backgroundColor: '#004d5e'},
  btnText: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
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
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 11,
    color: C.cyan,
    letterSpacing: 2,
  },

  errorBanner: {
    marginHorizontal: 16,
    padding: 12,
    backgroundColor: '#1a0007',
    borderWidth: 1,
    borderColor: C.red,
    borderRadius: 4,
  },
  errorBannerText: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 12,
    color: C.red,
  },

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
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 9,
    color: C.muted,
    letterSpacing: 4,
    marginBottom: 4,
  },
  targetNumber: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 28,
    color: C.cyan,
    fontWeight: '700',
    letterSpacing: 2,
  },
  targetTs: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 9,
    color: C.muted,
    marginTop: 6,
  },

  section: {
    marginHorizontal: 16,
    marginBottom: 12,
    backgroundColor: C.surface,
    borderWidth: 1,
    borderColor: C.border,
    borderRadius: 4,
    overflow: 'hidden',
  },
  sectionHeader: {
    borderLeftWidth: 3,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: C.border,
  },
  sectionTitle: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
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
  rowLabel: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 11,
    color: C.muted,
    flex: 1,
  },
  rowValue: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 12,
    color: C.text,
    flex: 2,
    textAlign: 'right',
  },

  badgeRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  badge: {
    borderWidth: 1,
    borderRadius: 3,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  badgeText: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 2,
  },

  breachCard: {
    borderTopWidth: 1,
    borderTopColor: C.border,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  breachName: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 13,
    color: C.red,
    fontWeight: '700',
  },
  breachMeta: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 10,
    color: C.dim,
    marginTop: 2,
  },
  breachClasses: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 10,
    color: C.orange,
    marginTop: 4,
  },

  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyText: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 13,
    color: C.muted,
    letterSpacing: 1,
  },

  errorText: {
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Menlo',
    fontSize: 11,
    color: C.orange,
    padding: 14,
  },
});
